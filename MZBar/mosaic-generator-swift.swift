import AVFoundation
import Accelerate
import AppKit
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import os
import os.signpost
import AppKit


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
        let thumbnailSizes: [CGSize]
        let mosaicSize: CGSize
    }
    
    
    struct TimeStamp {
        let ts: String
        let x: Int
        let y: Int
        let w: Int
        let h: Int
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
        public let skippedFiles: Int
        public let errorFiles: Int
        public let isRunning: Bool
        
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
    private var isRunning: Bool = false
    private var saveAtRoot: Bool = false
    private var separate: Bool = true
    private var summary: Bool = true
    private var videosFiles: [(URL, URL)]
    private var totalfiles: Int = 0
    private var processedFiles: Int = 0
    private var startTime: CFAbsoluteTime
    private var layoutCache: [String: MosaicLayout] = [:]
    private var custom: Bool = false
    private var skippedFiles: Int = 0
    private var errorFiles: Int = 0
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
        maxConcurrentOperations: Int? = nil, timeStamps: Bool = true, skip: Bool = true,
        smart: Bool = false, createPreview: Bool = false, batchsize: Int = 24,
        accurate: Bool = false, saveAtRoot: Bool = false, separate: Bool = true,
        summary: Bool = false, custom: Bool = false)
    {
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
        self.custom = custom
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
            estimatedTimeRemaining: estimatedTimeRemaining,
            skippedFiles: self.skippedFiles,
            errorFiles: self.errorFiles,
            isRunning: self.isRunning
        )
        
        // Update the progress on the main thread to ensure UI updates are thread-safe
        DispatchQueue.main.async {
            self.progressHandlerG?(progressInfo)
        }
    }
    
    /* document the function*/
    /// process a file
    /// - Parameters:
    ///   - videoFile: <#videoFile description#>
    ///   - width: <#width description#>
    ///   - density: <#density description#>
    ///   - format: <#format description#>
    ///   - overwrite: <#overwrite description#>
    ///   - preview: <#preview description#>
    ///   - outputDirectory: <#outputDirectory description#>
    ///   - accurate: <#accurate description#>
    ///   - duration: <#duration description#>
    ///   - addpath: <#addpath description#>
    /// - Returns: <#description#>
    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    public func processIndivFile(
        videoFile: URL, width: Int, density: String, format: String, overwrite: Bool, preview: Bool,
        outputDirectory: URL, accurate: Bool, duration: Int = 0, addpath: Bool? = false
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
        if Int(metadata.duration) < duration && duration > 0 {
            print("file too short \(videoFile.standardizedFileURL)")
            self.skippedFiles  += 1
            updateProgressG(
                currentFile: videoFile.lastPathComponent, processedFiles: self.processedFiles,
                totalFiles: self.totalfiles, currentStage: "Processing Files",
                startTime: self.startTime)
            throw MosaicError.tooShort
        }
        
        // Design the mosaic layout based on the metadata and input parameters
        let mosaicLayout = try await self.mosaicDesign(
            metadata: metadata, width: width, density: density)
        
        // Get the number of thumbnails needed for the mosaic
        let thumbnailCount = mosaicLayout.thumbCount
        
        // Log the start of thumbnail extraction
        logger.log(level: .debug, "Extracting thumbnails for \(videoFile.standardizedFileURL)")
        let fileName = try getOutputFileName(for: videoFile, in: outputDirectory, format: format, overwrite: overwrite, density: density, type: metadata.type, addpath: addpath)
        if fileName == "exist"  && !overwrite{
            print("skipping \(videoFile.standardizedFileURL)")
            self.skippedFiles  += 1
            updateProgressG(
                currentFile: videoFile.lastPathComponent, processedFiles: self.processedFiles,
                totalFiles: self.totalfiles, currentStage: "Processing Files",
                startTime: self.startTime)
            throw(MosaicError.existingVid)
            
        }
        // Extract thumbnails with their timestamps
        let thumbnailsWithTimestamps = try await self.extractThumbnailsWithTimestamps3(
            from: metadata.file,
            layout: mosaicLayout,
            asset: asset,
            preview: preview,
            accurate: accurate
        )
        
        // Calculate the output size of the mosaic
        let outputSize = mosaicLayout.mosaicSize
        
        // Log the start of mosaic generation
        logger.log(level: .debug, "Generating mosaic for \(videoFile.standardizedFileURL)")
        
        // Generate the mosaic image
        let mosaic = try await withCheckedThrowingContinuation { continuation in
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
                self.errorFiles  += 1
                updateProgressG(
                    currentFile: videoFile.lastPathComponent, processedFiles: self.processedFiles,
                    totalFiles: self.totalfiles, currentStage: "Processing Files",
                    startTime: self.startTime)
                continuation.resume(throwing: error)
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
            type: metadata.type,
            addpath: addpath
        )
    }
    
    
    
    @available(macOS 13, *)
    /// Retrieves video files from a specified input directory.
    /// - Parameters:
    ///   - input: The input directory containing video files.
    ///   - width: The width of the generated mosaic.
    /// - Returns: An array of tuples containing the video URL and its output directory.
    /// - Throws: An error if the video files cannot be retrieved.
    public func getFiles(input: String, width: Int) async throws {
        self.videosFiles = try await getVideoFiles(input: input, width: width)
    }
    public func getFilestoday(width: String) async throws {
        self.videosFiles =  try await getVideoFilesCreatedTodayWithPlaylistLocation(width: width)
        try await createM3U8Playlisttoday()
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
    public func GenerateMosaics(
        input: String? = "", width: Int, density: String, format: String, overwrite: Bool? =  false, preview: Bool? = false,
        summary: Bool? = false, duration: Int? = 0, addpath: Bool? = false, previewDuration: Int? = 0
    ) async throws -> [(video: URL, preview: URL)] {
        // Set the total unit count for progress tracking
        defer
        {
            self.processedFiles = self.totalfiles
            
            self.isRunning = false
            self.updateProgressG(currentFile: "--", processedFiles: self.processedFiles, totalFiles: self.totalfiles, currentStage: "Mosaic generation completed successfully!", startTime: self.startTime)
        }
        progressG.totalUnitCount = Int64(self.videosFiles.count)
        self.totalfiles = self.videosFiles.count
        if self.summary {
            progressG.totalUnitCount = Int64(self.videosFiles.count) + 1
        }
        self.totalfiles = self.videosFiles.count
        
        self.updateProgressG(currentFile: "--", processedFiles: self.processedFiles, totalFiles: self.totalfiles, currentStage: "Starting Mosaic Generation", startTime: self.startTime)
        
        self.isRunning = true// Initialize variables
        var ReturnedFiles: [(URL, URL)] = []
        var concurrentTaskLimit = self.maxConcurrentOperations
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
                                        format: format, overwrite: overwrite!, preview: preview!,
                                        outputDirectory: outputDirectory, accurate: self.accurate, duration: duration!, addpath: addpath)
                                    
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
                    
                    
                    
                    
                    // Log completion of processing
                    self.logger.log(level: .info, "All thumbnails processed.")
                    
                }
            } catch is CancellationError {
                // Handle cancellation
                logger.log(level: .info, "Processing was cancelled")
                
                throw CancellationError()
            }
            
        case true:
            do {
                
                // Process files for preview generation
                //
                var concurrentTaskLimit = self.maxConcurrentOperations
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
                                    let returnfile = try await self.generateAnimatedPreview(
                                        for: videoFile, outputDirectory: outputDirectory,
                                        density: density, previewDuration: previewDuration!)
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
                    
                    self.logger.log(level: .info, "All thumbnails processed.")
                }
            } catch is CancellationError {
                // Handle cancellation
                logger.log(level: .info, "Processing was cancelled")
                
                throw CancellationError()
            }
        case .none:
            logger.log(level: .info, "Processing was cancelled")
            
            throw CancellationError()
        case .some(_):
            logger.log(level: .info, "Processing was cancelled")
            
            throw CancellationError()
        }
        // Calculate and log total processing time
        let endTime = CFAbsoluteTimeGetCurrent()
        logger.log(
            level: .info,
            "Mosaic generation totally completed in \(String(format: "%.2f", endTime - startTime)) seconds"
        )
        
        return ReturnedFiles
    }
    
    public func generatePreviews(
        input: String? = "", density: String, overwrite: Bool? =  false,
        duration: Int? = 0, previewDuration: Int? = 0
    ) async throws -> [(video: URL, preview: URL)] {
        // Set the total unit count for progress tracking
        defer
        {
            self.processedFiles = self.totalfiles
            
            self.isRunning = false
            self.updateProgressG(currentFile: "--", processedFiles: self.processedFiles, totalFiles: self.totalfiles, currentStage: "Mosaic generation completed successfully!", startTime: self.startTime)
        }
        progressG.totalUnitCount = Int64(self.videosFiles.count)
        self.totalfiles = self.videosFiles.count
        if self.summary {
            progressG.totalUnitCount = Int64(self.videosFiles.count) + 1
        }
        self.totalfiles = self.videosFiles.count
        
        self.updateProgressG(currentFile: "--", processedFiles: self.processedFiles, totalFiles: self.totalfiles, currentStage: "Starting Preview Generation", startTime: self.startTime)
        
        self.isRunning = true// Initialize variables
        var ReturnedFiles: [(URL, URL)] = []
        var concurrentTaskLimit = self.maxConcurrentOperations
        var activeTasks = 0
        let pct = 100 / Double(self.videosFiles.count)
        var prog = 0.0
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Log the start of processing
        logger.log(level: .info, "Starting to process \(self.videosFiles.count) files")
        

            do {
                
                // Process files for preview generation
                //
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
                                    let returnfile = try await self.generateAnimatedPreview(
                                        for: videoFile, outputDirectory: outputDirectory,
                                        density: density, previewDuration: previewDuration!)
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
                    
                    self.logger.log(level: .info, "All thumbnails processed.")
                }
            } catch is CancellationError {
                // Handle cancellation
                logger.log(level: .info, "Processing was cancelled")
                
                throw CancellationError()
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
    
    
    /// Creates an M3U8 playlist from video files in a specified directory.
    /// - Parameter directoryPath: The path to the directory containing video files.
    /// - Throws: An error if the playlist creation fails.
    public func createM3U8Playlist(from directoryPath: String) async throws {
        // Step 1: Get all video files from the directory using the getVideoFiles function
        // Note: width is set to 0, adjust if needed for specific use cases
        let videoFiles = try await getVideoFiles(input: directoryPath, width: 0)
        let path = URL(fileURLWithPath: directoryPath, isDirectory: true)
        
        // Step 2: Create the M3U8 playlist content
        var playlistContent = ""
        progressG.totalUnitCount = Int64(videoFiles.count)
        
        // Iterate through each video file and add it to the playlist
        for (videoFile, _) in videoFiles {
            let fileName = videoFile.lastPathComponent
            
            //playlistContent += "#EXTINF:-1,\(fileName)\n"
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
    private func createM3U8Playlisttoday() async throws {
        // Step 1: Get all video files from the directory using the getVideoFiles function
        // Note: width is set to 0, adjust if needed for specific use cases
        //let videoFiles = try await getVideoFiles(input: directoryPath, width: 0)
        let path = self.videosFiles[0].1.deletingLastPathComponent()
        //let path = URL(fileURLWithPath: directoryPath, isDirectory: true)
        
        // Step 2: Create the M3U8 playlist content
        var playlistContent = ""
        progressG.totalUnitCount = Int64(self.videosFiles.count)
        
        // Iterate through each video file and add it to the playlist
        for (videoFile, _) in self.videosFiles {
            let fileName = videoFile.lastPathComponent
            
            //playlistContent += "#EXTINF:-1,\(fileName)\n"
            playlistContent += "\(videoFile.path)\n"
            self.progressG.completedUnitCount += 1
        }
        // create the folder
        if !FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true, attributes: nil)
            logger.log(level: .info, "Created directory: \(path.path)")
        }
        // Step 3: Define the path where the M3U8 file will be saved
        let playlistFileName = "\(path.lastPathComponent).m3u8"
        let playlistFilePath = path
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
    public func createM3U8PlaylistDiff(from directoryPath: String) async throws {
        // Step 1: Get all video files from the directory using the getVideoFiles function
        // Note: width is set to 0, adjust if needed for specific use cases
        let videoFiles = try await getVideoFiles(input: directoryPath, width: 0)
        let path = URL(fileURLWithPath: directoryPath, isDirectory: true)
        
        // Step 2: Create the M3U8 playlist content
        var playlistContentXS = ""
        var playlistContentS = ""
        var playlistContentM = ""
        var playlistContentL = ""
        var playlistContentXL = ""
        let outputdir =  URL(fileURLWithPath: directoryPath, isDirectory: true)
            .appendingPathComponent("0th")
            .appendingPathComponent("playlists")
        try FileManager.default.createDirectory(
            at: outputdir, withIntermediateDirectories: true, attributes: nil)
        
        
        
        progressG.totalUnitCount = Int64(videoFiles.count)
        
        // Iterate through each video file and add it to the playlist
        for (videoFile, _) in videoFiles {
            
            let asset = AVURLAsset(url: videoFile)
            let durationFuture = try await asset.load(.duration)
            
            let duration = try durationFuture.seconds
            print ("processing : \(videoFile.path)")
            
            switch duration {
            case 0...60:
                playlistContentXS += "\(videoFile.path)\n"
            case 60...300:
                playlistContentS += "\(videoFile.path)\n"
            case 300...900:
                playlistContentM += "\(videoFile.path)\n"
            case 900...1800:
                playlistContentL += "\(videoFile.path)\n"
            case 1800...:
                playlistContentXL += "\(videoFile.path)\n"
            default:
                playlistContentM += "\(videoFile.path)\n"
            }
            print ("processed : \(videoFile.path)")
            self.progressG.completedUnitCount += 1
        }
        
        // Step 3: Define the path where the M3U8 file will be saved
        let playlistFileNameXS = "XS-\(path.lastPathComponent).m3u8"
        let playlistFileNameS = "S-\(path.lastPathComponent).m3u8"
        let playlistFileNameM = "M-\(path.lastPathComponent).m3u8"
        let playlistFileNameL = "L-\(path.lastPathComponent).m3u8"
        let playlistFileNameXL = "XL-\(path.lastPathComponent).m3u8"
        
        let playlistFilePathXS = URL(fileURLWithPath: outputdir.path(), isDirectory: true)
            .appendingPathComponent(playlistFileNameXS)
        let playlistFilePathS = URL(fileURLWithPath: outputdir.path(), isDirectory: true)
            .appendingPathComponent(playlistFileNameS)
        let playlistFilePathM = URL(fileURLWithPath: outputdir.path(), isDirectory: true)
            .appendingPathComponent(playlistFileNameM)
        let playlistFilePathL = URL(fileURLWithPath: outputdir.path(), isDirectory: true)
            .appendingPathComponent(playlistFileNameL)
        let playlistFilePathXL = URL(fileURLWithPath: outputdir.path(), isDirectory: true)
            .appendingPathComponent(playlistFileNameXL)
        // Remove existing playlist file if it exists
        var playlists:[(URL,String)] = [(playlistFilePathXS,playlistContentXS),(playlistFilePathS,playlistContentS),(playlistFilePathM,playlistContentM),(playlistFilePathL,playlistContentL),(playlistFilePathXL,playlistContentXL)]
        for playlist in playlists {
            if FileManager.default.fileExists(atPath: playlist.0.path) {
                try FileManager.default.removeItem(at: playlist.0)
                logger.log(level: .info, "Existing playlist file removed: \(playlist.0.path)")
            }
            do {
                try playlist.1.write(to: playlist.0, atomically: true, encoding: .utf8)
                print("M3U8 playlist created at \(playlist.0.path)")
            } catch {
                print("Failed to create M3U8 playlist: \(error.localizedDescription)")
                throw error
            }
            
            
        }
        // Step 4: Write the M3U8 content to a fi
    }
    
    /// Retrieves video files and their corresponding output directories based on the input.
    /// - Parameters:
    ///   - input: The input path for video files.
    ///   - width: The width of the generated mosaic.
    ///   - density: The density of the mosaic.
    /// - Returns: An array of tuples containing the original video URL and the generated mosaic URL.
    /// - Throws: An error if the input is not found or processing fails.
    
    
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
        switch self.custom {
        case true:
            return calculateOptimalMosaicLayoutC(
                originalAspectRatio: thumbnailAspectRatio, estimatedThumbnailCount: thumbnailCount,
                mosaicWidth: width, density: density)
        default:
            return calculateOptimalMosaicLayoutClassic(
                originalAspectRatio: thumbnailAspectRatio, estimatedThumbnailCount: thumbnailCount,
                mosaicWidth: width)
        }
        
    }
    
    /// Retrieves video files from the input source.
    /// - Parameters:
    ///   - input: The input path for video files.
    ///   - width: The width of the generated mosaic.
    /// - Returns: An array of tuples containing the original video URL and the generated mosaic URL.
    /// - Throws: An error if the input is not found or processing fails.
    public func getVideoFiles(input: String, width: Int) async throws -> [(URL, URL)] {
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
        let nf = NotificationCenter.default
        //let query = NSMetadataQuery()
        let query = NSMetadataQuery()
        // Set up the search criteria
        
        
        // Create output base folder URL
        
        
        // Setup date range for today
        
        
        // Create individual predicates for each video type
        let videoTypes = [
            "public.movie",
            "public.video",
            "public.mpeg-4",
            "com.apple.quicktime-movie",
            "public.mpeg",
            "public.avi",
            "public.mkv"
        ]
        
        let typePredicates = videoTypes.map { type in
            NSPredicate(format: "kMDItemContentTypeTree == %@", type)
        }
        
        // Combine type predicates with OR
        //let typePredicate = NSCompoundPredicate(orPredicateWithSubpredicates: typePredicates)
        
        // Combine date and type predicates with AND
        query.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: typePredicates)
        query.searchScopes = [directory]
        query.valueListAttributes = ["kMDItemPath"]
        
        
        nf.addObserver(forName: .NSMetadataQueryDidStartGathering, object: query, queue: .main, using: {_ in
            print("Query did start gathering")
        })
        
        nf.addObserver(forName: .NSMetadataQueryDidUpdate, object: query, queue: .main, using: {_ in
            print("QUery results updated \(query.resultCount)")
        })
        
        
        // Specify the attributes we want to retrieve
        
        return try await withCheckedThrowingContinuation { continuation  in
            nf.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: query,
                queue: .main
            )
            { _ in
                defer {
                    NotificationCenter.default.removeObserver(nf)
                    query.stop()
                }
                
                let files = (query.results as! [NSMetadataItem]).compactMap { item -> (URL, URL)? in
                    guard let path = item.value(forAttribute: "kMDItemPath") as? String else {
                        return nil
                    }
                    var outputDirectory: URL
                    let fileURL = URL(fileURLWithPath: path)
                    if self.saveAtRoot {
                        outputDirectory = directory.appendingPathComponent("0th")
                            .appendingPathComponent("\(width)")
                    } else {
                        outputDirectory = fileURL.deletingLastPathComponent().appendingPathComponent(
                            "0th"
                        ).appendingPathComponent("\(width)")
                    }
                    if (!fileURL.lastPathComponent.lowercased().contains("amprv"))
                    {
                        return (fileURL, outputDirectory)
                    }
                    else
                    {
                        return nil
                    }
                }
                continuation.resume(returning: files)
            }
            DispatchQueue.main.async {
                query.start()
            }
        }
    }
    
    
    /// Retrieves video files from an m3u8 playlist.
    private func getVideoFilesFromPlaylist(_ playlistURL: URL, width: Int) async throws -> [(
        URL, URL
    )] {
        let videoURLs = try parseM3U8File(at: playlistURL)
        
        let playlistName = playlistURL.deletingPathExtension().lastPathComponent
        let outputFolder = playlistURL.deletingLastPathComponent().appendingPathComponent(
            "Playlist"
        ).appendingPathComponent(playlistName)
        
        logger.log(
            level: .info, "Parsed \(videoURLs.count) video URLs from playlist: \(playlistURL)")
        return videoURLs.map { ($0, outputFolder) }
    }
    
    /// Parses an m3u8 file and returns the video URLs.
    private func parseM3U8File(at url: URL) throws -> [URL] {
        //let contents = try String(contentsOf: url)
        let contents = try String(contentsOf: url, encoding: .utf8)
        
        let lines = contents.components(separatedBy: .newlines)
        
        return lines.compactMap { line in
            if !line.hasPrefix("#") && !line.isEmpty {
                return URL(fileURLWithPath: line)
            }
            return nil
        }
    }
    func getVideoFilesCreatedTodayWithPlaylistLocation(width: String) async throws  -> [(URL, URL)] {
        let nf = NotificationCenter.default
        //let query = NSMetadataQuery()
        let query = NSMetadataQuery()
        // Set up the search criteria
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateFolderName = dateFormatter.string(from: Date())
        
        // Create output base folder URL
        let outputBaseURL = URL(fileURLWithPath: "/Volumes/Ext-6TB-2/Playlist/\(dateFolderName)2/\(width)", isDirectory: true)
        
        // Setup date range for today
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        //let start = calendar.date(byAdding: .day, value: -3, to: today)!
        let start = today
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        
        // Date predicate
        let datePredicate = NSPredicate(format: "kMDItemContentCreationDate >= %@ AND kMDItemContentCreationDate < %@",
                                        start as NSDate,
                                        tomorrow as NSDate)
        
        // Create individual predicates for each video type
        let videoTypes = [
            "public.movie",
            "public.video",
            "public.mpeg-4",
            "com.apple.quicktime-movie",
            "public.mpeg",
            "public.avi",
            "public.mkv"
        ]
        
        let typePredicates = videoTypes.map { type in
            NSPredicate(format: "kMDItemContentTypeTree == %@", type)
        }
        
        // Combine type predicates with OR
        let typePredicate = NSCompoundPredicate(orPredicateWithSubpredicates: typePredicates)
        
        // Combine date and type predicates with AND
        query.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, typePredicate])
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        query.valueListAttributes = ["kMDItemPath"]
        
        
        nf.addObserver(forName: .NSMetadataQueryDidStartGathering, object: query, queue: .main, using: {_ in
            print("Query did start gathering")
        })
        
        nf.addObserver(forName: .NSMetadataQueryDidUpdate, object: query, queue: .main, using: {_ in
            print("QUery results updated \(query.resultCount)")
        })
        
        
        // Specify the attributes we want to retrieve
        
        return try await withCheckedThrowingContinuation { continuation  in
            nf.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: query,
                queue: .main
            )
            { _ in
                defer {
                    NotificationCenter.default.removeObserver(nf)
                    query.stop()
                }
                let files = (query.results as! [NSMetadataItem]).compactMap { item -> (URL, URL)? in
                    guard let path = item.value(forAttribute: "kMDItemPath") as? String else {
                        return nil
                    }
                    let fileURL = URL(fileURLWithPath: path)
                    if (!fileURL.lastPathComponent.lowercased().contains("amprv"))
                    {
                        return (fileURL, outputBaseURL)
                    }
                    else
                    {
                        return nil
                    }
                }
                continuation.resume(returning: files)
            }
            DispatchQueue.main.async {
                query.start()
            }
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
        case "s", "c" : densityFactor = 1.0
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
    
    private func generateAnimatedPreview(
        for videoFile: URL,
        outputDirectory: URL,
        density: String,
        previewDuration: Int
    ) async throws -> URL {
        // MARK: - Initialization and Logging Setup
        logger.log(level: .debug, "Generating animated preview for \(videoFile.lastPathComponent)")
        let startTime = CFAbsoluteTimeGetCurrent()
        var coeff: Double = 1.0
        // Setup completion logging and progress tracking
        defer {
            let endTime = CFAbsoluteTimeGetCurrent()
            let processingTime = String(format: "%.2f", endTime - startTime)
            logger.log(level: .info, "Preview generation completed in \(processingTime) seconds for \(videoFile.standardizedFileURL)")
            
            self.processedFiles += 1
            updateProgressG(
                currentFile: videoFile.lastPathComponent,
                processedFiles: self.processedFiles,
                totalFiles: self.totalfiles,
                currentStage: "Processing Files",
                startTime: self.startTime
            )
            self.progressG.completedUnitCount += 1
        }
        
        // MARK: - Asset Loading and Duration Calculation
        let asset = AVURLAsset(url: videoFile)
        let Movieduration = try await asset.load(.duration).seconds
        print("\n=== Video Information ===")
        print("Video duration: \(String(format: "%.2f", Movieduration)) seconds")
        
        let minextractDuration = 2.0
        // MARK: - Density Configuration
        // Configure extract parameters based on density setting
        let densityConfig: (factor: Double, extractsMultiplier: Double)
        switch density.lowercased() {
        case "xxl": densityConfig = (4.0, 0.25)    // Fewer, longer extracts
        case "xl":  densityConfig = (3.0, 0.5)
        case "l":   densityConfig = (2.0, 0.75)
        case "m":   densityConfig = (1.0, 1.0)
        case "s":   densityConfig = (0.75, 1.5)
        case "xs":  densityConfig = (0.5, 2.0)
        case "xxs": densityConfig = (0.25, 3.0)    // More, shorter extracts
        default:    densityConfig = (1.0, 1.0)
        }
        print("\n=== Density Configuration ===")
        print("Density: \(density)")
        print("Factor: \(densityConfig.factor)")
        print("Extracts Multiplier: \(densityConfig.extractsMultiplier)")
        
        // MARK: - Extract Rate Calculation
        // Calculate base number of extracts per minute using hyperbolic decay
        let baseExtractsPerMinute: Double
        if Movieduration > 0 {
            let durationInMinutes = Movieduration / 60.0
            let initialRate = 12.0  // Maximum rate for very short videos
            let decayFactor = 0.2   // Controls how quickly the rate decreases
            baseExtractsPerMinute = (initialRate / (1 + decayFactor * durationInMinutes)) / densityConfig.extractsMultiplier
        } else {
            baseExtractsPerMinute = 12.0
        }
        print("\n=== Extract Rate Calculation ===")
        print("Duration in minutes: \(String(format: "%.2f", Movieduration / 60.0))")
        print("Base extracts per minute: \(String(format: "%.2f", baseExtractsPerMinute))")
        
        // MARK: - Extract Parameters Calculation
        // Calculate number of extracts and their duration
        let minutes = Movieduration / 60.0
        
        let extractCount = Int(
            ceil(minutes * baseExtractsPerMinute)
        )
        print("total extract \(extractCount)")
        var extractDurationBase = Double(previewDuration) / Double(extractCount)
        print("extract duration base: \(String(format: "%.2f", extractDurationBase))")
        
        if (extractDurationBase < minextractDuration) {
            print("extraction < min duration")
            extractDurationBase = minextractDuration
            coeff = (extractDurationBase * Double(extractCount)) / Double(previewDuration)
        }
        print("coeff: \(String(format: "%.2f", coeff))")
        
        // Calculate preview duration (clamped between 10 seconds and 2 minutes)
        let finalPreviewDuration = extractDurationBase * Double(extractCount) / coeff
        print("adj preview duration: \(String(format: "%.2f", finalPreviewDuration))")
        // Calculate individual extract duration
        let extractDuration = extractDurationBase
        
        print("\n=== Extract Parameters ===")
        print("Total extract count: \(extractCount)")
        print("Preview duration: \(String(format: "%.2f", finalPreviewDuration)) seconds")
        print("Extract duration: \(String(format: "%.2f", extractDuration)) seconds")
        
        // MARK: - Output File Setup
        let previewDirectory = outputDirectory.deletingLastPathComponent()
            .appendingPathComponent("amprv", isDirectory: true)
        try FileManager.default.createDirectory(
            at: previewDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        
        let previewURL = previewDirectory.appendingPathComponent(
            "\(videoFile.deletingPathExtension().lastPathComponent)-amprv-\(density)-\(extractCount).mp4")
        
        // Remove existing preview if present
        if FileManager.default.fileExists(atPath: previewURL.path) {
            try FileManager.default.removeItem(at: previewURL)
            logger.log(level: .info, "Existing preview file removed: \(previewURL.path)")
        }
        
        // MARK: - Composition Setup
        // Create composition and tracks
        let composition = AVMutableComposition()
        guard
            let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ),
            let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ),
            let videoTrack = try await asset.loadTracks(withMediaType: .video).first,
            let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        else {
            throw MosaicError.unableToCreateCompositionTracks
        }
        
        // MARK: - Playback Configuration
        let originalFrameRate = try await videoTrack.load(.nominalFrameRate)
        
        let timescale: CMTimeScale = 600
        let durationCMTime = CMTime(seconds: extractDuration, preferredTimescale: timescale)
        let fastPlaybackDuration = CMTime(
            seconds: extractDuration / coeff,
            preferredTimescale: timescale
        )
        
        print("\n=== Playback Configuration ===")
        print("Original frame rate: \(originalFrameRate)")
        print("Speed multiplier: \(String(format: "%.2f", coeff))")
        print("Extract CMTime duration: \(durationCMTime.seconds) seconds")
        print("Fast playback duration: \(fastPlaybackDuration.seconds) seconds")
        
        // MARK: - Extract and Compose Segments
        var currentTime = CMTime.zero
        for i in 0..<extractCount {
            let startTime = CMTime(
                seconds: Double(i) * (Movieduration - extractDuration) / Double(extractCount - 1),
                preferredTimescale: timescale
            )
            
            do {
                let timeRange = CMTimeRange(start: currentTime, duration: durationCMTime)
                //   print("extract i: \(i), timerange: \(timeRange.duration.seconds), at \(currentTime.seconds), changing time range to \(fastPlaybackDuration.seconds)")
                // Insert video and audio segments
                try await compositionVideoTrack.insertTimeRange(
                    CMTimeRange(start: startTime, duration: durationCMTime),
                    of: videoTrack,
                    at: currentTime)
                try compositionVideoTrack.scaleTimeRange(timeRange, toDuration: fastPlaybackDuration)
                
                
                
                try await compositionAudioTrack.insertTimeRange(
                    CMTimeRange(start: startTime, duration: durationCMTime),
                    of: audioTrack,
                    at: currentTime
                )
                
                try compositionAudioTrack.scaleTimeRange(timeRange, toDuration: fastPlaybackDuration)
                
                
                // Scale segments to fast playback duration
                
                //  print("extract i: \(i), timerange: \(timeRange.duration.seconds), at \(currentTime.seconds), changing time range to \(fastPlaybackDuration.seconds)")
                
                currentTime = CMTimeAdd(currentTime, fastPlaybackDuration)
            } catch {
                logger.error("Failed to insert or scale time range: \(error.localizedDescription)")
            }
        }
        
        // MARK: - Export Configuration and Processing
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHEVC1920x1080
        ) else {
            throw MosaicError.unableToCreateExportSession
        }
        
        // Configure video composition
        let videoComposition = AVMutableVideoComposition(propertiesOf: composition)
        videoComposition.frameDuration = CMTime(
            value: 1,
            timescale: CMTimeScale(originalFrameRate * Float(coeff))
        )
        // Configure export session
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = false
        exportSession.videoComposition = videoComposition
        exportSession.allowsParallelizedExport = true
        exportSession.directoryForTemporaryFiles = FileManager.default.temporaryDirectory
        
        //if (coeff < 2)
        //{
        // Configure audio mix
        let audioMix = AVMutableAudioMix()
        let audioParameters = AVMutableAudioMixInputParameters(track: compositionAudioTrack)
        audioMix.inputParameters = [audioParameters]
        exportSession.audioMix = audioMix
        /*}
         else
         {   print("no audio")
         exportSession.audioMix = nil
         }
         */
        let estimatedDuration = await exportSession.estimatedMaximumDuration.seconds
        let estimatedSize = await exportSession.estimatedOutputFileLengthInBytes
        // Export the preview
        print ("esting duration: \(estimatedDuration), size: \(estimatedSize)")
        try await exportVid(for: exportSession, previewURL: previewURL)
        
        print("\n=== Export Complete ===")
        print("Preview saved to: \(previewURL.path)")
        
        return previewURL
    }
    
    /// Exports a video file to a specified URL.
    /// - Parameters:
    ///   - exportSession: The export session for the video.
    ///   - previewURL: The URL to save the exported video.
    /// - Throws: An error if the export fails.
    private func exportVid(for exportSession: AVAssetExportSession, previewURL: URL) async throws {
        exportSession.outputURL = previewURL
        
        // Create a progress tracking task using the new states API
        let progressTracking = Task {
            for await state in await exportSession.states(updateInterval: 1) {
                if Task.isCancelled { break }
                
                let currentProgress = exportSession.progress
                
                let percentage = Int(currentProgress * 100)
                
                // Update progress in log and status
                //logger.log(level: .debug, "Export progress: \(percentage)%")
                print("\(previewURL.lastPathComponent) Export progress: \(percentage)% status : \(exportSession.status.rawValue)")
                
                // Update status message with export progress
                updateProgressG(
                    currentFile: previewURL.lastPathComponent,
                    processedFiles: self.processedFiles,
                    totalFiles: self.totalfiles,
                    currentStage: "Exporting preview (\(percentage)%)",
                    startTime: self.startTime
                )
                
                // Break if we're no longer exporting
                if exportSession.status == .completed {
                    break
                }
            }
        }
        
        // Start the export using the newer async API
        try await withThrowingTaskGroup(of: Void.self) { group in
            // Add progress tracking task
            group.addTask {
                await progressTracking
            }
            
            // Add export task with completion handler
            group.addTask {
                do {
                    try await exportSession.export(to: previewURL, as: .mp4)
                }
                catch
                {
                    self.logger.error(
                        "Failed to process file: \(previewURL.absoluteString), error: \(error.localizedDescription)")
                    
                }
            }
            // Wait for both tasks to complete
            try await group.waitForAll()
        }
        
        // Get final export result using newer states API
        let finalState = await exportSession.status
        switch finalState {
        case .completed:
            logger.log(level: .info, "Export completed successfully: \(previewURL.path)")
        case .failed:
            // Use the newer export(to:as:) method which throws errors directly
            logger.error("Export failed")
            throw MosaicError.unableToGenerateMosaic
        case .cancelled:
            logger.log(level: .info, "Export was cancelled")
            throw CancellationError()
        default:
            logger.error("Export ended with unexpected state: \(finalState.rawValue)")
            throw MosaicError.unableToGenerateMosaic
        }
    }
    
    
    func generateRowConfigs(largeCols: Int, largeRows: Int, smallCols: Int, smallRows: Int) -> [(Int, Int)] {
        var rowConfigs: [(Int, Int)] = []
        
        // Calculate total rows
        let totalRows = largeRows * 2  + smallRows
        
        for _ in 0..<(smallRows/2) {
            rowConfigs.append((smallCols, 0))
        }
        for _ in 0..<largeRows {
            rowConfigs.append((0, largeCols))
        }
        for _ in 0..<(smallRows/2) {
            rowConfigs.append((smallCols, 0))
        }
        return rowConfigs
    }
    /// Calculates the optimal layout for the mosaic based on the original aspect ratio and estimated thumbnail count.
    /// - Parameters:
    ///   - originalAspectRatio: The aspect ratio of the original video.
    ///   - estimatedThumbnailCount: The estimated number of thumbnails.
    ///   - mosaicWidth: The width of the mosaic.
    /// - Returns: The optimal mosaic layout.
    func calculateOptimalMosaicLayoutC(
        originalAspectRatio: CGFloat,
        estimatedThumbnailCount: Int,
        mosaicWidth: Int,
        density: String
    ) -> MosaicLayout {
        // let cacheKey = "\(originalAspectRatio)-\(estimatedThumbnailCount)-\(mosaicWidth)-\(density)"
        //if let cachedLayout = layoutCache[cacheKey] {
        //   return cachedLayout
        //}
        //let cacheKey = "\(originalAspectRatio)-\(estimatedThumbnailCount)-\(mosaicWidth)-\(density)"
        // if let cachedLayout = layoutCache[cacheKey] {
        //  return cachedLayout
        //}
        
        let mosaicAspectRatio: CGFloat = 16.0 / 9.0
        let mosaicHeight = Int(CGFloat(mosaicWidth) / mosaicAspectRatio)
        
        func calculateDynamicLayout() -> MosaicLayout {
            var rowConfigs: [(smallCount: Int, largeCount: Int)] = []
            var smallThumbWidth:CGFloat = 0.0
            var largeThumbWidth:CGFloat = 0.0
            var smallThumbHeight:CGFloat = 0.0
            var largeThumbHeight:CGFloat = 0.0
            var largeCols = 0
            var smallCols = 0
            var largeRows = 0
            var smallRows = 0
            var totalRows = 0
            var TotalCols = 0
            switch density {
            case "XXL":
                largeCols = 2
                largeRows = 1
                smallCols = 4
                smallRows = 2
            case "XL":
                largeCols = 3
                largeRows = 1
                smallCols = 6
                smallRows = 2
                
            case "L":
                
                largeCols = 3
                largeRows = 2
                smallCols = 6
                smallRows = 4
                
            case "M":
                
                largeCols = 4
                largeRows = 2
                smallCols = 8
                smallRows = 4
                
            case "S":
                largeCols = 6
                largeRows = 2
                smallCols = 12
                smallRows = 4
                
            case "XS":
                
                largeCols = 8
                largeRows = 2
                smallCols = 16
                smallRows = 4
                
            case "XXS":
                
                largeCols = 9
                largeRows = 4
                smallCols = 18
                smallRows = 8
                
            default:
                
                largeCols = 4
                largeRows = 2
                smallCols = 8
                smallRows = 4
                
            }
            
            if originalAspectRatio < 1.0  {
                
                if smallRows > 2 {
                    smallRows = smallRows/2
                }
                smallCols = smallCols * 2
                largeCols = largeCols * 2
            }
            TotalCols = smallCols
            
            smallThumbWidth = CGFloat(CGFloat(mosaicWidth) / Double(TotalCols))
            smallThumbHeight = smallThumbWidth / originalAspectRatio
            if originalAspectRatio < 1.0  {
                var mozW = smallThumbWidth * CGFloat(TotalCols)
                var mozH = smallThumbHeight * CGFloat(smallRows + largeRows * 2)
                var mozAR = Double(mozW) / Double(mozH)
                while mozAR < mosaicAspectRatio
                {
                    smallCols += 2
                    largeCols += 1
                    TotalCols = smallCols
                    mozW = smallThumbWidth * CGFloat(TotalCols)
                    mozH = smallThumbHeight * CGFloat(smallRows + largeRows * 2)
                    mozAR = Double(mozW) / Double(mozH)
                }
            }
            else
            {
                var tmpTotalRows = Int(mosaicHeight / Int(smallThumbHeight))
                var diff = tmpTotalRows - (smallRows + 2 * largeRows)
                // if potential rows < small rows + 2x large rows , add a large row
                while diff > 0 {
                    if (diff >= 2)
                    {
                        largeRows += 1
                        diff -= 2
                    }else{
                        if (diff >= 1)
                        {
                            smallRows += 1
                            diff -= 1
                        }
                    }
                }
            }
            
            
            
            
            rowConfigs = generateRowConfigs(largeCols: largeCols, largeRows: largeRows, smallCols: smallCols, smallRows: smallRows)
            
            let totalSmallThumbs = smallCols * smallRows
            let totalLargeThumbs = largeCols * largeRows
            // let totalRows = rowConfigs.count
            
            smallThumbWidth = CGFloat(CGFloat(mosaicWidth) / Double(smallCols))
            largeThumbWidth = smallThumbWidth * 2
            smallThumbHeight = smallThumbWidth / originalAspectRatio
            largeThumbHeight = largeThumbWidth / originalAspectRatio
            totalRows = smallRows + 2 * largeRows
            TotalCols = smallCols
            let count = totalLargeThumbs + totalSmallThumbs
            
            var positions: [(x: Int, y: Int)] = []
            var thumbnailSizes: [CGSize] = []
            var rowHeight:CGFloat = 0
            var y:CGFloat = 0
            for (smallCount, largeCount) in rowConfigs {
                var x:CGFloat = 0
                if smallCount > 0 {
                    for _ in 0..<smallCount {
                        print("small : \(smallCount) x: \(x) y: \(y) smallThumbWidth: \(smallThumbWidth) smallThumbHeight: \(smallThumbHeight)")
                        positions.append((x: Int(x), y: Int(y)))
                        thumbnailSizes.append(CGSize(width: smallThumbWidth, height: smallThumbHeight))
                        x += smallThumbWidth
                        rowHeight = smallThumbHeight
                    }
                } else {
                    for _ in 0..<largeCount {
                        print("large : \(largeCount) x: \(x) y: \(y) largeThumbWidth: \(largeThumbWidth) largeThHubHeight: \(largeThumbHeight)")
                        
                        positions.append((x: Int(x), y: Int(y)))
                        thumbnailSizes.append(CGSize(width: largeThumbWidth, height: largeThumbHeight))
                        x += largeThumbWidth
                        rowHeight = largeThumbHeight
                    }
                }
                y += rowHeight
            }
            
            return MosaicLayout(
                rows: totalRows,
                cols: TotalCols,
                thumbnailSize: CGSize(width: smallThumbWidth, height: smallThumbHeight),
                positions: positions,
                thumbCount: count,
                thumbnailSizes: thumbnailSizes,
                mosaicSize: CGSize(width: mosaicWidth, height: totalRows*Int(smallThumbHeight))
            )
        }
        
        
        let layout = calculateDynamicLayout()
        //  layoutCache[cacheKey] = layout
        return layout
    }
    
    
    
    func calculateOptimalMosaicLayoutClassic(
        originalAspectRatio: CGFloat,
        estimatedThumbnailCount: Int,
        mosaicWidth: Int
    ) -> MosaicLayout {
        
        var count = estimatedThumbnailCount
        let state = signposter.beginInterval("calculateOptimalMosaicLayout", id: signpostID)
        defer {
            signposter.endInterval("calculateOptimalMosaicLayout", state)
        }
        let cacheKey = "\(originalAspectRatio)-\(estimatedThumbnailCount)-\(mosaicWidth)"
        if let cachedLayout = layoutCache[cacheKey] {
            return cachedLayout
        }
        let mosaicAspectRatio: CGFloat = 16.0 / 9.0
        let mosaicHeight = Int(CGFloat(mosaicWidth) / mosaicAspectRatio)
        var thumbnailSizes: [CGSize] = []
        
        func calculateLayout(rows: Int) -> MosaicLayout {
            let cols = Int(ceil(Double(count) / Double(rows)))
            
            let thumbnailWidth = CGFloat(mosaicWidth) / CGFloat(cols)
            let thumbnailHeight = thumbnailWidth / originalAspectRatio
            
            let adjustedRows = min(rows, Int(ceil(CGFloat(mosaicHeight) / thumbnailHeight)))
            
            var positions: [(x: Int, y: Int)] = []
            var y:CGFloat = 0
            for row in 0..<adjustedRows {
                var x:CGFloat = 0
                for col in 0..<cols {
                    if positions.count < count {
                        print("x: \(x) y: \(y) largeThumbWidth: \(thumbnailWidth) largeThHubHeight: \(thumbnailHeight)")
                        positions.append((x: Int(x), y: Int(y)))
                        x += thumbnailWidth
                        thumbnailSizes.append(CGSize(width: thumbnailWidth, height: thumbnailHeight))
                        
                    } else {
                        break
                    }
                }
                y += thumbnailHeight
            }
            return MosaicLayout(
                rows: adjustedRows,
                cols: cols,
                thumbnailSize: CGSize(width: thumbnailWidth, height: thumbnailHeight),
                positions: positions,
                thumbCount: count,
                thumbnailSizes: thumbnailSizes,
                mosaicSize: CGSize(width: thumbnailWidth*CGFloat(cols), height: thumbnailHeight*CGFloat(adjustedRows))                )
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
        from file: URL, layout: MosaicLayout, asset: AVAsset, preview: Bool, accurate: Bool, batchSize: Int = 20
    ) async throws -> [(image: CGImage, timestamp: String)] {
        let state = signposter.beginInterval("extractThumbnailsWithTimestamps2", id: signpostID)
        defer {
            signposter.endInterval("extractThumbnailsWithTimestamps2", state)
        }
        let  count = layout.thumbCount
        logger.log(level: .debug, "Starting thumbnail extraction for \(file.lastPathComponent): count=\(count), preview=\(preview), accurate=\(accurate)")
        
        let startTime = CFAbsoluteTimeGetCurrent()
        let duration = try await asset.load(.duration).seconds
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        if (accurate) {
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0, preferredTimescale: 600)
        } else {
            generator.requestedTimeToleranceBefore = CMTime(seconds: 2, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 2, preferredTimescale: 600)
        }
        
        if !preview {
            generator.maximumSize = CGSize(width: layout.thumbnailSize.width * 2, height: layout.thumbnailSize.width * 2 )
        }
        let startPoint = duration * 0.05
        let endPoint = duration * 0.95
        let effectiveDuration = endPoint - startPoint
        
        let firstThirdCount = Int(Double(count) * 0.2)
        let middleCount = Int(Double(count) * 0.6)
        let lastThirdCount = count - firstThirdCount - middleCount
        
        let firstThirdEnd = startPoint + effectiveDuration * 0.33
        let lastThirdStart = startPoint + effectiveDuration * 0.67
        
        let firstThirdStep = (firstThirdEnd - startPoint) / Double(firstThirdCount)
        let middleStep = (lastThirdStart - firstThirdEnd) / Double(middleCount)
        let lastThirdStep = (endPoint - lastThirdStart) / Double(lastThirdCount)
        
        // Break down the complex expression into separate parts
        let firstThirdTimes = (0..<firstThirdCount).map { index in
            CMTime(seconds: startPoint + Double(index) * firstThirdStep, preferredTimescale: 600)
        }
        
        let middleTimes = (0..<middleCount).map { index in
            CMTime(seconds: firstThirdEnd + Double(index) * middleStep, preferredTimescale: 600)
        }
        
        let lastThirdTimes = (0..<lastThirdCount).map { index in
            CMTime(seconds: lastThirdStart + Double(index) * lastThirdStep, preferredTimescale: 600)
        }
        
        // Combine the separate arrays
        let times = firstThirdTimes + middleTimes + lastThirdTimes
        
        var thumbnailsWithTimestamps: [(Int, CGImage, String)] = []
        var index = 0
        var failedCount = 0
        
        for await result in generator.images(for: times) {
            switch result {
            case .success(requestedTime: _, image: let image, actualTime: let actual):
                signposter.emitEvent("Image extracted")
                thumbnailsWithTimestamps.append((index, image, self.formatTimestamp(seconds: actual.seconds)))
                index += 1
            case .failure(requestedTime: _, error: let error):
                self.logger.error("Thumbnail extraction failed for \(file.lastPathComponent): \(error.localizedDescription)")
                failedCount += 1
            }
        }
        
        if failedCount > 0 {
            self.logger.warning("Partial failure in thumbnail extraction: \(thumbnailsWithTimestamps.count) successful, \(failedCount) failed")
            if thumbnailsWithTimestamps.isEmpty {
                throw ThumbnailExtractionError.partialFailure(successfulCount: thumbnailsWithTimestamps.count, failedCount: failedCount)
            }
        }
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let elapsedTime = endTime - startTime
        logger.log(level: .debug, "Thumbnail extraction completed for \(file.lastPathComponent): extracted=\(thumbnailsWithTimestamps.count), failed=\(failedCount), time=\(elapsedTime) seconds")
        
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
    
    
    
    /// Draws a timestamp on a thumbnail.
    private func drawTimestamp(context: CGContext, timestamp: String, x: Int, y: Int, width: Int, height: Int) {
        let fontSize = CGFloat(height) / 6 / 1.618
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.cgColor
        ]
        let attributedTimestamp = NSAttributedString(string: timestamp, attributes: attributes)
        // let attributedTimestamp = CFAttributedStringCreate(nil, timestamp as CFString, attributes as CFDictionary)
        // let line = CTLineCreateWithAttributedString(attributedTimestamp!)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedTimestamp)
        
        context.saveGState()
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 0.2))
        let textRect = CGRect(x: x, y: y, width: width, height: Int(CGFloat(height) / 6))
        //context.fill(textRect)
        let path = CGPath(rect: textRect, transform: nil)
        
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
        
        context.saveGState()
        CTFrameDraw(frame, context)
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
    private func generateOptMosaicImagebatch2old(
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
        print("width: \(width), height: \(height), thumbnailWidth: \(thumbnailWidth), thumbnailHeight: \(thumbnailHeight)")
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
            var lisTS: [TimeStamp] = []
            // 4. Use DispatchQueue for concurrent drawing of thumbnails
            DispatchQueue.concurrentPerform(iterations: min(thumbnailsWithTimestamps.count, layout.positions.count)) { index in
                let (thumbnail, timestamp) = thumbnailsWithTimestamps[index]
                let position = layout.positions[index]
                let x = Int(CGFloat(position.x) * layout.thumbnailSize.width)
                let y = height - Int(CGFloat(position.y + 1) * layout.thumbnailSize.height)
                context.draw(
                    thumbnail, in: CGRect(x: x, y: y, width: thumbnailWidth, height: thumbnailHeight))
                if self.time {
                    lisTS.append(TimeStamp(ts: timestamp, x: x, y: y, w: thumbnailWidth, h: thumbnailHeight))
                    //drawTimestamp2(context: context, timestamp: timestamp, x: x, y: y, width: thumbnailWidth, height: thumbnailHeight)
                }
            }
            
            if self.time {
                drawTimestamp3(context: context, timestamps: lisTS)
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
        
        let width = Int(layout.mosaicSize.width)
        let height = Int(layout.mosaicSize.height)
        //   let thumbnailWidth = Int(layout.thumbnailSize.width)
        // let thumbnailHeight = Int(layout.thumbnailSize.height)
        // print("width: \(width), height: \(height), thumbnailWidth: \(thumbnailWidth), thumbnailHeight: \(thumbnailHeight)")
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
            
            // var lisTS: [TimeStamp] = []
            var lisTS =  Array(repeating: TimeStamp(ts: "", x: 0, y: 0, w: 0, h: 0),
                               count: min(thumbnailsWithTimestamps.count, layout.positions.count))
            // 4. Use DispatchQueue for concurrent drawing of thumbnails
            DispatchQueue.concurrentPerform(iterations: min(thumbnailsWithTimestamps.count, layout.positions.count)) { index in
                let (thumbnail, timestamp) = thumbnailsWithTimestamps[index]
                let position = layout.positions[index]
                let thumbnailSize = layout.thumbnailSizes[index]
                let x = position.x
                let y = height - Int(thumbnailSize.height) - position.y
                
                
                context.draw(
                    thumbnail, in: CGRect(x: x, y: y, width: Int(thumbnailSize.width), height: Int(thumbnailSize.height)))
                
                if self.time {
                    
                    lisTS[index] = (TimeStamp(ts: timestamp, x: x, y: y, w: Int(thumbnailSize.width), h: Int(thumbnailSize.height)))
                }
            }
            
            
            if self.time {
                drawTimestamp3(context: context, timestamps: lisTS)
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
    
    private func drawTimestamp3(context: CGContext,timestamps: [TimeStamp]) {
        for (ts) in timestamps {
            let fontSize = CGFloat(ts.h) / 6 / 1.618
            let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white.cgColor
            ]
            let attributedTimestamp = CFAttributedStringCreate(nil, ts.ts as CFString, attributes as CFDictionary)
            let line = CTLineCreateWithAttributedString(attributedTimestamp!)
            
            context.saveGState()
            context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.1))
            let textRect = CGRect(x: ts.x, y: ts.y, width: ts.w, height: Int(CGFloat(ts.h) / 7))
            context.fill(textRect)
            // print("x : \(ts.x) y : \(ts.y), width : \(ts.w), height : \(ts.h), timestamp : \(ts.ts)")
            let textWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
            let textPosition = CGPoint(x: ts.x + ts.w - Int(textWidth) - 5, y: ts.y + 10)
            
            context.textPosition = textPosition
            CTLineDraw(line, context)
            context.restoreGState()
            
        }
    }
    
    /// Generates an output file name for the mosaic image.
    private func getOutputFileName(for videoFile: URL, in directory: URL, format: String, overwrite: Bool, density: String, type: String, addpath: Bool? = false) throws -> String {
        var baseName = ""
        var fileName = ""
        let fileExtension = format.lowercased()
        if addpath == false
        {
            baseName = videoFile.deletingPathExtension().lastPathComponent
            fileName = "\(type)-\(baseName)-\(density).\(fileExtension)"
        }
        else
        {
            //the basename will be <all path components> seperated by "-" and the file name
            baseName = videoFile.deletingPathExtension().path.split(separator: "/").joined(separator: "-")
            fileName = "\(baseName)-\(density)-\(type).\(fileExtension)"
        }
        
        
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(fileName).path) {
            if overwrite {
                try FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
                break
            }
            else {
                return "exist"
            }
            /* version += 1
             fileName = "\(type)-\(baseName)-\(density)_v\(version).\(fileExtension)"*/
        }
        return fileName
    }
    
    
    
    /// Saves the generated mosaic image to disk.
    private func saveMosaic(mosaic: CGImage, for videoFile: URL, in outputDirectory: URL, format: String, overwrite: Bool, width: Int, density: String, type: String, addpath: Bool? = false) async throws -> URL {
        let state = signposter.beginInterval("saveMosaic", id: signpostID)
        defer {
            signposter.endInterval("saveMosaic", state)
        }
        
        // Ensure output directory exists
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true, attributes: nil)
        
        // Get the file name for the output image
        let fileName = try getOutputFileName(for: videoFile, in: outputDirectory, format: format, overwrite: overwrite, density: density, type: type, addpath: addpath)
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
        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, AVFileType.heic.rawValue as CFString, 1,nil) else {
            throw NSError(domain: "HEICError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create HEIC destination"])
        }
        
        // Create the compression options
        let options: [String: Any] = [
            kCGImageDestinationLossyCompressionQuality as String: 0.2 ,
            kCGImageDestinationEmbedThumbnail as String: true // Compression quality (0.0 to 1.0)
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
    
}

