import Foundation
import os.log

/// Main processing pipeline for mosaic generation
public final class ProcessingPipeline {
    // MARK: - Properties
    
    private let coordinator: GenerationCoordinator
    private let logger = Logger(subsystem: "com.mosaic.pipeline", category: "ProcessingPipeline")
    
    /// Progress handler for pipeline operations
    public var progressHandler: ((ProgressInfo) -> Void)?
    
    // MARK: - Initialization
    
    /// Initialize the processing pipeline
    /// - Parameter config: Configuration for the pipeline
    public init(config: ProcessingConfiguration) {
        self.coordinator = GenerationCoordinator(config: config.generatorConfig)
        setupCoordinator()
    }
    
    // MARK: - Public Methods
    
    /// Cancels ongoing processing
    public func cancel() {
        coordinator.cancelGeneration()
    }
    
    public func cancelFile(_ filename: String) {
    coordinator.cancelFile(filename)
}
    /// Gets files from a specified path
    /// - Parameters:
    ///   - path: Input path
    ///   - width: Width for output
    /// - Returns: Array of video files and their output locations
    public func getFiles(from path: String, width: Int, config: ProcessingConfiguration) async throws -> [(URL, URL)] {
        logger.debug("Getting files from: \(path)")
        return try await coordinator.getFiles(input: path, width: width, config: config)
        
        //getFiles(input: path, width: width)
    }
    public func getSingleFile(from path: String, width: Int) async throws -> [(URL, URL)] {
        logger.debug("Getting files from: \(path)")
        return try await coordinator.getSingleFile(input: path, width: width)
    }
    
    /// Gets files created today
    /// - Parameter width: Width for output
    /// - Returns: Array of video files and their output locations
    public func getTodayFiles(width: Int) async throws -> [(URL, URL)] {
        logger.debug("Getting today's files")
        return try await coordinator.getTodayFiles(width: width)
    }
    
    /// Creates a playlist from input
    /// - Parameter path: Input path
    public func createPlaylist(from path: String) async throws {
        logger.debug("Creating playlist from: \(path)")
        try await coordinator.createPlaylist(from: path)
    }
    /// Creates a playlist from input
    /// - Parameter path: Input path
    public func createPlaylisttoday() async throws {
        logger.debug("Creating playlist today from: ")
        try await coordinator.createPlaylisttoday()
    }
    
    /// Generates mosaics for video files
    /// - Parameters:
    ///   - files: Input files
    ///   - config: Processing configuration
    public func generateMosaics(
        for files: [(video: URL, output: URL)],
        config: ProcessingConfiguration
    ) async throws {
        logger.debug("Generating mosaics for \(files.count) files")
        try await coordinator.generateMosaics(
            for: files,
            width: config.width,
            density: config.density.rawValue, // Get the string value
            format: config.format,
            options: .init(
                useCustomLayout: config.customLayout,
                generatePlaylist: config.summary,
                addFullPath: config.addFullPath,
                minimumDuration: config.duration,
                accurateTimestamps: config.generatorConfig.accurateTimestamps,
                useSeparateFolder: config.separateFolders
            )
        )
    }
    
    /// Generates previews for video files
    /// - Parameters:
    ///   - files: Input files
    ///   - config: Processing configuration
    public func generatePreviews(
        for files: [(video: URL, output: URL)],
        config: ProcessingConfiguration
    ) async throws {
        logger.debug("Generating previews for \(files.count) files")
        try await coordinator.generatePreviews(
            for: files,
            density: config.density.rawValue,
            duration: config.previewDuration
        )
    }
    
    /// Updates the configuration for the pipeline
    /// - Parameter config: New configuration
    public func updateConfig(_ config: MosaicGeneratorConfig) {
        coordinator.updateConfig(config)
    }
    
    public func updateMaxConcurrentTasks(_ maxConcurrentTasks: Int) {
        coordinator.updateMaxConcurrentTasks(maxConcurrentTasks)
    }
    // MARK: - Private Methods
    
    private func setupCoordinator() {
        coordinator.setProgressHandler { [weak self] info in
            self?.progressHandler?(info)
        }
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
