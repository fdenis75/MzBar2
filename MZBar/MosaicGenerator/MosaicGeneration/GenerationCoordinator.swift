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
    
    private var cancelledFiles: Set<String> = []
    struct ActiveFile {
        let filename: String
        var isCancelled: Bool = false
    }
    private var activeFiles: [ActiveFile] = []
    
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
    
    
    public func updateMaxConcurrentTasks(_ maxConcurrentTasks: Int) {
        self.maxTasks = maxConcurrentTasks
    }
    /// Cancel ongoing generation processes
    public func cancelGeneration() {
        isCancelled = true
        isRunning = false
        cancelAllPreviews()
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
    ) async throws -> [(video: URL, output: URL)] {
        isRunning = true
        isCancelled = false
        var results: [(URL, URL)] = []
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
                    activemozTasks += 1
                    group.addTask {
                        do {
                            let fileActivity = self.startBackgroundActivity(
                                reason: "Processing \(video.lastPathComponent)"
                            )
                            print("activemozTasks: \(activemozTasks)")
                            defer {
                                // self.activeFiles.removeAll(where: { $0.filename == video.path() })
                                self.endBackgroundActivity(fileActivity) }
                            
                            if self.isFileCancelled(video.lastPathComponent) {
                                throw CancellationError()
                            }
                            let mosaicGenerator = MosaicGenerator(config: self.config)
                            self.setupmosaicGenerator(mosaicGenerator)
                            self.mosaicGenerators.append(mosaicGens(generator: mosaicGenerator, filename: video.path()))
                            let config = ProcessingConfiguration(width: width, density: density, format: format, previewDuration: options.minimumDuration,separateFolders: options.useSeparateFolder,addFullPath: options.addFullPath)
                            let result = try await mosaicGenerator.processSingleFile(video: video, output: outputDirectory, config: config)
                            
                            results.append(result)
                            processedFiles += 1
                            activemozTasks -= 1
                        } catch {
                            switch error {

                        case  MosaicError.existingVid:
                            self.logger.error("video alredy exists: \(error.localizedDescription)")
                            skippedFiles += 1
                            processedFiles += 1
                            activemozTasks -= 1
                            
                        case MosaicError.tooShort:
                            self.logger.error("skipped because too short to process video: \(error.localizedDescription)")
                            skippedFiles += 1
                            processedFiles += 1
                            activemozTasks -= 1
                        default:
                            self.logger.error("Failed to process video: \(error.localizedDescription)")
                            errorFiles += 1
                            processedFiles += 1
                            activemozTasks -= 1
                            
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
                    activemozTasks -= 1
           
            case MosaicError.tooShort:
                self.logger.error("skipped because too short to process video: \(error.localizedDescription)")
                    skippedFiles += 1
                    processedFiles += 1
                    activemozTasks -= 1
            default:
                self.logger.error("Failed to process video: \(error.localizedDescription)")
                errorFiles += 1
                processedFiles += 1
                    activemozTasks -= 1
                throw error
            }
            
        }
        for activity in backgroundActivities.values {
            ProcessInfo.processInfo.endActivity(activity)
        }
        return results
    }
    
    public func updateConfig(_ config: MosaicGeneratorConfig) {
        self.config = config
        
    }
    
    public func generatePreviews(
        for files: [(video: URL, output: URL)],
        density: String,
        duration: Int
    ) async throws -> [(video: URL, output: URL)] {
        
        isRunning = true
        isCancelled = false
        var results: [(URL, URL)] = []
        var activeTasks = 0
        //var maxTasks = self.config.maxConcurrentOperations
        let totalFiles = files.count
        var processedFiles = 0
        var skippedFiles = 0
        var errorFiles = 0
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Start background activity for the entire preview generation process
        let mainActivity = startBackgroundActivity(reason: "Preview Generation")
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
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (video, outputDirectory) in files {
                
                if isCancelled { throw CancellationError() }
                if isFileCancelled(video.lastPathComponent) {
                    skippedFiles += 1
                    continue
                }
                while activeTasks >= maxTasks {
                    try await group.next()
                    
                }
                
                activeTasks += 1
                
                group.addTask {
                    do {
                        // Start individual file background activity
                        let fileActivity = self.startBackgroundActivity(
                            reason: "Processing \(video.lastPathComponent)"
                        )
                        defer {
                            // self.activeFiles.removeAll(where: { $0.filename == video.path() })
                            self.endBackgroundActivity(fileActivity) }
                        
                        if self.isFileCancelled(video.lastPathComponent) {
                            throw CancellationError()
                        }
                        
                        //let activeFile = ActiveFile(filename: video.path())
                        //self.activeFiles.append(activeFile)
                        let previewGenerator = PreviewGenerator(config: self.config)
                        self.setupPreviewGenerator(previewGenerator)
                        self.previewGenerators.append(previewGens(generator: previewGenerator, filename: video.path))
                        
                        let preview = try await previewGenerator.generatePreview(
                            for: video,
                            outputDirectory: outputDirectory,
                            density: DensityConfig.from(density),
                            previewDuration: duration
                        )
                        
                        results.append((video, preview))
                        processedFiles += 1
                        activeTasks -= 1
                        
                    } catch {
                        switch error {
                        case  MosaicError.existingVid:
                            self.logger.error("video alredy exists: \(error.localizedDescription)")
                            skippedFiles += 1
                            processedFiles += 1
                            activeTasks -= 1
                       
                        case MosaicError.tooShort:
                            self.logger.error("skipped because too short to process video: \(error.localizedDescription)")
                                skippedFiles += 1
                                processedFiles += 1
                                activeTasks -= 1
                        default:
                            self.logger.error("Failed to process video: \(error.localizedDescription)")
                            errorFiles += 1
                            processedFiles += 1
                            activeTasks -= 1
                            throw error
                        }
                    }
                    
                    self.updateProgress(
                        currentFile: "",
                        processedFiles: processedFiles,
                        totalFiles: totalFiles,
                        startTime: startTime,
                        skippedFiles: skippedFiles,
                        errorFiles: errorFiles
                    )
                }
                
            }
            try await group.waitForAll()
            
        }
        for activity in backgroundActivities.values {
            ProcessInfo.processInfo.endActivity(activity)
        }
        
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
        guard !filename.isEmpty else { return }
        
        if let index = previewGenerators.firstIndex(where: { $0.filename == filename }) {
            // Cancel the specific preview generator
            previewGenerators[index].generator.isCancelled = true
            previewGenerators[index].generator.cancelCurrentPreview(for: URL(fileURLWithPath: filename))
            
            // Remove from active generators
            previewGenerators.remove(at: index)
            
            // End background activity immediately
            if let activityKey = backgroundActivities.first(where: { $0.key.starts(with: filename)})?.key,
               let activity = backgroundActivities[activityKey] {
                endBackgroundActivity(activity)
            }
        }
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
    
    private func generateMosaic(
        for video: URL,
        metadata: VideoMetadata,
        layout: MosaicLayout
    ) async throws -> CGImage {
        let asset = AVURLAsset(url: video)
        
        let thumbnailProcessor = ThumbnailProcessor(config: config)
        /*let thumbnails = try await thumbnailProcessor.extractThumbnails(
         from: video,
         layout: layout,
         asset: asset,
         preview: false,
         accurate: config.accurateTimestamps
         )*/
        let thumbnails = try await thumbnailProcessor.processVideo(for: video, layout: layout, asset: asset, preview: false, accurate: config.accurateTimestamps)
        return try await mosaicGenerator.generateMosaic(
            from: thumbnails,
            layout: layout,
            metadata: metadata
        )
    }
    
    
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
            useSeparateFolder: Bool = false
        ) {
            self.useCustomLayout = useCustomLayout
            self.generatePlaylist = generatePlaylist
            self.addFullPath = addFullPath
            self.minimumDuration = minimumDuration
            self.accurateTimestamps = accurateTimestamps
            self.useSeparateFolder = useSeparateFolder
        }
        
        /// Default generation options
        public static let `default` = GenerationOptions()
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
            try await playlistGenerator.generateDurationBasedPlaylists(from: URL(fileURLWithPath: path), outputDirectory: URL(fileURLWithPath: path))
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
            if input.lowercased().hasSuffix("m3u8") {
                // Handle M3U8 playlist files
                let content = try String(contentsOf: inputURL, encoding: .utf8)
                
                
                let urls = content.components(separatedBy: .newlines)
                    .filter { !$0.hasPrefix("#") && !$0.isEmpty }
                    .map { URL(fileURLWithPath: $0) }
                
                return urls.map { videoURL in
                    outputDir = inputURL.deletingLastPathComponent()
                        .appendingPathComponent(ThDir, isDirectory: true).appendingPathComponent(String(width), isDirectory: true)
                    return (videoURL, outputDir)
                }
            } else {
                // Handle directories
                return try await playlistGenerator.findVideoFiles(in: inputURL)
                    .map { videoURL in
                        if config.saveAtRoot {
                            outputDir = inputURL
                                .appendingPathComponent(ThDir, isDirectory: true).appendingPathComponent(String(width), isDirectory: true)
                        } else {
                            outputDir = videoURL.deletingLastPathComponent()
                                .appendingPathComponent(ThDir, isDirectory: true).appendingPathComponent(String(width), isDirectory: true)
                        }
                        return (videoURL, outputDir)
                    }
            }
        }
        
        public func getSingleFile(input: String, width: Int) async throws -> [(URL, URL)] {
            let inputURL = URL(fileURLWithPath: input)
            let outputDir = inputURL.deletingLastPathComponent().appendingPathComponent(ThDir, isDirectory: true).appendingPathComponent(String(width), isDirectory: true)
            return [(inputURL, outputDir)]
        }
        
        /// Creates a playlist from a directory
        /// - Parameter path: Directory path
        func createPlaylist(from path: String) async throws {
            logger.debug("Creating playlist from: \(path)")
            let playlistGenerator = PlaylistGenerator()
            let inputURL = URL(fileURLWithPath: path)
            _ = try await playlistGenerator.generateStandardPlaylist(
                from: inputURL,
                outputDirectory: inputURL
            )
        }
        /// Creates a playlist from a directory
        /// - Parameter path: Directory path
        func createPlaylisttoday() async throws {
            logger.debug("Creating playlist toda)")
            let playlistGenerator = PlaylistGenerator()
            
            _ = try await playlistGenerator.generateTodayPlaylist(
                outputDirectory: URL(fileURLWithPath: todaypl)
            )
        }
    }
    
