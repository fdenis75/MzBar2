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
    private let logger = Logger(subsystem: "com.mosaic.generation", category: "GenerationCoordinator")
    private let config: MosaicGeneratorConfig
    //let generator: MosaicGenerator
    
    private let mosaicGenerator: MosaicGenerator
    private let previewGenerator: PreviewGenerator
    private let playlistGenerator: PlaylistGenerator
    private let exportManager: ExportManager
    
    private var progressHandler: ((ProgressInfo) -> Void)?
    private var isRunning = false
    private var isCancelled = false
    
    /// Initialize a new generation coordinator
    /// - Parameter config: Configuration for generation processes
    public init(config: MosaicGeneratorConfig = .default) {
        self.config = config
        self.mosaicGenerator = MosaicGenerator(config: config)
        self.previewGenerator = PreviewGenerator(config: config)
        self.playlistGenerator = PlaylistGenerator()
        self.exportManager = ExportManager(config: config)
    }
    
    /// Set progress handler for generation updates
    /// - Parameter handler: Progress handler closure
    public func setProgressHandler(_ handler: @escaping (ProgressInfo) -> Void) {
        self.progressHandler = handler
    }
    
    /// Cancel ongoing generation processes
    public func cancelGeneration() {
        isCancelled = true
        isRunning = false
    }
    
    /// Generate mosaics for video files
    /// - Parameters:
    ///   - files: Array of video files and their output locations
    ///   - width: Width of generated mosaics
    ///   - density: Density configuration
    ///   - format: Output format
    ///   - options: Additional generation options
    /// - Returns: Array of processed files and their outputs
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
        
        let totalFiles = files.count
        var processedFiles = 0
        let startTime = CFAbsoluteTimeGetCurrent()
        
        defer {
            isRunning = false
        }
        
        for (video, outputDirectory) in files {
            if isCancelled { throw CancellationError() }
            
            do {
                let result = try await processVideo(
                    video,
                    outputDirectory: outputDirectory,
                    width: width,
                    density: density,
                    format: format,
                    options: options
                )
                
                results.append(result)
                processedFiles += 1
                
                updateProgress(
                    currentFile: video.lastPathComponent,
                    processedFiles: processedFiles,
                    totalFiles: totalFiles,
                    startTime: startTime
                )
            } catch {
                logger.error("Failed to process video: \(error.localizedDescription)")
                throw error
            }
        }
        
        if options.generatePlaylist {
            try await generatePlaylists(for: results, outputDirectory: files[0].output)
        }
        
        return results
    }
    
    /// Generate previews for video files
    /// - Parameters:
    ///   - files: Array of video files and their output locations
    ///   - density: Density configuration
    ///   - duration: Target duration for previews
    /// - Returns: Array of processed files and their outputs
    public func generatePreviews(
        for files: [(video: URL, output: URL)],
        density: String,
        duration: Int
    ) async throws -> [(video: URL, output: URL)] {
        isRunning = true
        isCancelled = false
        var results: [(URL, URL)] = []
        
        let totalFiles = files.count
        var processedFiles = 0
        let startTime = CFAbsoluteTimeGetCurrent()
        
        defer {
            isRunning = false
        }
        
        for (video, outputDirectory) in files {
            if isCancelled { throw CancellationError() }
            
            do {
                let preview = try await previewGenerator.generatePreview(
                    for: video,
                    outputDirectory: outputDirectory,
                    density: DensityConfig.from(density),
                    previewDuration: duration
                )
                
                results.append((video, preview))
                processedFiles += 1
                
                updateProgress(
                    currentFile: video.lastPathComponent,
                    processedFiles: processedFiles,
                    totalFiles: totalFiles,
                    startTime: startTime
                )
            } catch {
                logger.error("Failed to generate preview: \(error.localizedDescription)")
                throw error
            }
        }
        
        return results
    }
    
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
        
        if options.minimumDuration > 0 && metadata.duration < Double(options.minimumDuration) {
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
    
    private func updateProgress(
            currentFile: String,
            processedFiles: Int,
            totalFiles: Int,
            startTime: CFAbsoluteTime
        ) {
            let elapsedTime = CFAbsoluteTimeGetCurrent() - startTime
            let progress = Double(processedFiles) / Double(totalFiles)
            var estimatedTimeRemaining = TimeInterval(0.0)
            
            if processedFiles > 0 {
                estimatedTimeRemaining = elapsedTime / progress - elapsedTime
            }
            
            let progressInfo = ProgressInfo(
                progress: progress,
                currentFile: currentFile,
                processedFiles: processedFiles,
                totalFiles: totalFiles,
                currentStage: "Processing Files",
                elapsedTime: elapsedTime,
                estimatedTimeRemaining: estimatedTimeRemaining,
                skippedFiles: 0,
                errorFiles: 0,
                isRunning: isRunning
            )
            
            DispatchQueue.main.async {
                self.progressHandler?(progressInfo)
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
                metadata: metadata
            )
        }
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
        accurateTimestamps: Bool = false
    ) {
        self.useCustomLayout = useCustomLayout
        self.generatePlaylist = generatePlaylist
        self.addFullPath = addFullPath
        self.minimumDuration = minimumDuration
        self.accurateTimestamps = accurateTimestamps
    }
    
    /// Default generation options
    public static let `default` = GenerationOptions()
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
        return try await playlistGenerator.findTodayVideos()
            .map { videoURL in
                let outputDir = videoURL.deletingLastPathComponent()
                    .appendingPathComponent(ThDir, isDirectory: true).appendingPathComponent(String(width), isDirectory: true)
                return (videoURL, outputDir)
            }
    }

    /// Gets files from a specified input
    /// - Parameters:
    ///   - input: Input path
    ///   - width: Width for the mosaic
    /// - Returns: Array of video files and their output locations
    public func getFiles(input: String, width: Int) async throws -> [(URL, URL)] {
        logger.debug("Getting files from input: \(input)")
        let playlistGenerator = PlaylistGenerator()
        let inputURL = URL(fileURLWithPath: input)
        
        if input.lowercased().hasSuffix("m3u8") {
            // Handle M3U8 playlist files
            let content = try String(contentsOf: inputURL, encoding: .utf8)
            let urls = content.components(separatedBy: .newlines)
                .filter { !$0.hasPrefix("#") && !$0.isEmpty }
                .map { URL(fileURLWithPath: $0) }
            
            return urls.map { videoURL in
                let outputDir = videoURL.deletingLastPathComponent()
                    .appendingPathComponent(ThDir, isDirectory: true).appendingPathComponent(String(width), isDirectory: true)
                return (videoURL, outputDir)
            }
        } else {
            // Handle directories
            return try await playlistGenerator.findVideoFiles(in: inputURL)
                .map { videoURL in
                    let outputDir = videoURL.deletingLastPathComponent()
                        .appendingPathComponent(ThDir, isDirectory: true).appendingPathComponent(String(width), isDirectory: true)
                    return (videoURL, outputDir)
                }
        }
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
}

