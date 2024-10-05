import AVFoundation
import Accelerate
import AppKit
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import os
import os.signpost



/// A class for generating mosaic images from video files.
public class MosaicGenerator {
    // MARK: - Enums

    /// Rendering modes for mosaic generation.
    public enum RenderingMode {
        case auto
        case metal
        case classic
    }

    // MARK: - Nested Types

    /// Represents the layout of thumbnails in the mosaic.
    struct MosaicLayout {
        let rows: Int
        let cols: Int
        let thumbnailSize: CGSize
        let positions: [(x: Int, y: Int)]
        let thumbCount: Int
    }

    /// Represents the uniforms for rendering the mosaic.
    struct Uniforms {
        var position: SIMD2<Float>
        var size: SIMD2<Float>
        var renderType: Int32
        var padding: Int32  // Add padding to ensure 16-byte alignment
    }

    /// Represents the progress information for the mosaic generation process.
    public struct ProgressInfo {
        public let progress: Double
        public let currentFile: String
        public let processedFiles: Int
        public let totalFiles: Int
        public let currentStage: String
        public let elapsedTime: TimeInterval
        public let estimatedTimeRemaining: TimeInterval
    }
    // MARK: - Properties

    private let debug: Bool
    private let renderingMode: RenderingMode
    private let maxConcurrentOperations: Int
    private let time: Bool
    private let skip: Bool
    private let logger: Logger
    private let smart: Bool
    private let signposter: OSSignposter
    private let signpostID: OSSignpostID
    private let createPreview: Bool
    private let batchSize: Int
    private let accurate: Bool
    private var progressG: Progress
    private var progressT: Progress
    private var progressM: Progress
    private var progressHandlerG: ((ProgressInfo) -> Void)?
    private var progressHandlerT: ((Double) -> Void)?
    private var progressHandlerM: ((Double) -> Void)?
    private var isCancelled: Bool = false
    private var saveAtRoot: Bool = false
    private var separate: Bool = true
    private var summary: Bool = true
    private var videosFiles: [(URL, URL)]
    private var totalfiles: Int = 0
    private var processedFiles: Int = 0
    private var startTime: CFAbsoluteTime

    // MARK: - Initialization

    /// Initializes the MosaicGenerator with the specified parameters.
    ///
    /// - Parameters:
    ///   - debug: Enable debug logging.
    ///   - renderingMode: The rendering mode for mosaic generation.
    ///   - maxConcurrentOperations: The maximum number of concurrent operations.
    ///   - timeStamps: Enable time stamping for logging.
    ///   - skip: Skip processing if true.
    ///   - smart: Enable smart processing.
    public init(
        debug: Bool = false, renderingMode: RenderingMode = .auto,
        maxConcurrentOperations: Int? = nil, timeStamps: Bool = false, skip: Bool = true,
        smart: Bool = false, createPreview: Bool = false, batchsize: Int = 24,
        accurate: Bool = false, saveAtRoot: Bool = false, separate: Bool = true,
        summary: Bool = false
    ) {
        self.debug = debug
        self.renderingMode = renderingMode
        self.time = timeStamps
        self.skip = skip
        self.smart = smart
        self.createPreview = createPreview
        self.logger = Logger(subsystem: "com.fd.MosaicGenerator", category: "MosaicGeneration")
        self.signposter = OSSignposter()
        self.signpostID = signposter.makeSignpostID()
        self.maxConcurrentOperations = maxConcurrentOperations ?? 24
        self.batchSize = batchsize
        self.accurate = accurate
        self.separate = separate
        self.summary = summary
        self.videosFiles = []
        self.startTime = CFAbsoluteTimeGetCurrent()

        self.progressG = Progress(totalUnitCount: 1)  // Initialize with 1, we'll update this later

        self.progressT = Progress(totalUnitCount: 1)  // Initialize with 1, we'll update this later
        self.progressG.addChild(self.progressT, withPendingUnitCount: 0)
        self.progressM = Progress(totalUnitCount: 1)  // Initialize with 1, we'll update this later
        self.saveAtRoot = saveAtRoot

        logger.log(
            level: .info,
            "MosaicGenerator initialized with debug: \(debug), maxConcurrentOperations: \(self.maxConcurrentOperations), timeStamps: \(timeStamps), skip: \(skip), smart: \(smart), createPreview: \(createPreview), batchSize: \(batchsize), accurate: \(accurate)"
        )
    }

    // MARK: - Public Methods
    public func setProgressHandlerG(_ handler: @escaping (ProgressInfo) -> Void) {
        self.progressHandlerG = handler
    }

    public func setProgressHandlerT(_ handler: @escaping (Double) -> Void) {
        self.progressHandlerT = handler
    }
    public func setProgressHandlerM(_ handler: @escaping (Double) -> Void) {
        self.progressHandlerM = handler
    }
    public func cancelProcessing() {
        isCancelled = true
    }
    public func getProgressSize() -> Double {
        return Double(self.progressG.totalUnitCount)
    }
    
    /// Updates the global progress of the mosaic generation process.
    ///
    /// - Parameters:
    ///   - currentFile: The name of the file currently being processed.
    ///   - processedFiles: The number of files that have been processed so far.
    ///   - totalFiles: The total number of files to be processed.
    ///   - currentStage: A string describing the current stage of the process.
    ///   - startTime: The time when the entire process started.
    private func updateProgressG(
        currentFile: String, processedFiles: Int, totalFiles: Int, currentStage: String,
        startTime: CFAbsoluteTime
    ) {
        // Calculate the time elapsed since the start of the process
        let elapsedTime = CFAbsoluteTimeGetCurrent() - startTime
        
        // Get the current progress as a fraction
        let progress = self.progressG.fractionCompleted
        
        // Initialize the estimated time remaining
        var estimatedTimeRemaining = TimeInterval(0.0)
        
        // Calculate the estimated time remaining if there are files to process
        if totalFiles > 0 {
            do {
                // Estimate time remaining based on progress and elapsed time
                try estimatedTimeRemaining = elapsedTime / progress - elapsedTime
            } catch {
                // If there's an error (e.g., division by zero), set remaining time to 0
                estimatedTimeRemaining = 0.0
            }
        }
        
        // Create a ProgressInfo object with all the current progress information
        let progressInfo = ProgressInfo(
            progress: progress,
            currentFile: currentFile,
            processedFiles: processedFiles,
            totalFiles: self.totalfiles,
            currentStage: currentStage,
            elapsedTime: elapsedTime,
            estimatedTimeRemaining: estimatedTimeRemaining
        )
        
        // Update the progress on the main thread to ensure UI updates are thread-safe
        DispatchQueue.main.async {
            self.progressHandlerG?(progressInfo)
        }
    }

    /// Processes an individual video file and generates a mosaic image.
    ///
    /// - Parameters:
    ///   - videoFile: The URL of the video file to process.
    ///   - width: The width of the mosaic image.
    ///   - density: The density of the mosaic image.
    ///   - format: The format of the mosaic image.
    ///   - overwrite: Overwrite existing files if true.
    /// Processes an individual video file and generates a mosaic image.
    ///
    /// - Parameters:
    ///   - videoFile: The URL of the video file to process.
    ///   - width: The width of the mosaic image.
    ///   - density: The density of the mosaic image.
    ///   - format: The format of the mosaic image.
    ///   - overwrite: Overwrite existing files if true.
    ///   - preview: Generate a preview if true.
    ///   - outputDirectory: The directory to save the output file.
    ///   - accurate: Use accurate mode for thumbnail extraction if true.
    /// - Returns: The URL of the generated mosaic image.
    /// - Throws: An error if the processing fails.
    public func processIndivFile(
        videoFile: URL, width: Int, density: String, format: String, overwrite: Bool, preview: Bool,
        outputDirectory: URL, accurate: Bool
    ) async throws -> URL {

        // Log the start of processing for this file
        logger.log(level: .info, "Processing file: \(videoFile.standardizedFileURL)")
        
        // Create an asset from the video file
        let asset = AVURLAsset(url: videoFile)
        
        // Record the start time for this file's processing
        let TstartTime = CFAbsoluteTimeGetCurrent()
        
        // Use defer to ensure these actions are performed at the end of the function
        defer {
            // Calculate and log the total processing time for this file
            let endTime = CFAbsoluteTimeGetCurrent()
            logger.log(
                level: .info,
                "Mosaic generation completed in \(String(format: "%.2f", endTime - TstartTime)) seconds for \(videoFile.standardizedFileURL)"
            )
            
            // Increment the count of processed files
            self.processedFiles += 1
            
            // Update the progress information
            updateProgressG(
                currentFile: videoFile.lastPathComponent, processedFiles: self.processedFiles,
                totalFiles: self.totalfiles, currentStage: "Processing Files",
                startTime: self.startTime)
            
            // Increment the progress counter
            self.progressG.completedUnitCount += 1
        }

        // Process the video to extract metadata
        let metadata = try await self.processVideo(file: videoFile, asset: asset)

        // Design the mosaic layout based on the metadata and input parameters
        let mosaicLayout = try await self.mosaicDesign(
            metadata: metadata, width: width, density: density)
        
        // Get the number of thumbnails needed for the mosaic
        let thumbnailCount = mosaicLayout.thumbCount
        
        // Log the start of thumbnail extraction
        logger.log(level: .debug, "Extracting thumbnails for \(videoFile.standardizedFileURL)")
        try await self.extractThumbnailsWithTimestamps4( from: metadata.file,
                                                         count: thumbnailCount,
                                                         asset: asset,
                                                         thSize: mosaicLayout.thumbnailSize,
                                                         preview: false,
                                                         accurate: accurate
                                                     )
        // Extract thumbnails with their timestamps
        let thumbnailsWithTimestamps = try await self.extractThumbnailsWithTimestamps3(
            from: metadata.file,
            count: thumbnailCount,
            asset: asset,
            thSize: mosaicLayout.thumbnailSize,
            preview: preview,
            accurate: accurate
        )
        
        // Calculate the output size of the mosaic
        let outputSize = CGSize(
            width: Int(mosaicLayout.cols * Int(mosaicLayout.thumbnailSize.width)),
            height: Int(mosaicLayout.rows * Int(mosaicLayout.thumbnailSize.height)))

        // Log the start of mosaic generation
        logger.log(level: .debug, "Generating mosaic for \(videoFile.standardizedFileURL)")
        
        // Generate the mosaic image
        let mosaic = try await withCheckedThrowingContinuation { continuation in
            autoreleasepool {
                do {
                    switch renderingMode {
                    case .auto, .classic:
                        // Record start time for classic rendering
                        let startTimeC = CFAbsoluteTimeGetCurrent()
                        
                        // Generate the mosaic image using the classic method
                        let result = try self.generateOptMosaicImagebatch2(
                            thumbnailsWithTimestamps: thumbnailsWithTimestamps,
                            layout: mosaicLayout, outputSize: outputSize, metadata: metadata)
                        
                        // Calculate and log the time taken for classic rendering
                        let endTimeC = CFAbsoluteTimeGetCurrent()
                        logger.log(
                            level: .info,
                            "Mosaic generation without metal completed in \(String(format: "%.2f", endTimeC - startTimeC)) seconds for \(videoFile.standardizedFileURL)"
                        )
                        continuation.resume(returning: result)
                    case .metal:
                        // Metal rendering not implemented in this block
                        break
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        
        // Determine the final output directory
        var finalOutputDirectory: URL
        if self.separate {
            finalOutputDirectory = outputDirectory.appendingPathComponent(
                metadata.type, isDirectory: true)
        } else {
            finalOutputDirectory = outputDirectory
        }
        
        // Log the start of saving the mosaic
        logger.log(level: .debug, "Saving mosaic for \(videoFile.standardizedFileURL)")

        // Save the mosaic and return the URL of the saved file
        return try await self.saveMosaic(
            mosaic: mosaic,
            for: videoFile,
            in: finalOutputDirectory,
            format: format,
            overwrite: overwrite,
            width: width,
            density: density,
            type: metadata.type
        )
    }

    // Function to process a QuickLook file and generate a mosaic image
    public func processQLFile(videoFile: URL, width: Int, density: String, accurate: Bool)
        -> NSImage
    {
        // Log the start of processing for the given video file
        logger.log(level: .info, "Processing file: \(videoFile.standardizedFileURL)")
        
        // Create an AVURLAsset from the video file
        let asset = AVURLAsset(url: videoFile)
        
        // Record the start time for performance measurement
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Use defer to ensure logging of completion time, regardless of how the function exits
        defer {
            let endTime = CFAbsoluteTimeGetCurrent()
            logger.log(
                level: .info,
                "Mosaic generation completed in \(String(format: "%.2f", endTime - startTime)) seconds for \(videoFile.standardizedFileURL)"
            )
            // Uncomment the following line if progress tracking is needed
            // self.progress.completedUnitCount += 1
        }
        
        // Initialize a variable to hold the generated image
        var imageT: NSImage?
        
        // Start an asynchronous task to generate the mosaic
        Task {
            // Process the video to extract metadata
            let metadata = try await self.processVideo(file: videoFile, asset: asset)

            // Design the mosaic layout based on metadata, width, and density
            let mosaicLayout = try await self.mosaicDesign(
                metadata: metadata, width: width, density: density)
            
            // Get the number of thumbnails needed for the mosaic
            let thumbnailCount = mosaicLayout.thumbCount
            
            // Log the start of thumbnail extraction
            logger.log(level: .debug, "Extracting thumbnails for \(videoFile.standardizedFileURL)")
            
            // Extract thumbnails with timestamps from the video
            let thumbnailsWithTimestamps = try await self.extractThumbnailsWithTimestamps2(
                from: metadata.file,
                count: thumbnailCount,
                asset: asset,
                thSize: mosaicLayout.thumbnailSize,
                preview: false,
                accurate: accurate
            )
            try await self.extractThumbnailsWithTimestamps4( from: metadata.file,
                                                             count: thumbnailCount,
                                                             asset: asset,
                                                             thSize: mosaicLayout.thumbnailSize,
                                                             preview: false,
                                                             accurate: accurate
                                                         )
            // Calculate the output size of the mosaic
            let outputSize = CGSize(
                width: Int(mosaicLayout.cols * Int(mosaicLayout.thumbnailSize.width)),
                height: Int(mosaicLayout.rows * Int(mosaicLayout.thumbnailSize.height)))

            // Log the start of mosaic generation
            logger.log(level: .debug, "Generating mosaic for \(videoFile.standardizedFileURL)")
            
            // Generate the mosaic image
            let mosaic = try await withCheckedThrowingContinuation { continuation in
                autoreleasepool {
                    do {
                        switch renderingMode {
                        case .auto, .classic:
                            // Record start time for classic rendering
                            let startTimeC = CFAbsoluteTimeGetCurrent()
                            
                            // Generate the mosaic using the classic method
                            let result = try self.generateOptMosaicImagebatch(
                                thumbnailsWithTimestamps: thumbnailsWithTimestamps,
                                layout: mosaicLayout, outputSize: outputSize, metadata: metadata)
                            
                            // Record end time and log the duration for classic rendering
                            let endTimeC = CFAbsoluteTimeGetCurrent()
                            logger.log(
                                level: .info,
                                "Mosaic generation without metal completed in \(String(format: "%.2f", endTimeC - startTimeC)) seconds for \(videoFile.standardizedFileURL)"
                            )
                            continuation.resume(returning: result)
                        case .metal:
                            // Metal rendering not implemented in this block
                            break
                        }
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            // Convert the CGImage mosaic to NSImage
            imageT = NSImage(cgImage: mosaic, size: outputSize)
        }
        
        // Return the generated mosaic image
        return imageT!
    }

    @available(macOS 13, *)
    /// Retrieves video files from a specified input directory.
    /// - Parameters:
    ///   - input: The input directory containing video files.
    ///   - width: The width of the generated mosaic.
    /// - Returns: An array of tuples containing the video URL and its output directory.
    /// - Throws: An error if the video files cannot be retrieved.
    public func getFiles(input: String, width: Int) async throws {
        self.videosFiles = try await getVideoFiles(from: input, width: width)
    }
   
    /// Runs the mosaic generation process for multiple video files.
    /// - Parameters:
    ///   - input: The input directory containing video files.
    ///   - width: The width of the generated mosaic.
    ///   - density: The density of frames to use in the mosaic.
    ///   - format: The output format of the mosaic image.
    ///   - overwrite: Whether to overwrite existing mosaic files.
    ///   - preview: Whether to generate a preview image.
    ///   - summary: Whether to generate a summary of the process.
    /// - Returns: An array of tuples containing the original video URL and the generated mosaic preview URL.
    /// - Throws: An error if the mosaic generation process fails.
    // Public function to run the mosaic generation process
    public func RunGen(
        input: String, width: Int, density: String, format: String, overwrite: Bool, preview: Bool,
        summary: Bool
    ) async throws -> [(video: URL, preview: URL)] {
        // Set the total unit count for progress tracking
        progressG.totalUnitCount = Int64(self.videosFiles.count)
        if self.summary {
            progressG.totalUnitCount = Int64(self.videosFiles.count) + 1
        }
        self.totalfiles = Int(progressG.totalUnitCount)
        
        // Initialize variables
        var ReturnedFiles: [(URL, URL)] = []
        let concurrentTaskLimit = self.maxConcurrentOperations
        var activeTasks = 0
        let pct = 100 / Double(self.videosFiles.count)
        var prog = 0.0
        let startTime = CFAbsoluteTimeGetCurrent()

        // Log the start of processing
        logger.log(level: .info, "Starting to process \(self.videosFiles.count) files")

        // Switch based on preview flag
        switch preview {
        case false:
            do {
                // Use a task group for concurrent processing
                try await withThrowingTaskGroup(of: Void.self) { group in
                    // Iterate through video files
                    for (index, (videoFile, outputDirectory)) in self.videosFiles.enumerated() {
                        // Check for cancellation
                        if isCancelled {
                            throw CancellationError()
                        }
                        // Wait if concurrent task limit is reached
                        if activeTasks >= concurrentTaskLimit {
                            self.signposter.emitEvent(
                                "waiting for slots to become available for file process")
                            try await group.next()
                            activeTasks -= 1
                        }

                        // Increment active tasks and process file
                        activeTasks += 1
                        autoreleasepool {
                            group.addTask {
                                do {
                                    // Check for cancellation again
                                    if self.isCancelled {
                                        throw CancellationError()
                                    }

                                    // Log start of file processing
                                    self.signposter.emitEvent(
                                        "starting file process", id: self.signpostID)
                                    
                                    // Process individual file
                                    let returnfile = try await self.processIndivFile(
                                        videoFile: videoFile, width: width, density: density,
                                        format: format, overwrite: overwrite, preview: preview,
                                        outputDirectory: outputDirectory, accurate: self.accurate)

                                    // Add processed file to return array
                                    ReturnedFiles.append((videoFile, returnfile))

                                } catch {
                                    // Log error if file processing fails
                                    self.logger.error(
                                        "Failed to process file: \(videoFile.absoluteString), error: \(error.localizedDescription)"
                                    )
                                }
                            }
                        }
                    }

                    // Wait for all tasks to complete
                    try await group.waitForAll()

                    // Create summary video if requested
                    if self.summary {
                        let outputFolder =
                            self.videosFiles.first?.1.deletingLastPathComponent()
                            ?? URL(fileURLWithPath: NSTemporaryDirectory())
                        self.logger.log(level: .info, "startingg video summary creation.")
                        try await createSummaryVideo(
                            from: ReturnedFiles, outputFolder: outputFolder)
                    }

                    // Log completion of processing
                    self.logger.log(level: .info, "All thumbnails processed.")
                }
            } catch is CancellationError {
                // Handle cancellation
                logger.log(level: .info, "Processing was cancelled")
                throw CancellationError()
            }

        case true:
            // Process files for preview generation
            try await withThrowingTaskGroup(of: Void.self) { group in
                for (videoFile, outputDirectory) in self.videosFiles {
                    // Wait if concurrent task limit is reached
                    if activeTasks >= concurrentTaskLimit {
                        try await group.next()
                    } else {
                        // Increment active tasks and generate preview
                        activeTasks += 1
                        autoreleasepool {
                            group.addTask {
                                do {
                                    prog += pct
                                    let returnfile = try await self.generateAnimatedPreview(
                                        for: videoFile, outputDirectory: outputDirectory,
                                        density: density)
                                    ReturnedFiles.append((videoFile, returnfile))
                                    activeTasks -= 1
                                } catch {
                                    // Log error if preview generation fails
                                    self.logger.error(
                                        "Failed to process file: \(videoFile.absoluteString), error: \(error.localizedDescription)"
                                    )
                                }
                            }
                        }
                    }
                }
                // Wait for all tasks to complete
                try await group.waitForAll()
                self.logger.log(level: .info, "All thumbnails processed.")
            }
        }

        // Calculate and log total processing time
        let endTime = CFAbsoluteTimeGetCurrent()
        logger.log(
            level: .info,
            "Mosaic generation totally completed in \(String(format: "%.2f", endTime - startTime)) seconds"
        )
        return ReturnedFiles
    }

    /// Processes video files to generate mosaics or previews.
    ///
    /// - Parameters:
    ///   - input: The input path for video files.
    ///   - width: The width of the generated mosaic.
    ///   - density: The density of the mosaic.
    ///   - format: The output format for the mosaic.
    ///   - overwrite: Whether to overwrite existing files.
    ///   - preview: Whether to generate previews instead of full mosaics.
    ///   - summary: Whether to create a summary video.
    /// - Returns: An array of tuples containing the original video URL and the generated mosaic/preview URL.
    /// - Throws: An error if processing fails.
    public func processFiles(
        input: String, width: Int, density: String, format: String, overwrite: Bool, preview: Bool,
        summary: Bool
    ) async throws -> [(video: URL, preview: URL)] {
        // Reset cancellation flag
        isCancelled = false
        
        // Get video files from the input
        let videoFiles = try await getVideoFiles(from: input, width: width)
        
        // Set up progress tracking
        progressG.totalUnitCount = Int64(videoFiles.count)
        if self.summary {
            progressG.totalUnitCount = Int64(videoFiles.count) + 1
        }
        
        // Initialize array to store returned files
        var ReturnedFiles: [(URL, URL)] = []
        
        // Set concurrent task limit
        let concurrentTaskLimit = self.maxConcurrentOperations
        var activeTasks = 0
        
        // Calculate progress increment per file
        let pct = 100 / Double(videoFiles.count)
        var prog = 0.0
        
        // Record start time for performance measurement
        let startTime = CFAbsoluteTimeGetCurrent()

        logger.log(level: .info, "Starting to process \(videoFiles.count) files")

        switch preview {
        case false:
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for (videoFile, outputDirectory) in videoFiles {
                        // Check for cancellation
                        if isCancelled {
                            throw CancellationError()
                        }
                        
                        // Wait if maximum concurrent tasks reached
                        if activeTasks >= concurrentTaskLimit {
                            self.signposter.emitEvent(
                                "waiting for slots to become available for file process")
                            try await group.next()
                            activeTasks -= 1
                        }

                        activeTasks += 1
                        autoreleasepool {
                            group.addTask {
                                do {
                                    if self.isCancelled {
                                        throw CancellationError()
                                    }

                                    self.signposter.emitEvent(
                                        "starting file process", id: self.signpostID)
                                    
                                    // Process individual file
                                    let returnfile = try await self.processIndivFile(
                                        videoFile: videoFile, width: width, density: density,
                                        format: format, overwrite: overwrite, preview: preview,
                                        outputDirectory: outputDirectory, accurate: self.accurate)
                                    ReturnedFiles.append((videoFile, returnfile))

                                } catch {
                                    self.logger.error(
                                        "Failed to process file: \(videoFile.absoluteString), error: \(error.localizedDescription)"
                                    )
                                }
                            }
                        }
                    }

                    // Wait for all tasks to complete
                    try await group.waitForAll()

                    // Create summary video if requested
                    if self.summary {
                        let outputFolder =
                            videoFiles.first?.1.deletingLastPathComponent()
                            ?? URL(fileURLWithPath: NSTemporaryDirectory())
                        self.logger.log(level: .info, "Starting video summary creation.")
                        try await createSummaryVideo(
                            from: ReturnedFiles, outputFolder: outputFolder)
                    }

                    self.logger.log(level: .info, "All thumbnails processed.")
                }
            } catch is CancellationError {
                logger.log(level: .info, "Processing was cancelled")
                throw CancellationError()
            }

        case true:
            try await withThrowingTaskGroup(of: Void.self) { group in
                for (videoFile, outputDirectory) in videoFiles {
                    // Wait if maximum concurrent tasks reached
                    if activeTasks >= concurrentTaskLimit {
                        try await group.next()
                    } else {
                        activeTasks += 1
                        autoreleasepool {
                            group.addTask {
                                do {
                                    prog += pct
                                    // Generate animated preview
                                    let returnfile = try await self.generateAnimatedPreview(
                                        for: videoFile, outputDirectory: outputDirectory,
                                        density: density)
                                    ReturnedFiles.append((videoFile, returnfile))
                                    activeTasks -= 1
                                } catch {
                                    self.logger.error(
                                        "Failed to process file: \(videoFile.absoluteString), error: \(error.localizedDescription)"
                                    )
                                }
                            }
                        }
                    }
                }
                // Wait for all tasks to complete
                try await group.waitForAll()
                self.logger.log(level: .info, "All thumbnails processed.")
            }
        }

        // Calculate and log total processing time
        let endTime = CFAbsoluteTimeGetCurrent()
        logger.log(
            level: .info,
            "Mosaic generation totally completed in \(String(format: "%.2f", endTime - startTime)) seconds"
        )
        return ReturnedFiles
    }

    /// Creates an M3U8 playlist from video files in a specified directory.
    /// - Parameter directoryPath: The path to the directory containing video files.
    /// - Throws: An error if the playlist creation fails.
    public func createM3U8Playlist(from directoryPath: String) async throws {
        // Step 1: Get all video files from the directory using the getVideoFiles function
        // Note: width is set to 0, adjust if needed for specific use cases
        let videoFiles = try await getVideoFiles(from: directoryPath, width: 0)
        let path = URL(fileURLWithPath: directoryPath, isDirectory: true)

        // Step 2: Create the M3U8 playlist content
        var playlistContent = "#EXTM3U\n"
        progressG.totalUnitCount = Int64(videoFiles.count)

        // Iterate through each video file and add it to the playlist
        for (videoFile, _) in videoFiles {
            let fileName = videoFile.lastPathComponent
            playlistContent += "#EXTINF:-1,\(fileName)\n"
            playlistContent += "\(videoFile.path)\n"
            self.progressG.completedUnitCount += 1
        }

        // Step 3: Define the path where the M3U8 file will be saved
        let playlistFileName = "\(path.lastPathComponent).m3u8"
        let playlistFilePath = URL(fileURLWithPath: directoryPath, isDirectory: true)
            .appendingPathComponent(playlistFileName)

        // Remove existing playlist file if it exists
        if FileManager.default.fileExists(atPath: playlistFilePath.path) {
            try FileManager.default.removeItem(at: playlistFilePath)
            logger.log(level: .info, "Existing playlist file removed: \(playlistFilePath.path)")
        }

        // Step 4: Write the M3U8 content to a file
        do {
            try playlistContent.write(to: playlistFilePath, atomically: true, encoding: .utf8)
            print("M3U8 playlist created at \(playlistFilePath.path)")
        } catch {
            print("Failed to create M3U8 playlist: \(error.localizedDescription)")
            throw error
        }
    }

    /// Retrieves video files and their corresponding output directories based on the input.
    /// - Parameters:
    ///   - input: The input path for video files.
    ///   - width: The width of the generated mosaic.
    ///   - density: The density of the mosaic.
    /// - Returns: An array of tuples containing the original video URL and the generated mosaic URL.
    /// - Throws: An error if the input is not found or processing fails.
    public func getVideoFilespair(from input: String, width: Int, density: String) async throws
        -> [(URL, URL)]
    {
        let inputURL = URL(fileURLWithPath: input)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: input, isDirectory: &isDirectory) else {
            throw MosaicError.inputNotFound
        }
        var result = [(URL, URL)]()
        if isDirectory.boolValue {
            logger.log(level: .debug, "Input is a directory")
            result = try await getVideoFilesFromDirectory(inputURL, width: width)
        } else if inputURL.pathExtension.lowercased() == "m3u8" {
            logger.log(level: .debug, "Input is an m3u8 playlist")
            result = try await getVideoFilesFromPlaylist(inputURL, width: width)
        } else {
            logger.log(level: .debug, "Input is a file")
            guard isVideoFile(inputURL) else {
                throw MosaicError.notAVideoFile
            }
            let outputDirectory = inputURL.deletingLastPathComponent().appendingPathComponent("0th")
                .appendingPathComponent("\(width)")
            try FileManager.default.createDirectory(
                at: outputDirectory, withIntermediateDirectories: true, attributes: nil)
            result = [(inputURL, outputDirectory)]
        }
        let finalResult = try result.map { inputURL, outputDirectory in
            let outputFile = try findTargetFileName(
                for: inputURL, in: outputDirectory, format: "heic", density: density)
            return (inputURL, outputFile)
        }
        return finalResult
    }

    /// Returns the current progress of the mosaic generation process.
    /// - Returns: A float value representing the progress from 0 to 1.
    public func currentProgress() -> Float {
        return Float(progressG.fractionCompleted)
    }

    // MARK: - Private Methods

    /// Determines the optimal mosaic layout based on video metadata and parameters.
    /// - Parameters:
    ///   - metadata: The metadata of the video.
    ///   - width: The width of the mosaic.
    ///   - density: The density of the mosaic.
    /// - Returns: The optimal mosaic layout.
    private func mosaicDesign(metadata: VideoMetadata, width: Int, density: String) async throws
        -> (MosaicLayout)
    {
        let state = signposter.beginInterval("mosaicDesign", id: signpostID)
        defer {
            signposter.endInterval("mosaicDesign", state)
        }
        let thumbnailCount = calculateThumbnailCount(
            duration: metadata.duration, width: width, density: density)

        let thumbnailAspectRatio = metadata.resolution.width / metadata.resolution.height
        return calculateOptimalMosaicLayout(
            originalAspectRatio: thumbnailAspectRatio, estimatedThumbnailCount: thumbnailCount,
            mosaicWidth: width)
    }

    /// Retrieves video files from the input source.
    /// - Parameters:
    ///   - input: The input path for video files.
    ///   - width: The width of the generated mosaic.
    /// - Returns: An array of tuples containing the original video URL and the generated mosaic URL.
    /// - Throws: An error if the input is not found or processing fails.
    public func getVideoFiles(from input: String, width: Int) async throws -> [(URL, URL)] {
        let inputURL = URL(fileURLWithPath: input)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: input, isDirectory: &isDirectory) else {
            throw MosaicError.inputNotFound
        }

        if isDirectory.boolValue {
            logger.log(level: .debug, "Input is a directory")
            return try await getVideoFilesFromDirectory(inputURL, width: width)
        } else if inputURL.pathExtension.lowercased() == "m3u8" {
            logger.log(level: .debug, "Input is an m3u8 playlist")
            return try await getVideoFilesFromPlaylist(inputURL, width: width)
        } else {
            // let newInput = URL(fileURLWithPath: inputURL.path(percentEncoded: false), isDirectory: false)!
            logger.log(level: .debug, "Input is a file")
            return try await getSingleFile(inputURL, width: width)
        }
    }

    /// Retrieves video files from a single file.
    private func getSingleFile(_ inputURL: URL, width: Int) async throws -> [(URL, URL)] {
        guard isVideoFile(inputURL) else {
            throw MosaicError.notAVideoFile
        }
        let fileManager = FileManager.default
        var result = [(URL, URL)]()
        let folder = URL(fileURLWithPath: inputURL.path(percentEncoded: false), isDirectory: false)
            .deletingLastPathComponent()
        let outputDirectory1 = folder.appendingPathComponent("0th", isDirectory: true)
        let outputDirectory2 = folder.appendingPathComponent("0th", isDirectory: true)
            .appendingPathComponent(String(width), isDirectory: true)
        do {
            try fileManager.createDirectory(at: outputDirectory1, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: outputDirectory2, withIntermediateDirectories: true)

        } catch {
            self.logger.error(
                "Failed to create directory at file: \(inputURL.absoluteString), error: \(error.localizedDescription)"
            )
            throw error
        }

        self.summary = false
        result.append((inputURL, outputDirectory2))
        return result
    }

    /// Retrieves video files from a directory.
    /// - Parameters:
    ///   - directory: The directory containing video files.
    ///   - width: The width of the generated mosaic.
    /// - Returns: An array of tuples containing the video URL and its output directory.
    /// - Throws: An error if the video files cannot be retrieved.
    private func getVideoFilesFromDirectory(_ directory: URL, width: Int) async throws -> [(
        URL, URL
    )] {

        let fileManager = FileManager.default
        var result = [(URL, URL)]()

        guard
            let enumerator = fileManager.enumerator(
                at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: [.skipsHiddenFiles])
        else {
            throw NSError(
                domain: "FileManagerError", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create directory enumerator"])
        }
        var index = 0
        let startTime = CFAbsoluteTimeGetCurrent()
        while let fileURL = enumerator.nextObject() as? URL {
            let resourceValues = try fileURL.resourceValues(forKeys: [
                .isDirectoryKey, .isRegularFileKey,
            ])

            if resourceValues.isDirectory == true {
                continue
            }
            var outputDirectory: URL
            if resourceValues.isRegularFile == true,
                self.isVideoFile(fileURL),
                !fileURL.lastPathComponent.lowercased().contains("amprv")
            {
                if saveAtRoot {
                    outputDirectory = directory.appendingPathComponent("0th")
                        .appendingPathComponent("\(width)")
                } else {
                    outputDirectory = fileURL.deletingLastPathComponent().appendingPathComponent(
                        "0th"
                    ).appendingPathComponent("\(width)")
                }
                self.progressT.completedUnitCount += 1
                self.updateProgressG(
                    currentFile: fileURL.lastPathComponent,
                    processedFiles: Int(self.progressT.completedUnitCount),
                    totalFiles: 0,
                    currentStage: "Discovering video",
                    startTime: self.startTime
                )
                index += 1
                result.append((fileURL, outputDirectory))
            }
        }

        logger.log(level: .info, "Found \(result.count) video files in directory: \(directory)")
        return result
    }

    /// Retrieves video files from an m3u8 playlist.
    private func getVideoFilesFromPlaylist(_ playlistURL: URL, width: Int) async throws -> [(
        URL, URL
    )] {
        let videoURLs = try parseM3U8File(at: playlistURL.path(percentEncoded: false))

        let playlistName = playlistURL.deletingPathExtension().lastPathComponent
        let outputFolder = playlistURL.deletingLastPathComponent().appendingPathComponent(
            "Playlist"
        ).appendingPathComponent(playlistName)

        logger.log(
            level: .info, "Parsed \(videoURLs.count) video URLs from playlist: \(playlistURL)")
        return videoURLs.map { ($0, outputFolder) }
    }

    /// Parses an m3u8 file and returns the video URLs.
    private func parseM3U8File(at url: String) throws -> [URL] {
        let contents = try String(contentsOf: URL(string: url, encodingInvalidCharacters: false)!)
        let lines = contents.components(separatedBy: .newlines)

        return lines.compactMap { line in
            if !line.hasPrefix("#") && !line.isEmpty {
                return URL(fileURLWithPath: line)
            }
            return nil
        }
    }

    /// Checks if the given URL is a video file.
    private func isVideoFile(_ url: URL) -> Bool {
        let videoExtensions = ["mp4", "mov", "avi", "mkv", "m4v", "webm", "ts"]
        return videoExtensions.contains(url.pathExtension.lowercased())
    }

    /// Processes video metadata.
    public func processVideo(file: URL, asset: AVAsset) async throws -> VideoMetadata {
        let state = signposter.beginInterval("analyzing metadata", id: signpostID)
        defer {
            signposter.endInterval("analyzing metadata", state)
        }
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            throw MosaicError.noVideoTrack
        }

        async let durationFuture = asset.load(.duration)
        async let sizeFuture = track.load(.naturalSize)
        let duration = try await durationFuture.seconds
        let size = try await sizeFuture
        let codec = try await track.mediaFormat
        var type = "M"

        switch duration {
        case 0...60:
            type = "XS"
        case 60...300:
            type = "S"
        case 300...900:
            type = "M"
        case 900...1800:
            type = "L"
        case 1800...:
            type = "XL"
        default:
            type = "M"
        }

        logger.log(
            level: .debug,
            "Processed video metadata for \(file): duration=\(duration), codec=\(codec)")
        return VideoMetadata(
            file: file, duration: duration, resolution: size, codec: codec, type: type)
    }

    /// Calculates the number of thumbnails to extract based on video duration and mosaic width.
    private func calculateThumbnailCount(duration: Double, width: Int, density: String) -> Int {
        let state = signposter.beginInterval("calculateThumbnailCount", id: signpostID)

        let base = Double(width) / 200.0
        let k = 10.0
        let rawCount = base + k * log(duration)

        let densityFactor: Double
        switch density.lowercased() {
        case "xxs": densityFactor = 0.25
        case "xs": densityFactor = 0.5
        case "s": densityFactor = 1.0
        case "m": densityFactor = 1.5
        case "l": densityFactor = 2.0
        case "xl": densityFactor = 4.0
        case "xxl": densityFactor = 8.0
        default: densityFactor = 1.0
        }

        signposter.endInterval("calculateThumbnailCount", state)

        if duration < 5 {
            return 4
        }
        let totalCount = Int(rawCount / densityFactor)
        logger.log(
            level: .debug,
            "Calculated thumbnail count: \(totalCount) for duration: \(duration), width: \(width), density: \(density)"
        )
        return min(totalCount, 800)
    }

    /// Generates an animated preview for a video file.
    /// - Parameters:
    ///   - videoFile: The URL of the video file.
    ///   - outputDirectory: The directory to save the preview.
    ///   - density: The density of the preview.
    /// - Returns: The URL of the generated preview.
    /// - Throws: An error if the preview generation fails.
    private func generateAnimatedPreview(for videoFile: URL, outputDirectory: URL, density: String)
        async throws -> URL
    {
        logger.log(level: .debug, "Generating animated preview for \(videoFile.lastPathComponent)")
        let asset = AVURLAsset(url: videoFile)
        let duration = try await asset.load(.duration).seconds
        var previewDuration = Double(60)
        let densityFactor: Double
        switch density.lowercased() {
        case "xxs": densityFactor = 0.25
        case "xs": densityFactor = 0.5
        case "s": densityFactor = 1.0
        case "m": densityFactor = 1.5
        case "l": densityFactor = 2.0
        case "xl": densityFactor = 4.0
        default: densityFactor = 1.0
        }

        let extractsPerMinute: Double
        if duration < 300 {  // Less than 5 minutes
            extractsPerMinute = 8 / densityFactor
            previewDuration = Double(30)
        } else if duration < 1200 {  // Less than 20 minutes
            extractsPerMinute = 3 / densityFactor
            previewDuration = Double(60)
        } else {
            extractsPerMinute = 0.5 / densityFactor
            previewDuration = Double(90)
        }
        let extractCount = Int(ceil(duration / 60 * extractsPerMinute))
        let extractDuration = min(
            previewDuration / Double(extractCount), duration / Double(extractCount))
        logger.log(
            level: .debug,
            "Generating \(extractCount) extracts of \(extractDuration) seconds each for preview animation"
        )

        let previewDirectory = outputDirectory.deletingLastPathComponent().appendingPathComponent(
            "amprv", isDirectory: true)
        try FileManager.default.createDirectory(
            at: previewDirectory, withIntermediateDirectories: true, attributes: nil)
        var previewURL = previewDirectory.appendingPathComponent(
            "\(videoFile.deletingPathExtension().lastPathComponent)-amprv-\(density).mp4")
        if FileManager.default.fileExists(atPath: previewURL.path) {
            try FileManager.default.removeItem(at: previewURL)
            logger.log(level: .info, "Existing preview file removed: \(previewURL.path)")
        }

        // Create a composition
        let composition = AVMutableComposition()
        guard
            let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
            let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else {
            throw MosaicError.unableToCreateCompositionTracks
        }

        // Get the original video and audio tracks
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first,
            let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        else {
            throw MosaicError.noVideoOrAudioTrack
        }

        // Get the original video's framerate
        let originalFrameRate = try await videoTrack.load(.nominalFrameRate)

        var currentTime = CMTime.zero

        // Create video composition for fade transitions
       // var instructions = [AVMutableVideoCompositionInstruction]()
        let timescale: CMTimeScale = 600

        let fastPlaybackDuration = CMTime(
            seconds: extractDuration / 2, preferredTimescale: timescale)
        for i in 0..<extractCount {
            let startTime = CMTime(
                seconds: Double(i) * (duration - extractDuration) / Double(extractCount - 1),
                preferredTimescale: timescale)
            let durationCMTime = CMTime(seconds: extractDuration, preferredTimescale: timescale)

            do {
                // Insert video segment
                try await compositionVideoTrack.insertTimeRange(
                    CMTimeRange(start: startTime, duration: durationCMTime),
                    of: videoTrack,
                    at: currentTime)

                try await compositionAudioTrack.insertTimeRange(
                    CMTimeRange(start: startTime, duration: durationCMTime),
                    of: audioTrack,
                    at: currentTime)

                // Scale the inserted segments to play faster
                let timeRange = CMTimeRange(start: currentTime, duration: durationCMTime)
                try compositionVideoTrack.scaleTimeRange(
                    timeRange, toDuration: fastPlaybackDuration)
                try compositionAudioTrack.scaleTimeRange(
                    timeRange, toDuration: fastPlaybackDuration)

                logger.log(
                    level: .debug,
                    "Extracted segment \(i+1) of \(extractCount) for \(videoFile.lastPathComponent)"
                )

                currentTime = CMTimeAdd(currentTime, fastPlaybackDuration)
            } catch {
                logger.error("Failed to insert or scale time range: \(error.localizedDescription)")
            }
        }

        logger.log(level: .debug, "Starting export for \(videoFile.lastPathComponent)")
        guard
            let exportSession = AVAssetExportSession(
                asset: composition, presetName: AVAssetExportPresetPassthrough)
        else {
            throw MosaicError.unableToCreateExportSession
        }
        let videoComposition = AVMutableVideoComposition(propertiesOf: composition)
        videoComposition.frameDuration = CMTime(
            value: 1, timescale: CMTimeScale(originalFrameRate * 2))
        let audioMix = AVMutableAudioMix()
        let audioParameters = AVMutableAudioMixInputParameters(track: compositionAudioTrack)

        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = false
        exportSession.videoComposition = videoComposition
        exportSession.allowsParallelizedExport = true
        exportSession.directoryForTemporaryFiles = FileManager.default.temporaryDirectory
        audioMix.inputParameters = [audioParameters]
        exportSession.audioMix = audioMix

        try await exportVid(for: exportSession, previewURL: previewURL)
        return previewURL
    }

    /// Exports a video file to a specified URL.
    /// - Parameters:
    ///   - exportSession: The export session for the video.
    ///   - previewURL: The URL to save the exported video.
    /// - Throws: An error if the export fails.
    private func exportVid(for exportSession: AVAssetExportSession, previewURL: URL) async throws {
        exportSession.outputURL = previewURL
        let startTime = CFAbsoluteTimeGetCurrent()
        // Perform the export
        exportSession.allowsParallelizedExport = true
        try await exportSession.export(to: previewURL, as: .mp4)
        let endTime = CFAbsoluteTimeGetCurrent()
        logger.log(
            level: .debug,
            "Finished export in \(String(format: "%.2f", endTime - startTime)) seconds")
    }

    /// Calculates the optimal layout for the mosaic based on the original aspect ratio and estimated thumbnail count.
    /// - Parameters:
    ///   - originalAspectRatio: The aspect ratio of the original video.
    ///   - estimatedThumbnailCount: The estimated number of thumbnails.
    ///   - mosaicWidth: The width of the mosaic.
    /// - Returns: The optimal mosaic layout.
    func calculateOptimalMosaicLayout(
        originalAspectRatio: CGFloat,
        estimatedThumbnailCount: Int,
        mosaicWidth: Int
    ) -> MosaicLayout {
        var count = estimatedThumbnailCount
        let state = signposter.beginInterval("calculateOptimalMosaicLayout", id: signpostID)
        defer {
            signposter.endInterval("calculateOptimalMosaicLayout", state)
        }
        let mosaicAspectRatio: CGFloat = 16.0 / 9.0
        let mosaicHeight = Int(CGFloat(mosaicWidth) / mosaicAspectRatio)

        func calculateLayout(rows: Int) -> MosaicLayout {
            let cols = Int(ceil(Double(count) / Double(rows)))

            let thumbnailWidth = CGFloat(mosaicWidth) / CGFloat(cols)
            let thumbnailHeight = thumbnailWidth / originalAspectRatio

            let adjustedRows = min(rows, Int(ceil(CGFloat(mosaicHeight) / thumbnailHeight)))

            var positions: [(x: Int, y: Int)] = []
            for row in 0..<adjustedRows {
                for col in 0..<cols {
                    if positions.count < count {
                        positions.append((x: col, y: row))
                    } else {
                        break
                    }
                }
            }
            return MosaicLayout(
                rows: adjustedRows,
                cols: cols,
                thumbnailSize: CGSize(width: thumbnailWidth, height: thumbnailHeight),
                positions: positions,
                thumbCount: count
            )
        }

        var bestLayout = calculateLayout(rows: Int(sqrt(Double(estimatedThumbnailCount))))
        var bestScore = Double.infinity

        for rows in 1...estimatedThumbnailCount {
            let layout = calculateLayout(rows: rows)

            let fillRatio =
                (CGFloat(layout.rows) * layout.thumbnailSize.height) / CGFloat(mosaicHeight)
            let thumbnailCount = layout.positions.count
            let countDifference = abs(thumbnailCount - estimatedThumbnailCount)

            let score = (1 - fillRatio) + Double(countDifference) / Double(estimatedThumbnailCount)

            if score < bestScore {
                bestScore = score
                bestLayout = layout
            }

            if CGFloat(layout.rows) * layout.thumbnailSize.height > CGFloat(mosaicHeight) {
                break
            }
        }
        count = bestLayout.rows * bestLayout.cols

        logger.log(
            level: .debug,
            "Optimal mosaic layout calculated: rows=\(bestLayout.rows), cols=\(bestLayout.cols), totalThumbnails=\(count)"
        )
        return calculateLayout(rows: bestLayout.rows)
    }

    @available(macOS 13, *)
    /// Extracts thumbnails from a video file with timestamps.
    /// - Parameters:
    ///   - file: The URL of the video file.
    ///   - count: The number of thumbnails to extract.
    ///   - asset: The AVAsset object for the video.
    ///   - thSize: The size of the thumbnails.
    ///   - preview: Whether to extract thumbnails for a preview.
    ///   - accurate: Whether to extract thumbnails with accurate timestamps.
    /// - Returns: An array of tuples containing the thumbnail image and its timestamp.
    func extractThumbnailsWithTimestamps3(
        from file: URL, count: Int, asset: AVAsset, thSize: CGSize, preview: Bool, accurate: Bool, batchSize: Int = 20
    ) async throws -> [(image: CGImage, timestamp: String)] {
        let state = signposter.beginInterval("extractThumbnailsWithTimestamps3", id: signpostID)
        defer { signposter.endInterval("extractThumbnailsWithTimestamps3", state) }

        logger.log(level: .debug, "Starting thumbnail extraction for \(file.lastPathComponent): count=\(count), preview=\(preview), accurate=\(accurate)")

        let startTime = CFAbsoluteTimeGetCurrent()
        let duration = try await asset.load(.duration).seconds
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = accurate ? .zero : CMTime(seconds: 2, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = accurate ? .zero : CMTime(seconds: 2, preferredTimescale: 600)
        if !preview { generator.maximumSize = thSize }

        let step = duration / Double(count)
        let times = stride(from: 0, to: duration, by: step).map { CMTime(seconds: $0, preferredTimescale: 600) }
        var thumbnailsWithTimestamps: [(Int, CGImage, String)] = []
        batchSize = count
       
            self.signposter.emitEvent("start new batch size")
            let batches = times.chunked(into: batchSize)
            self.signposter.emitEvent("start extracted")
            
            var failedCount = 0
            

            await withTaskGroup(of: [(Int, CGImage, String)].self) { group in
                for (batchIndex, batch) in batches.enumerated() {
                    group.addTask {
                        var batchResults: [(Int, CGImage, String)] = []
                        self.signposter.emitEvent("start batch")
                        for await result in generator.images(for: batch) {
                            switch result {
                            case .success(requestedTime: _, let image, actualTime: let actual):
                                self.signposter.emitEvent("Image extracted")
                                let index = batchIndex * batchSize + batchResults.count
                                batchResults.append((index, image, self.formatTimestamp(seconds: actual.seconds)))
                            case .failure(requestedTime: _, let error):
                                self.logger.error("Thumbnail extraction failed: \(error.localizedDescription)")
                            }
                        }
                        return batchResults
                    }
                }

                for await batchResult in group {
                    thumbnailsWithTimestamps.append(contentsOf: batchResult)
                }
            }

            failedCount = count - thumbnailsWithTimestamps.count

            if failedCount > 0 {
                self.logger.warning("Partial failure in thumbnail extraction: \(thumbnailsWithTimestamps.count) successful, \(failedCount) failed")
                if thumbnailsWithTimestamps.isEmpty {
                    throw ThumbnailExtractionError.partialFailure(successfulCount: thumbnailsWithTimestamps.count, failedCount: failedCount)
                }
            }

            let endTime = CFAbsoluteTimeGetCurrent()
            let elapsedTime = endTime - startTime
            let fps = Double(count) / elapsedTime
            logger.log(level: .debug, "Thumbnail extraction with batchsise \(batchSize) completed for \(file.lastPathComponent): extracted=\(thumbnailsWithTimestamps.count), failed=\(failedCount), time=\(elapsedTime) seconds,fps : \(fps)")
            if batchSize != count{
               thumbnailsWithTimestamps = []
            }
        
        return thumbnailsWithTimestamps
            .sorted { $0.0 < $1.0 }
            .map { ($0.1, $0.2) }
    }
    /// Formats a timestamp in seconds to a string representation.
    private func formatTimestamp(seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let seconds = Int(seconds) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
                            
                            /// Generates the mosaic image from the extracted thumbnails.
                            private func generateOptMosaicImagebatch(thumbnailsWithTimestamps: [(image: CGImage, timestamp: String)],
                                                                     layout: MosaicLayout,
                                                                     outputSize: CGSize,
                                                                     metadata: VideoMetadata) throws -> CGImage {
                                let state = signposter.beginInterval("generateOptMosaicImagebatch", id: signpostID)
                                defer {
                                    signposter.endInterval("generateOptMosaicImagebatch", state)
                                }
                                
                                let width = Int(outputSize.width)
                                let height = Int(outputSize.height)
                                let thumbnailWidth = Int(layout.thumbnailSize.width)
                                let thumbnailHeight = Int(layout.thumbnailSize.height)
                                
                                guard let context = CGContext(data: nil,
                                                              width: width,
                                                              height: height,
                                                              bitsPerComponent: 8,
                                                              bytesPerRow: 0,
                                                              space: CGColorSpaceCreateDeviceRGB(),
                                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                                    logger.error("Unable to create CGContext for mosaic generation")
                                    throw MosaicError.unableToCreateContext
                                }
                                
                                // Fill background
                                context.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0))
                                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                                
                                // Draw thumbnails
                                for (index, (thumbnail, timestamp)) in thumbnailsWithTimestamps.enumerated() {
                                    guard index < layout.positions.count else { break }
                                    
                                    let position = layout.positions[index]
                                    let x = Int(CGFloat(position.x) * layout.thumbnailSize.width)
                                    let y = height - Int(CGFloat(position.y + 1) * layout.thumbnailSize.height)
                                    context.draw(thumbnail, in: CGRect(x: x, y: y, width: thumbnailWidth, height: thumbnailHeight))
                                    
                                    if self.time {
                                        drawTimestamp(context: context, timestamp: timestamp, x: x, y: y, width: thumbnailWidth, height: thumbnailHeight)
                                    }
                                }
                                
                                // Draw metadata
                                drawMetadata(context: context, metadata: metadata, width: width, height: height)
                                
                                guard let outputImage = context.makeImage() else {
                                    logger.error("Unable to generate mosaic image")
                                    throw MosaicError.unableToGenerateMosaic
                                }
                                
                                logger.log(level: .debug, "Mosaic image generated successfully")
                                return outputImage
                            }

                            /// Draws a timestamp on a thumbnail.
                            private func drawTimestamp(context: CGContext, timestamp: String, x: Int, y: Int, width: Int, height: Int) {
                                let fontSize = CGFloat(height) / 6 / 1.618
                                let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
                                
                                let attributes: [NSAttributedString.Key: Any] = [
                                    .font: font,
                                    .foregroundColor: NSColor.white.cgColor
                                ]
                                
                                let attributedTimestamp = CFAttributedStringCreate(nil, timestamp as CFString, attributes as CFDictionary)
                                let line = CTLineCreateWithAttributedString(attributedTimestamp!)
                                
                                context.saveGState()
                                context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.5))
                                let textRect = CGRect(x: x, y: y, width: width, height: Int(CGFloat(height) / 6))
                                context.fill(textRect)
                                
                                let textWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
                                let textPosition = CGPoint(x: x + width - Int(textWidth) - 5, y: y + 5)
                                
                                context.textPosition = textPosition
                                CTLineDraw(line, context)
                                context.restoreGState()
                            }

                            /// Draws metadata on the mosaic image.
                            private func drawMetadata(context: CGContext, metadata: VideoMetadata, width: Int, height: Int) {
                                let metadataHeight = Int(round(Double(height) * 0.1))
                                let lineHeight = metadataHeight / 4
                                let fontSize = round(Double(lineHeight) / 1.618)
                                let duree = formatTimestamp(seconds: metadata.duration)
                                context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 0.2))
                                context.fill(CGRect(x: 0, y: height - metadataHeight, width: width, height: metadataHeight))
                                
                                let metadataText = """
                                File: \(metadata.file.standardizedFileURL.standardizedFileURL)
                                Codec: \(metadata.codec)
                                Resolution: \(Int(metadata.resolution.width))x\(Int(metadata.resolution.height))
                                Duration: \(duree)
                                """
                                let attributes: [NSAttributedString.Key: Any] = [
                                    .font: CTFontCreateWithName("Helvetica" as CFString, fontSize, nil),
                                    .foregroundColor: NSColor.white.cgColor
                                ]
                                
                                let attributedString = NSAttributedString(string: metadataText, attributes: attributes)
                                let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
                                
                                let rect = CGRect(x: 10, y: height - metadataHeight + 10, width: width - 20, height: metadataHeight - 20)
                                let path = CGPath(rect: rect, transform: nil)
                                
                                let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
                                
                                context.saveGState()
                                CTFrameDraw(frame, context)
                                context.restoreGState()
                            }
    
    /// New code
    /// /// Generates the mosaic image from the extracted thumbnails.
    /// - Parameters:
    ///   - thumbnailsWithTimestamps: An array of tuples containing the thumbnail image and its timestamp.
    ///   - layout: The layout of the mosaic.
    ///   - outputSize: The size of the output mosaic image.
    ///   - metadata: The metadata of the video.
    /// - Returns: The generated mosaic image.
    /// - Throws: An error if the mosaic image cannot be generated.
    private func generateOptMosaicImagebatch2(
        thumbnailsWithTimestamps: [(image: CGImage, timestamp: String)],
        layout: MosaicLayout,
        outputSize: CGSize,
        metadata: VideoMetadata
    ) throws -> CGImage {
        let state = signposter.beginInterval("generateOptMosaicImagebatch", id: signpostID)
        defer {
            signposter.endInterval("generateOptMosaicImagebatch", state)
        }

        let width = Int(outputSize.width)
        let height = Int(outputSize.height)
        let thumbnailWidth = Int(layout.thumbnailSize.width)
        let thumbnailHeight = Int(layout.thumbnailSize.height)

        // 1. Use autoreleasepool to manage memory more efficiently
        return try autoreleasepool {
            guard
                let context = CGContext(
                    data: nil,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else {
                logger.error("Unable to create CGContext for mosaic generation")
                throw MosaicError.unableToCreateContext
            }

            // 2. Fill background more efficiently
            context.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))

            // 3. Prepare timestamp drawing attributes
            let timestampAttributes: [NSAttributedString.Key: Any] = [
                .font: CTFontCreateWithName("Helvetica" as CFString, CGFloat(thumbnailHeight) / 6 / 1.618, nil),
                .foregroundColor: NSColor.white.cgColor,
            ]

            // 4. Use DispatchQueue for concurrent drawing of thumbnails
            DispatchQueue.concurrentPerform(iterations: min(thumbnailsWithTimestamps.count, layout.positions.count)) { index in
                let (thumbnail, timestamp) = thumbnailsWithTimestamps[index]
                let position = layout.positions[index]
                let x = Int(CGFloat(position.x) * layout.thumbnailSize.width)
                let y = height - Int(CGFloat(position.y + 1) * layout.thumbnailSize.height)
                
                context.draw(
                    thumbnail, in: CGRect(x: x, y: y, width: thumbnailWidth, height: thumbnailHeight))

                if self.time {
                    drawTimestamp(
                        context: context,
                        timestamp: timestamp,
                        x: x,
                        y: y,
                        width: thumbnailWidth,
                        height: thumbnailHeight,
                        attributes: timestampAttributes
                    )
                }
            }

            // 5. Draw metadata
            drawMetadata(context: context, metadata: metadata, width: width, height: height)

            guard let outputImage = context.makeImage() else {
                logger.error("Unable to generate mosaic image")
                throw MosaicError.unableToGenerateMosaic
            }

            logger.log(level: .debug, "Mosaic image generated successfully")
            return outputImage
        }
    }

    // 6. Optimize drawTimestamp function
    private func drawTimestamp(
        context: CGContext,
        timestamp: String,
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        attributes: [NSAttributedString.Key: Any]
    ) {
        context.saveGState()
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.5))
        let textRect = CGRect(x: x, y: y, width: width, height: Int(CGFloat(height) / 6))
        context.fill(textRect)

        let attributedTimestamp = NSAttributedString(string: timestamp, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributedTimestamp)
        let textWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
        let textPosition = CGPoint(x: x + width - Int(textWidth) - 5, y: y + 5)

        context.textPosition = textPosition
        CTLineDraw(line, context)
        context.restoreGState()
    }

                            /// Generates an output file name for the mosaic image.
    private func getOutputFileName(for videoFile: URL, in directory: URL, format: String, overwrite: Bool, density: String, type: String) throws -> String {
                                let baseName = videoFile.deletingPathExtension().lastPathComponent
                                let fileExtension = format.lowercased()
                                var version = 1
                                var fileName = "\(type)-\(baseName)-\(density).\(fileExtension)"
                                
                                while FileManager.default.fileExists(atPath: directory.appendingPathComponent(fileName).path) {
                                    if overwrite {
                                        try FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
                                        break
                                    }
                                    version += 1
                                    fileName = "\(type)-\(baseName)-\(density)_v\(version).\(fileExtension)"
                                }
                                return fileName
                            }

                            public func findTargetFileName(for videoFile: URL, in directory: URL, format: String, density: String) throws -> URL {
                                let baseName = videoFile.deletingPathExtension().lastPathComponent
                                let fileExtension = format.lowercased()
                                var version = 1
                                var fileName = "\(baseName)-\(density).\(fileExtension)"
                                if FileManager.default.fileExists(atPath: directory.appendingPathComponent(fileName).path) {
                                   return directory.appendingPathComponent(fileName)
                                }
                                else {
                                    version += 1
                                    fileName = "\(baseName)_v\(version).\(fileExtension)"
                                    while !FileManager.default.fileExists(atPath: directory.appendingPathComponent(fileName).path) {
                                        version += 1
                                        fileName = "\(baseName)_v\(version).\(fileExtension)"
                                    }
                                    return directory.appendingPathComponent(fileName)
                                }
                            }
                            
                            /// Saves the generated mosaic image to disk.
    private func saveMosaic(mosaic: CGImage, for videoFile: URL, in outputDirectory: URL, format: String, overwrite: Bool, width: Int, density: String, type: String) async throws -> URL {
                                let state = signposter.beginInterval("saveMosaic", id: signpostID)
                                defer {
                                    signposter.endInterval("saveMosaic", state)
                                }
                                
                                // Ensure output directory exists
                                try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true, attributes: nil)
                                
                                // Get the file name for the output image
        let fileName = try getOutputFileName(for: videoFile, in: outputDirectory, format: format, overwrite: overwrite, density: density, type: type)
                                let outputURL = outputDirectory.appendingPathComponent(fileName)
                                
                                // Handle saving the image as HEIC if the format is HEIC
                                if format.lowercased() == "heic" {
                                    try await saveMosaicAsHEIC(mosaic, to: outputURL)
                                } else {
                                    // Use existing image saving logic for other formats
                                    try await saveMosaicImage(mosaic, to: outputURL, format: format)
                                }
                                logger.log(level: .info, "Mosaic saved: \(outputURL.path)")
                                return outputURL
                            }
                            
                            /// Saves the mosaic image in HEIC format.
                            private func saveMosaicAsHEIC(_ mosaic: CGImage, to outputURL: URL) async throws {
                                guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, AVFileType.heic as CFString, 1,nil) else {
                                    throw NSError(domain: "HEICError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create HEIC destination"])
                                }

                                // Create the compression options
                                let options: [String: Any] = [
                                    kCGImageDestinationLossyCompressionQuality as String: 0.2 // Compression quality (0.0 to 1.0)
                                ]

                                // Add the mosaic image to the destination and finalize the save
                                CGImageDestinationAddImage(destination, mosaic, options as CFDictionary?)
                                if !CGImageDestinationFinalize(destination) {
                                    throw NSError(domain: "HEICError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize HEIC image save"])
                                }
                            }

                            /// Saves the mosaic image to a file with the specified format.
                            private func saveMosaicImage(_ image: CGImage, to url: URL, format: String) async throws {
                                let data: Data
                                switch format.lowercased() {
                                case "jpeg", "jpg":
                                    guard let imageData = image.jpegData(compressionQuality: 0.4) else {
                                        throw MosaicError.unableToSaveMosaic
                                    }
                                    data = imageData
                                case "png":
                                    guard let imageData = image.pngData() else {
                                        throw MosaicError.unableToSaveMosaic
                                    }
                                    data = imageData
                                default:
                                    throw MosaicError.unsupportedOutputFormat
                                }
                                
                                try data.write(to: url)
                            }

                           
    public func createSummaryVideo(from returnedFiles: [(video: URL, preview: URL)], outputFolder: URL) async throws -> URL {
        defer {
            self.progressG.completedUnitCount += 1
        }
        let startTime = CFAbsoluteTimeGetCurrent()
        defer {
            let endTime = CFAbsoluteTimeGetCurrent()
            logger.log(level: .info, "createSummaryVideo \(String(format: "%.2f", endTime - startTime)) sec")
        }
        let dateFormatter = DateFormatter()
           dateFormatter.dateFormat = "yyyyMMddHHmm"
           let timestamp = dateFormatter.string(from: Date())
           let outputURL = outputFolder.appendingPathComponent("\(timestamp)-amprv.mp4")
           
           let fps: Float = 1.0
           let frameInterval = CMTime(seconds: 1.0 / Double(fps), preferredTimescale: 600)
           
           // Set up the video writer
           let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
               AVVideoWidthKey: 1920,
               AVVideoHeightKey: 1080
           ]
           
           guard let assetWriter = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
               throw NSError(domain: "VideoCreationError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unable to create asset writer."])
           }
           
           let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
           let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerInput, sourcePixelBufferAttributes: nil)
           
           assetWriter.add(writerInput)
           
           guard assetWriter.startWriting() else {
               throw NSError(domain: "VideoCreationError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to start writing."])
           }
           
           assetWriter.startSession(atSourceTime: .zero)
           
           var frameCount = 0
           
           for (_, previewURL) in returnedFiles {
               guard let image = CIImage(contentsOf: previewURL) else { continue }
               
               let scaledImage = image.transformed(by: CGAffineTransform(scaleX: 1920 / image.extent.width, y: 1080 / image.extent.height))
               
               guard let pixelBuffer = try? await createPixelBuffer(from: scaledImage) else { continue }
               
               while !writerInput.isReadyForMoreMediaData {
                   await Task.sleep(10_000_000) // 10 milliseconds
               }
               
               let frameTime = CMTime(value: CMTimeValue(frameCount), timescale: CMTimeScale(fps))
               adaptor.append(pixelBuffer, withPresentationTime: frameTime)
               
               frameCount += 1
           }
           
           writerInput.markAsFinished()
           await assetWriter.finishWriting()
           
           logger.info("Summary video created at: \(outputURL.path)")
           return outputURL
       }
       
       private func createPixelBuffer(from ciImage: CIImage) async throws -> CVPixelBuffer {
           let attributes: [String: Any] = [
               kCVPixelBufferCGImageCompatibilityKey as String: true,
               kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
           ]
           var pixelBuffer: CVPixelBuffer?
           let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                            Int(ciImage.extent.width),
                                            Int(ciImage.extent.height),
                                            kCVPixelFormatType_32ARGB,
                                            attributes as CFDictionary,
                                            &pixelBuffer)
           
           guard status == kCVReturnSuccess, let unwrappedPixelBuffer = pixelBuffer else {
               throw NSError(domain: "PixelBufferError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unable to create pixel buffer."])
           }
           
           let context = CIContext()
           try await context.render(ciImage, to: unwrappedPixelBuffer)
           
           return unwrappedPixelBuffer
       }
}

