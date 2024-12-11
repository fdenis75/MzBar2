//
//  GenerationCoordinator.swift
//  MZBar
//
//  Created by Francois on 02/11/2024.
//


import Foundation
import AVFoundation
import os.log


/// Coordinates the generation of mosaics, previews, and playlists
public final class GenerationCoordinator {
    let signposter = OSSignposter(logHandle: .mosaic)
    private let logger = Logger(subsystem: "com.mosaic.generation", category: "GenerationCoordinator")
    private var config: MosaicGeneratorConfig
    //let generator: MosaicGenerator
    struct previewGens {
        let generator: PreviewGenerator
        let filename: String
    }
    struct mosaicGens {
        let generator: MosaicGenerator
        let filename: String
    }
    
    private var mosaicGenerator: MosaicGenerator
    private var previewGenerators: [previewGens]
    private var mosaicGenerators: [mosaicGens]
    
    private let playlistGenerator: PlaylistGenerator
    private let exportManager: ExportManager
    private var maxTasks: Int
    
    private var progressHandler: ((ProgressInfo) -> Void)?
    private var isRunning = false
    private var isCancelled = false
    private var backgroundActivities: [String: NSObjectProtocol] = [:]
    private let processQueue = DispatchQueue(label: "com.mosaic.generation", qos: .userInitiated)
    private let previewEngine: PreviewEngine
    private var cancelledFiles: Set<String> = []
    struct ActiveFile {
        let filename: String
        var isCancelled: Bool = false
    }
    private var activeFiles: [ActiveFile] = []
    private var lastUpdateTime: CFAbsoluteTime = 0
    private let layoutProcessor: LayoutProcessor
    
    /// Initialize a new generation coordinator
    /// - Parameter config: Configuration for generation processes
    public init(config: MosaicGeneratorConfig = .default) {
        self.config = config
        self.maxTasks = config.maxConcurrentOperations
        self.mosaicGenerator = MosaicGenerator(config: config)
        self.previewGenerators = []
        self.mosaicGenerators = []
        self.playlistGenerator = PlaylistGenerator()
        self.exportManager = ExportManager(config: config)
        self.previewEngine = config.previewEngine
        self.layoutProcessor = LayoutProcessor()
        ()
    }
    
    /// Set progress handler for generation updates
    /// - Parameter handler: Progress handler closure
    public func setProgressHandler(_ handler: @escaping (ProgressInfo) -> Void) {
        self.progressHandler = handler
    }
    private func setupmosaicGenerator(_ generator: MosaicGenerator ) {
        generator.setProgressHandler { [weak self] info in
            self?.progressHandler?(info)
        }
    }
    private func setupPreviewGenerator(_ generator: PreviewGenerator) {
        generator.setProgressHandler { [weak self] info in
            self?.progressHandler?(info)
        }
    }
     public func updateConfig(_ config: MosaicGeneratorConfig) {
        self.config = config
        
    }

    public func updateCodec(_ codec: String)
    {
        self.config.videoExportPreset = codec
    }
    public func updateMaxConcurrentTasks(_ maxConcurrentTasks: Int) {
        self.maxTasks = maxConcurrentTasks
    }
    


    
    /// Generate mosaics for video files
       /// - Parameters:
       ///   - files: Array of video files and their output locations
       ///   - width: Width of generated mosaics
       ///   - density: Density configuration
       ///   - format: Output format
       ///   - options: Additional generation options
       /// - Returns: Array of processed files and their outputs
       /// actif avec UI
       public func generateMosaics(
           for files: [(video: URL, output: URL)],
           width: Int,
           density: String,
           format: String,
           options: GenerationOptions
       ) async throws -> [ResultFiles] {
           let activemozLock = DispatchQueue(label: "com.mosaic.activemozLock")

           func incrementActiveTasks() {
               activemozLock.sync { activemozTasks += 1 }
           }

           func decrementActiveTasks() {
               activemozLock.sync { activemozTasks -= 1 }
           }
           isRunning = true
           isCancelled = false
           var results: [ResultFiles] = []
           var activemozTasks = 0
           
           let totalFiles = files.count
           var processedFiles = 0
           var skippedFiles = 0
           var errorFiles = 0
           let startTime = CFAbsoluteTimeGetCurrent()
           //activeFiles = []
           let mainActivity = startBackgroundActivity(reason: "mosa Generation")
           defer {
               endBackgroundActivity(mainActivity)
               isRunning = false
               self.updateProgress(
                   currentFile: "Finished",
                   processedFiles: processedFiles,
                   totalFiles: totalFiles,
                   startTime: startTime,
                   skippedFiles: skippedFiles,
                   errorFiles: errorFiles
               )
           }
           do {
               try await withThrowingTaskGroup(of: Void.self) { group in
                   for (video, outputDirectory) in files {
                       if isCancelled { throw CancellationError() }
                       if isFileCancelled(video.lastPathComponent) {
                           skippedFiles += 1
                           continue
                       }
                       while activemozTasks >= maxTasks {
                           try await group.next()
                       }
                       incrementActiveTasks()
                       group.addTask {
                           do {
                               let fileActivity = self.startBackgroundActivity(
                                   reason: "Processing \(video.lastPathComponent)"
                               )
                              // print("activemozTasks: \(activemozTasks)")
                               defer {
                                   // self.activeFiles.removeAll(where: { $0.filename == video.path() })
                                   self.endBackgroundActivity(fileActivity) }
                               
                               if self.isFileCancelled(video.lastPathComponent) {
                                   throw CancellationError()
                               }
                               let mosaicGenerator = MosaicGenerator(config: self.config, layoutProcessor: self.layoutProcessor)
                               self.setupmosaicGenerator(mosaicGenerator)
                               self.mosaicGenerators.append(mosaicGens(generator: mosaicGenerator, filename: video.path))
                               let config = ProcessingConfiguration(width: width, density: density, format: format, previewDuration: options.minimumDuration,separateFolders: options.useSeparateFolder,addFullPath: options.addFullPath,addBorder: options.addBorder,addShadow: options.addShadow,borderWidth: options.borderWidth)
                               let result = try await mosaicGenerator.processSingleFile(video: video, output: outputDirectory, config: config)
                               
                               results.append(result)
                               processedFiles += 1
                               decrementActiveTasks()
                           } catch {
                               switch error {

                           case  MosaicError.existingVid:
                               self.logger.error("video alredy exists: \(error.localizedDescription)")
                               skippedFiles += 1
                               processedFiles += 1
                                   decrementActiveTasks()
                           case MosaicError.tooShort:
                               self.logger.error("skipped because too short to process video: \(error.localizedDescription)")
                               skippedFiles += 1
                               processedFiles += 1
                                   decrementActiveTasks()
                               default:
                               self.logger.error("Failed to process video: \(error.localizedDescription)")
                               errorFiles += 1
                               processedFiles += 1
                                   decrementActiveTasks()
                                   
                           }
                       }
                               
                           
                           self.updateProgress(
                               currentFile: "",
                               processedFiles: processedFiles,
                               totalFiles: totalFiles,
                               startTime: startTime,
                               skippedFiles: skippedFiles,
                               errorFiles: errorFiles)
                           
                       }
                   }
                   
                   self.logger.debug("Waiting for all tasks to complete")
                   try await group.waitForAll()
                   /*if options.generatePlaylist {
                    try await generatePlaylists(for: results, outputDirectory: files[0].output)
                    }*/
               }
           }
               catch {
                   switch error {
                   case is CancellationError:
                       endBackgroundActivity(mainActivity)
                       isRunning = false
                       self.updateProgress(
                           currentFile: "",
                           processedFiles: processedFiles,
                           totalFiles: totalFiles,
                           startTime: startTime,
                           skippedFiles: skippedFiles,
                           errorFiles: errorFiles
                       )
                       throw CancellationError()
               case  MosaicError.existingVid:
                   self.logger.error("video alredy exists: \(error.localizedDescription)")
                   skippedFiles += 1
                   processedFiles += 1
                       decrementActiveTasks()
               case MosaicError.tooShort:
                   self.logger.error("skipped because too short to process video: \(error.localizedDescription)")
                       skippedFiles += 1
                       processedFiles += 1
                       decrementActiveTasks()
                   default:
                   self.logger.error("Failed to process video: \(error.localizedDescription)")
                   errorFiles += 1
                   processedFiles += 1
                       decrementActiveTasks()
                   throw error
               }
               
           }
           for activity in backgroundActivities.values {
               ProcessInfo.processInfo.endActivity(activity)
           }
           return results
       }
    
   
    
    public func generatePreviews(
        for initialFiles: [(video: URL, output: URL)],
        density: String,
        duration: Int
    ) async throws -> [(video: URL, output: URL)] {
        // Store results and initialize state variables
        isRunning = true
        isCancelled = false
        var results: [(URL, URL)] = []
        let totalFiles = initialFiles.count
        var processedFiles = 0
        var skippedFiles = 0
        var errorFiles = 0
        let startTime = CFAbsoluteTimeGetCurrent()
        let mainActivity = startBackgroundActivity(reason: "Preview Generation")
        let fileProcessingQueue = DispatchQueue(label: "com.mosaic.previewProcessing", qos: .userInitiated)
        var activeTasks = 0
        
        // Use a mutable array to track files being processed
        var filesToProcess: [(video: URL, output: URL)] = initialFiles
        let filesLock = DispatchQueue(label: "com.mosaic.filesLock")

        defer {
            endBackgroundActivity(mainActivity)
            isRunning = false
            updateProgress(
                currentFile: "Finished",
                processedFiles: processedFiles,
                totalFiles: totalFiles + filesToProcess.count,
                startTime: startTime,
                skippedFiles: skippedFiles,
                errorFiles: errorFiles
            )
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            // Continuously process files while new ones are added
            while true {
                var nextFile: (video: URL, output: URL)?
                
                // Safely extract the next file to process
                filesLock.sync {
                    if !filesToProcess.isEmpty {
                        nextFile = filesToProcess.removeFirst()
                    }
                }

                // Exit the loop if no more files to process and group is empty
                if nextFile == nil && group.isEmpty {
                    break
                }

                // Skip iteration if no files are currently available
                guard let file = nextFile else {
                    try await Task.sleep(nanoseconds: 50_000_000) // Small delay to reduce CPU usage
                    continue
                }
                while activeTasks >= self.maxTasks {
                    try await group.next()
                    
                }
                activeTasks += 1
                
                // Add a new task for the file
                group.addTask {
                    do {
                        
                        
                        // Start individual file background activity
                        let fileActivity = self.startBackgroundActivity(reason: "Processing \(file.video.lastPathComponent)")
                        defer { self.endBackgroundActivity(fileActivity) }

                        if self.isFileCancelled(file.video.lastPathComponent) {
                            skippedFiles += 1
                            activeTasks -= 1
                            return
                        }

                        // Create and set up the preview generator
                        let previewGenerator = PreviewGenerator(config: self.config)
                        self.setupPreviewGenerator(previewGenerator)
                        self.previewGenerators.append(previewGens(generator: previewGenerator, filename: file.video.path))

                        // Generate the preview
                        let preview = try await previewGenerator.generatePreview(
                            for: file.video,
                            outputDirectory: file.output,
                            density: DensityConfig.from(density),
                            previewDuration: Double(duration)
                        )

                        // Update results and progress
                        results.append((file.video, preview))
                        processedFiles += 1
                        activeTasks -= 1

                    } catch {
                        // Handle specific errors
                        switch error {
                        case MosaicError.existingVid:
                            self.logger.error("Skipped: Video already exists: \(error.localizedDescription)")
                            skippedFiles += 1
                            processedFiles += 1
                            activeTasks -= 1


                        case MosaicError.tooShort:
                            self.logger.error("Skipped: Video too short: \(error.localizedDescription)")
                            processedFiles += 1
                            activeTasks -= 1

                        case MosaicError.notAVideoFile:
                            self.logger.error("Skipped: Not a valid video file: \(error.localizedDescription)")
                            processedFiles += 1
                            activeTasks -= 1


                        default:
                            self.logger.error("Failed to process video: \(error.localizedDescription)")
                            processedFiles += 1
                            activeTasks -= 1

                        }
                    }
                    
                    // Update progress information
                    self.updateProgress(
                        currentFile: file.video.lastPathComponent,
                        processedFiles: processedFiles,
                        totalFiles: totalFiles + filesToProcess.count,
                        startTime: startTime,
                        skippedFiles: skippedFiles,
                        errorFiles: errorFiles
                    )
                }
            }

            // Wait for all tasks to finish
            try await group.waitForAll()
        }

        // Return results
        return results
    }
    
    
    // Background activity management methods
    private func startBackgroundActivity(reason: String) -> NSObjectProtocol {
        // Guard against empty reason
        guard !reason.isEmpty else {
            logger.error("Attempted to start background activity with empty reason")
            return ProcessInfo.processInfo.beginActivity(
                options: [.automaticTerminationDisabled, .suddenTerminationDisabled],
                reason: "Unknown Activity"
            )
        }
        
        // Create unique identifier for this activity
        let activityId = "\(reason)_\(UUID().uuidString)"
        
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.automaticTerminationDisabled, .suddenTerminationDisabled],
            reason: reason
        )
        
        // Store using the unique identifier
        DispatchQueue.main.async { [weak self] in
            self?.backgroundActivities[activityId] = activity
        }
        
        return activity
    }
    
    private func endBackgroundActivity(_ activity: NSObjectProtocol) {
        ProcessInfo.processInfo.endActivity(activity)
        
        // Remove from dictionary on main thread
        DispatchQueue.main.async { [weak self] in
            // Find and remove by value instead of using description
            self?.backgroundActivities = self?.backgroundActivities.filter { $0.value !== activity } ?? [:]
        }
    }
    
    
    public func cancelFile(_ filename: String) {
        CancellationManager.shared.cancelFile(filename)
        
        // Cancel active preview generators
        previewGenerators.forEach { generator in
            if generator.filename == filename {
                generator.generator.isCancelled = true
            }
        }
        
        // Remove cancelled generators
        previewGenerators.removeAll { $0.filename == filename }
        
        // Cleanup any temporary files
        cleanupTemporaryFiles(for: filename)
    }
    public func cancelGeneration() {
        CancellationManager.shared.cancelAll()
        
        // Cancel all active generators
        previewGenerators.forEach { $0.generator.isCancelled = true }
        
        // Clear all generators
        previewGenerators.removeAll()
        
        // Cleanup all temporary files
        cleanupAllTemporaryFiles()
    }


      private func cleanupTemporaryFiles(for filename: String) {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: tempURL)
    }
    
    private func cleanupAllTemporaryFiles() {
        // Implement cleanup logic for all temporary files
        let tempDirectory = FileManager.default.temporaryDirectory
        try? FileManager.default.removeItem(at: tempDirectory)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    
    
    
    
    
    
    
    public func cancelAllPreviews() {
        // Cancel all preview generators
        for generator in previewGenerators {
            generator.generator.isCancelled = true
            generator.generator.cancelCurrentPreview(for: URL(fileURLWithPath: generator.filename))
        }
        
        // Clear the generators array
        previewGenerators.removeAll()
        
        // End all background activities
        for activity in backgroundActivities.values {
            ProcessInfo.processInfo.endActivity(activity)
        }
        backgroundActivities.removeAll()
    }
    
    
    
    
    
    
    
    
    
    /*  deinit {
     // Clean up any remaining background activities
     let activities = backgroundActivities.values
     activities.forEach { activity in
     ProcessInfo.processInfo.endActivity(activity)
     }
     
     }*/
    
    
    
    
    
    
    
    
    
    
    
    
    
    // MARK: - Private Methods
    /*
    private func processVideo(
        _ video: URL,
        outputDirectory: URL,
        width: Int,
        density: String,
        format: String,
        options: GenerationOptions
    ) async throws -> (URL, URL) {
        let metadata = try await processMetadata(for: video)
        
        //  if !exportManager.FileExists(for: video, in: outputDirectory, format: format, type: metadata.type, density: density, addPath: options.addFullPath)
        
        if (options.minimumDuration > 0 && metadata.duration < Double(options.minimumDuration))
        {
            throw MosaicError.tooShort
        }
        
        let layout = try await generateLayout(
            for: metadata,
            width: width,
            density: density,
            useCustomLayout: options.useCustomLayout
        )
        
        let mosaic = try await generateMosaic(
            for: video,
            metadata: metadata,
            layout: layout
        )
        
        let output = try await exportManager.saveMosaic(
            mosaic,
            for: video,
            in: outputDirectory,
            format: format,
            type: metadata.type,
            density: density,
            addPath: options.addFullPath
        )
        
        return (video, output)
    }
    */
    private func generatePlaylists(
        for files: [(video: URL, output: URL)],
        outputDirectory: URL
    ) async throws {
        if files.isEmpty { return }
        
        let baseDirectory = files[0].output.deletingLastPathComponent()
        
        // Generate standard playlist
        _ = try await playlistGenerator.generateStandardPlaylist(
            from: baseDirectory,
            outputDirectory: baseDirectory
        )
        
        // Generate duration-based playlists
        _ = try await playlistGenerator.generateDurationBasedPlaylists(
            from: baseDirectory,
            outputDirectory: baseDirectory
        )
    }
    /*
     public func cancelFile(_ filename: String) {
     if let index = previewGenerators.firstIndex(where: { $0.filename == filename }) {
     previewGenerators[index].generator.isCancelled = true
     previewGenerators[index].generator.cancelCurrentPreview(for: URL(fileURLWithPath: filename)) // Update this method to cancel the specific preview
     }
     }*/
    
    private func isFileCancelled(_ filename: String) -> Bool {
        return cancelledFiles.contains(filename)
    }
    
    private func updateProgress(
        currentFile: String,
        processedFiles: Int,
        totalFiles: Int,
        startTime: CFAbsoluteTime,
        skippedFiles: Int?,
        errorFiles: Int?,
        fileProgress: Double? = nil
    ) {
        let elapsedTime = CFAbsoluteTimeGetCurrent() - startTime
        let progress = Double(processedFiles) / Double(totalFiles)
        var estimatedTimeRemaining = TimeInterval(0.0)
        
        if processedFiles > 0 {
            estimatedTimeRemaining = elapsedTime / progress - elapsedTime
        }
        let progressInfo: ProgressInfo
        if (!isCancelled) {
             progressInfo = ProgressInfo(
                progressType: .global,
                progress: progress,
                currentFile: currentFile,
                processedFiles: processedFiles,
                totalFiles: totalFiles,
                currentStage: "Processing Files",
                elapsedTime: elapsedTime,
                estimatedTimeRemaining: estimatedTimeRemaining,
                skippedFiles: skippedFiles ?? 0,
                errorFiles: errorFiles ?? 0,
                isRunning: isRunning,
                fileProgress: fileProgress
            )
        }
         else
        {
              progressInfo = ProgressInfo(
                progressType: .global,
                progress: progress,
                currentFile: "",
                processedFiles: processedFiles,
                totalFiles: totalFiles,
                currentStage: "Cancelled",
                elapsedTime: elapsedTime,
                estimatedTimeRemaining: estimatedTimeRemaining,
                skippedFiles: skippedFiles ?? 0,
                errorFiles: errorFiles ?? 0,
                isRunning: isRunning,
                fileProgress: fileProgress
             )
         }
        
        // Throttle updates to maximum 4 times per second
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastUpdateTime < 0.25 { return }
        lastUpdateTime = now
        
        // Ensure we're on the main thread when calling the progress handler
        DispatchQueue.main.async { [weak self] in
            self?.progressHandler?(progressInfo)
        }
    }
    
    
    
    
    private func processMetadata(for video: URL) async throws -> VideoMetadata {
        let asset = AVURLAsset(url: video)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            throw MosaicError.noVideoTrack
        }
        
        async let durationFuture = asset.load(.duration)
        async let sizeFuture = track.load(.naturalSize)
        let duration = try await durationFuture.seconds
        let size = try await sizeFuture
        let codec = try await track.mediaFormat
        let type = VideoMetadata.classifyType(duration: duration)
        
        return VideoMetadata(
            file: video,
            duration: duration,
            resolution: size,
            codec: codec,
            type: type
        )
    }
    
    private func generateLayout(
        for metadata: VideoMetadata,
        width: Int,
        density: String,
        useCustomLayout: Bool
    ) async throws -> MosaicLayout {
        let layoutProcessor = LayoutProcessor()
        let thumbnailCount = layoutProcessor.calculateThumbnailCount(
            duration: metadata.duration,
            width: width,
            density: DensityConfig.from(density)
        )
        
        return layoutProcessor.calculateLayout(
            originalAspectRatio: metadata.resolution.width / metadata.resolution.height,
            thumbnailCount: thumbnailCount,
            mosaicWidth: width,
            density: DensityConfig.from(density),
            useCustomLayout: useCustomLayout
        )
    }
    /*
    private func generateMosaic(
        for video: URL,
        metadata: VideoMetadata,
        layout: MosaicLayout
    ) async throws -> CGImage {
        let asset = AVURLAsset(url: video)
        
        let thumbnailProcessor = ThumbnailProcessor(config: config)
         let thumbnails = try await thumbnailProcessor.extractThumbnails(
         from: video,
         layout: layout,
         asset: asset,
         preview: false,
         accurate: config.accurateTimestamps
         )
        return try await mosaicGenerator.generateMosaic(
            from: thumbnails,
            layout: layout,
            metadata: metadata,
            config: config
        )
        
    }*/
    
    
    /// Options for mosaic generation process
    public struct GenerationOptions {
        /// Whether to use custom layout algorithm
        public let useCustomLayout: Bool
        
        /// Whether to generate playlists
        public let generatePlaylist: Bool
        
        /// Whether to add full path to filenames
        public let addFullPath: Bool
        
        /// Minimum duration requirement for videos
        public let minimumDuration: Int
        
        /// Whether timestamps should be accurate
        public let accurateTimestamps: Bool
        
        public let useSeparateFolder: Bool

        public let addBorder: Bool
        public let addShadow: Bool
        public let borderWidth: CGFloat
        
        /// Create generation options with defaults
        /// - Parameters:
        ///   - useCustomLayout: Whether to use custom layout
        ///   - generatePlaylist: Whether to generate playlists
        ///   - addFullPath: Whether to add full path to filenames
        ///   - minimumDuration: Minimum duration requirement
        ///   - accurateTimestamps: Whether timestamps should be accurate
        public init(
            useCustomLayout: Bool = true,
            generatePlaylist: Bool = false,
            addFullPath: Bool = false,
            minimumDuration: Int = 0,
            accurateTimestamps: Bool = false,
            useSeparateFolder: Bool = false,
            addBorder: Bool = false,
            addShadow: Bool = false,
            borderWidth: CGFloat = 0
        ) {
            self.useCustomLayout = useCustomLayout
            self.generatePlaylist = generatePlaylist
            self.addFullPath = addFullPath
            self.minimumDuration = minimumDuration
            self.accurateTimestamps = accurateTimestamps
            self.useSeparateFolder = useSeparateFolder
            self.addBorder = addBorder
            self.addShadow = addShadow
            self.borderWidth = borderWidth
        }
        
        /// Default generation options
        public static let `default` = GenerationOptions()
    }
    
    public func updateAspectRatio(_ ratio: CGFloat) {
        layoutProcessor.updateAspectRatio(ratio)
    }
}
    public extension GenerationCoordinator {
        /// Gets files created today
        /// - Parameter width: Width for the mosaic
        /// - Returns: Array of video files and their output locations
        
        /// Gets files from a specified input
        /// - Parameters:
        ///   - input: Input path
        ///   - width: Width for the mosaic
        /// - Returns: Array of video files and their output locations
        
        
        /// Creates a playlist from a directory
        /// - Parameter path: Directory path
        
        
        /// Creates a duration-based playlist
        /// - Parameter path: Directory path
        func createDurationBasedPlaylists(from path: String) async throws {
            logger.debug("Creating duration-based playlists from: \(path)")
            _ = try await playlistGenerator.generateDurationBasedPlaylists(from: URL(fileURLWithPath: path), outputDirectory: URL(fileURLWithPath: path))
        }
        
        /// Gets files for playlist generation
        /// - Parameters:
        ///   - path: Playlist path
        ///   - width: Width for thumbnails
        /// - Returns: Array of video files and their output locations
        private func getPlaylistFiles(from path: String, width: Int) async throws -> [(URL, URL)] {
            if path.lowercased().hasSuffix("m3u8") {
                // Handle M3U8 files
                return try await
                playlistGenerator.getFiles(from: path)
            } else {
                // Handle directories
                return try await playlistGenerator.getFiles(from: path)
            }
        }
    
            /// Creates duration-based playlists for videos between dates
    /// - Parameters:
    ///   - startDate: Start date
    ///   - endDate: End date
    func createDateRangeDurationPlaylists(from startDate: Date, to endDate: Date) async throws {
        logger.debug("Creating duration-based playlists for date range")
        let playlistGenerator = PlaylistGenerator()
        _ = try await playlistGenerator.generateDateRangeDurationPlaylists(
            from: startDate,
            to: endDate,
            outputDirectory: URL(fileURLWithPath: todaypl)
        )
    }
    
/// Creates a playlist for videos between dates
/// - Parameters:
///   - startDate: Start date
///   - endDate: End date
func createDateRangePlaylist(
    from startDate: Date,
    to endDate: Date,
    playlistype: Int = 0,
    outputFolder: URL? = nil
) async throws -> URL {
    logger.debug("Creating playlist for date range")
    let outputDir = outputFolder ?? URL(fileURLWithPath: todaypl)
    if playlistype == 0 {
        return try await playlistGenerator.generateDateRangePlaylist(
            from: startDate,
            to: endDate,
            outputDirectory: outputDir
        )
    } else {
        let playlists = try await playlistGenerator.generateDateRangeDurationPlaylists(
            from: startDate,
            to: endDate,
            outputDirectory: outputDir
        )
        // Return the first playlist URL or the output directory
        return playlists.first?.value ?? outputDir
    }
}
    }
    extension GenerationCoordinator {
        /// Gets files created today
        /// - Parameter width: Width for the mosaic
        /// - Returns: Array of video files and their output locations
        public func getTodayFiles(width: Int) async throws -> [(URL, URL)] {
            // Remove incorrect references
            logger.debug("Getting today's video files")
            let playlistGenerator = PlaylistGenerator()
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd"
            let dateFolderName = dateFormatter.string(from: Date())
            let outputBaseURL = URL(fileURLWithPath: "/Volumes/Ext-6TB-2/Playlist/\(dateFolderName)2/\(width)", isDirectory: true)
            return try await playlistGenerator.findTodayVideos()
                .map { videoURL in
                    let outputDir = outputBaseURL
                    return (videoURL, outputDir)
                }
        }
        
        /// Gets files from a specified input
        /// - Parameters:
        ///   - input: Input path
        ///   - width: Width for the mosaic
        /// - Returns: Array of video files and their output locations
        public func getFiles(input: String, width: Int, config: ProcessingConfiguration) async throws -> [(URL, URL)] {
            logger.debug("Getting files from input: \(input)")
            let playlistGenerator = PlaylistGenerator()
            let inputURL = URL(fileURLWithPath: input)
            var outputDir = inputURL.deletingLastPathComponent()
            
            // Get aspect ratio string
            let aspectRatioStr = layoutProcessor.mosaicAspectRatio == 1.0 ? "1x1" :
                                layoutProcessor.mosaicAspectRatio > 1.0 ? "16x9" : "9x16"
            
            if input.lowercased().hasSuffix("m3u8") {
                // Handle M3U8 playlist files
                let content = try String(contentsOf: inputURL, encoding: .utf8)
                
                let urls = content.components(separatedBy: .newlines)
                    .filter { !$0.hasPrefix("#") && !$0.isEmpty }
                    .map { URL(fileURLWithPath: $0) }
                
                return urls.map { videoURL in
                    outputDir = inputURL.deletingLastPathComponent()
                        .appendingPathComponent(ThDir, isDirectory: true)
                        .appendingPathComponent(inputURL.deletingPathExtension().lastPathComponent, isDirectory: true)
                        .appendingPathComponent("\(width)_\(aspectRatioStr)", isDirectory: true)  // Include aspect ratio
                    return (videoURL, outputDir)
                }
            } else {
                // Handle directories
                return try await playlistGenerator.findVideoFiles(in: inputURL)
                    .map { videoURL in
                        if config.saveAtRoot {
                            outputDir = inputURL
                                .appendingPathComponent(ThDir, isDirectory: true)
                                .appendingPathComponent("\(width)_\(aspectRatioStr)", isDirectory: true)  // Include aspect ratio
                        } else {
                            outputDir = videoURL.deletingLastPathComponent()
                                .appendingPathComponent(ThDir, isDirectory: true)
                                .appendingPathComponent("\(width)_\(aspectRatioStr)", isDirectory: true)  // Include aspect ratio
                        }
                        return (videoURL, outputDir)
                    }
            }
        }
        
        public func getSingleFile(input: String, width: Int) async throws -> [(URL, URL)] {
            let inputURL = URL(fileURLWithPath: input)
            let aspectRatioStr = layoutProcessor.mosaicAspectRatio == 1.0 ? "1x1" :
                                layoutProcessor.mosaicAspectRatio > 1.0 ? "16x9" : "9x16"
            
            let outputDir = inputURL.deletingLastPathComponent()
                .appendingPathComponent(ThDir, isDirectory: true)
                .appendingPathComponent("\(width)_\(aspectRatioStr)", isDirectory: true)  // Include aspect ratio
            return [(inputURL, outputDir)]
        }
        
        /// Creates a playlist from a directory
        /// - Parameter path: Directory path
        func createPlaylist(from path: String, playlistype: Int = 0, outputFolder: URL? = nil) async throws -> URL {
            logger.debug("Creating playlist from: \(path)")
            let playlistGenerator = PlaylistGenerator()
            let inputURL = URL(fileURLWithPath: path)
            let outputDir = outputFolder ?? inputURL
            return try await playlistGenerator.generateStandardPlaylist(
                from: inputURL,
                outputDirectory: outputDir
            )
        }
        func createPlaylistDiff(from path: String, outputFolder: URL? = nil) async throws -> [PlaylistGenerator.DurationCategory: URL] {
            logger.debug("Creating playlist from: \(path)")
            let playlistGenerator = PlaylistGenerator()
            let inputURL = URL(fileURLWithPath: path)
            let outputDir = outputFolder ?? inputURL
            return try await playlistGenerator.generateDurationBasedPlaylists(
                from: inputURL,
                outputDirectory: outputDir
            )
        }
        
        /// Creates a playlist from a directory
        /// - Parameter path: Directory path
        func createPlaylisttoday(outputFolder: URL? = nil) async throws -> URL {
            logger.debug("Creating playlist today")
            let playlistGenerator = PlaylistGenerator()
            let outputDir = outputFolder ?? URL(fileURLWithPath: todaypl)
            return try await playlistGenerator.generateTodayPlaylist(
                outputDirectory: outputDir
            )
        }
    }
    

