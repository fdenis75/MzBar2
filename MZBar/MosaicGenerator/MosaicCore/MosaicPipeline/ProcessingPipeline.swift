import Foundation
import os.log

/// Main processing pipeline for mosaic generation
public final class ProcessingPipeline {
    // MARK: - Properties
    
    private let generationCoordinator: GenerationCoordinator
    private let logger = Logger(subsystem: "com.mosaic.pipeline", category: "ProcessingPipeline")

    /// Progress handler for pipeline operations
    public var progressHandler: ((ProgressInfo) -> Void)?
    
    // MARK: - Initialization
    
    /// Initialize the processing pipeline
    /// - Parameter config: Configuration for the pipeline
    public init(config: ProcessingConfiguration) {
        self.generationCoordinator = GenerationCoordinator(config: config.generatorConfig)
        setupCoordinator()
    }
    
    // MARK: - Public Methods
    
    /// Cancels ongoing processing
    public func cancel() {
        generationCoordinator.cancelGeneration()
        CancellationManager.shared.cancelAll()
    }
    
    public func cancelFile(_ filename: String) {
        generationCoordinator.cancelFile(filename)
        CancellationManager.shared.cancelFile(filename)
    }
    
    /// Gets files from a specified path
    /// - Parameters:
    ///   - path: Input path
    ///   - width: Width for output
    /// - Returns: Array of video files and their output locations
    public func getFiles(from path: String, width: Int, config: ProcessingConfiguration) async throws -> [(URL, URL)] {
        logger.debug("Getting files from: \(path)")
        return try await generationCoordinator.getFiles(input: path, width: width, config: config)
        
        //getFiles(input: path, width: width)
    }
    public func getSingleFile(from path: String, width: Int) async throws -> [(URL, URL)] {
        logger.debug("Getting files from: \(path)")
        return try await generationCoordinator.getSingleFile(input: path, width: width)
    }
    
    /// Gets files created today
    /// - Parameter width: Width for output
    /// - Returns: Array of video files and their output locations
    public func getTodayFiles(width: Int) async throws -> [(URL, URL)] {
        logger.debug("Getting today's files")
        return try await generationCoordinator.getTodayFiles(width: width)
    }
    
    /// Creates a playlist from input
    /// - Parameter path: Input path

    public func createPlaylist(from path: String, playlistype: Int = 0, outputFolder: URL? = nil) async throws -> URL {
        if playlistype == 0 {
            return try await generationCoordinator.createPlaylist(from: path, playlistype: playlistype, outputFolder: outputFolder)
        }
        else
        {
            let folder = try await generationCoordinator.createPlaylistDiff(from: path, outputFolder: outputFolder)
            return outputFolder ?? URL(fileURLWithPath: path).deletingLastPathComponent()
        }
    }
 
    /// Creates a playlist for videos between dates
    /// - Parameters:
    ///   - startDate: Start date
    ///   - endDate: End date
    public func createDateRangePlaylist(
        from startDate: Date,
        to endDate: Date,
        playlistype: Int = 0,
        outputFolder: URL? = nil
    ) async throws -> URL {
        logger.debug("Creating playlist for date range")
        return try await generationCoordinator.createDateRangePlaylist(
            from: startDate,
            to: endDate,
            playlistype: playlistype,
            outputFolder: outputFolder
        )
    }
    
    /// Creates a playlist today
    public func createPlaylisttoday(outputFolder: URL? = nil) async throws -> URL {
        logger.debug("Creating playlist today")
        return try await generationCoordinator.createPlaylisttoday(outputFolder: outputFolder)
    }
    
    /// Generates mosaics for video files
    /// - Parameters:
    ///   - files: Input files
    ///   - config: Processing configuration
    public func generateMosaics(
        for files: [(URL, URL)],
        config: ProcessingConfiguration,
        completion: ((Result<(URL, URL), Error>) -> Void)? = nil
    ) async throws {
        logger.debug("Generating mosaics for \(files.count) files")
        try await generationCoordinator.generateMosaics(
            for: files,
            width: config.width,
            density: config.density.rawValue,
            format: config.format,
            options: .init(
                useCustomLayout: config.customLayout,
                generatePlaylist: config.summary,
                addFullPath: config.addFullPath,
                minimumDuration: config.duration,
                accurateTimestamps: config.generatorConfig.accurateTimestamps,
                useSeparateFolder: config.separateFolders,
                addBorder: config.addBorder,
                addShadow: config.addShadow,
                borderWidth: config.borderWidth
            )
        )
    }
    
    /// Generates previews for video files
    /// - Parameters:
    ///   - files: Input files
    ///   - config: Processing configuration
    public func generatePreviews(
        for files: [(URL, URL)],
        config: ProcessingConfiguration
    ) async throws {
        logger.debug("Generating previews for \(files.count) files")
        try await generationCoordinator.generatePreviews(
            for: files,
            density: config.density.rawValue,
            duration: config.previewDuration
        )
    }
    
    /// Updates the configuration for the pipeline
    /// - Parameter config: New configuration
    public func updateConfig(_ config: MosaicGeneratorConfig) {
        generationCoordinator.updateConfig(config)
    }
    public func updateCodec(_ codec: String) {
        generationCoordinator.updateCodec(codec)
    }
    
    public func updateMaxConcurrentTasks(_ maxConcurrentTasks: Int) {
        generationCoordinator.updateMaxConcurrentTasks(maxConcurrentTasks)
    }
    
    public func updateAspectRatio(_ ratio: CGFloat) {
        generationCoordinator.updateAspectRatio(ratio)
    }
    
    // MARK: - Private Methods
    
    private func setupCoordinator() {
        generationCoordinator.setProgressHandler { [weak self] info in
            self?.progressHandler?(info)
        }
    }
    
    public func reset() {
        CancellationManager.shared.reset()
    }
}

// MARK: - Error Handling
extension ProcessingPipeline {
    /// Error types specific to the processing pipeline
    public enum PipelineError: LocalizedError {
        case invalidInput(String)
        case processingFailed(String)
        case cancelled
        
        public var errorDescription: String? {
            switch self {
            case .invalidInput(let details):
                return "Invalid input: \(details)"
            case .processingFailed(let details):
                return "Processing failed: \(details)"
            case .cancelled:
                return "Processing was cancelled"
            }
        }
    }
}

// MARK: - Progress Tracking
extension ProcessingPipeline {
    /// Updates progress information
    /// - Parameter info: New progress information
    private func updateProgress(_ info: ProgressInfo) {
        progressHandler?(info)
    }
}

// MARK: - Validation
extension ProcessingPipeline {
    /// Validates input files
    /// - Parameter files: Array of input files
    /// - Throws: PipelineError if validation fails
    private func validateInput(_ files: [(URL, URL)]) throws {
        guard !files.isEmpty else {
            throw PipelineError.invalidInput("No input files provided")
        }
        
        for (video, _) in files {
            guard FileManager.default.fileExists(atPath: video.path) else {
                throw PipelineError.invalidInput("File not found: \(video.path)")
            }
        }
    }
}
