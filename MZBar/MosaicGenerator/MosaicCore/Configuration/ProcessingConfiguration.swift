//
//  ProcessingConfiguration.swift
//  MZBar
//
//  Created by Francois on 02/11/2024.
//
import Foundation

/// High-level configuration for the mosaic processing pipeline
public struct ProcessingConfiguration {
    // MARK: - Basic Settings
    
    /// Width of the generated mosaic
    public let width: Int
    
    /// Density of frame extraction
    public let density: DensityConfig

    /// Output format (e.g., "heic", "jpeg")
    public let format: String
    
    /// Minimum video duration requirement
    public let duration: Int
    
    /// Duration for preview generation
    public let previewDuration: Int
    
    // MARK: - Processing Options
    
    /// Whether to overwrite existing files
    public let overwrite: Bool
    
    /// Whether to save at root directory
    public let saveAtRoot: Bool
    
    /// Whether to separate files into folders
    public let separateFolders: Bool
    
    /// Whether to generate summary
    public let summary: Bool
    
    /// Whether to use custom layout
    public let customLayout: Bool
    
    /// Whether to add full path to filenames
    public let addFullPath: Bool
    
    /// Low-level generator configuration
    public let generatorConfig: MosaicGeneratorConfig
    
    /// Default configuration
    public static let `default` = ProcessingConfiguration(
        width: 5120,
        density: "M",
        format: "heic",
        duration: 0,
        previewDuration: 60,
        overwrite: false,
        saveAtRoot: false,
        separateFolders: true,
        summary: false,
        customLayout: true,
        addFullPath: false,
        generatorConfig: .default
    )
    
    /// Initialize with custom settings
    /// - Parameters:
    ///   - width: Width of the generated mosaic
    ///   - density: Density of frame extraction
    ///   - format: Output format
    ///   - duration: Minimum video duration requirement
    ///   - previewDuration: Duration for preview generation
    ///   - overwrite: Whether to overwrite existing files
    ///   - saveAtRoot: Whether to save at root directory
    ///   - separateFolders: Whether to separate files into folders
    ///   - summary: Whether to generate summary
    ///   - customLayout: Whether to use custom layout
    ///   - addFullPath: Whether to add full path to filenames
    ///   - generatorConfig: Low-level generator configuration
    public init(
        width: Int = 5120,
        density: String = "M",
        format: String = "heic",
        duration: Int = 0,
        previewDuration: Int = 60,
        overwrite: Bool = false,
        saveAtRoot: Bool = false,
        separateFolders: Bool = true,
        summary: Bool = false,
        customLayout: Bool = true,
        addFullPath: Bool = false,
        generatorConfig: MosaicGeneratorConfig = .default
    ) {
        self.width = width
        self.density = DensityConfig.from(rawValue: density)
        self.format = format
        self.duration = duration
        self.previewDuration = previewDuration
        self.overwrite = overwrite
        self.saveAtRoot = saveAtRoot
        self.separateFolders = separateFolders
        self.summary = summary
        self.customLayout = customLayout
        self.addFullPath = addFullPath
        self.generatorConfig = generatorConfig
    }
}

// MARK: - Validation Extension

extension ProcessingConfiguration {
    /// Validates the configuration
    /// - Throws: ConfigurationError if validation fails
    public func validate() throws {
        // Validate width
        guard width > 0 else {
            throw ConfigurationError.invalidWidth
        }
        
        // Validate format
        let validFormats = ["heic", "jpeg"]
        guard validFormats.contains(format.lowercased()) else {
            throw ConfigurationError.invalidFormat
        }
        
        // Validate durations
        guard duration >= 0 else {
            throw ConfigurationError.invalidDuration
        }
        
        guard previewDuration > 0 else {
            throw ConfigurationError.invalidPreviewDuration
        }
        
        // Validate compression quality
        guard generatorConfig.compressionQuality >= 0 && generatorConfig.compressionQuality <= 1 else {
            throw ConfigurationError.invalidCompressionQuality
        }
        
        // Validate batch size
        guard generatorConfig.batchSize > 0 else {
            throw ConfigurationError.invalidBatchSize
        }
        
        // Validate concurrent operations
        guard generatorConfig.maxConcurrentOperations > 0 else {
            throw ConfigurationError.invalidConcurrentOperations
        }
    }
}

// MARK: - Configuration Errors
public enum ConfigurationError: LocalizedError {
    case invalidWidth
    case invalidFormat
    case invalidDuration
    case invalidPreviewDuration
    case invalidCompressionQuality
    case invalidBatchSize
    case invalidConcurrentOperations
    
    public var errorDescription: String? {
        switch self {
        case .invalidWidth:
            return "Width must be greater than 0"
        case .invalidFormat:
            return "Invalid output format. Supported formats: heic, jpeg"
        case .invalidDuration:
            return "Duration must be non-negative"
        case .invalidPreviewDuration:
            return "Preview duration must be greater than 0"
        case .invalidCompressionQuality:
            return "Compression quality must be between 0 and 1"
        case .invalidBatchSize:
            return "Batch size must be greater than 0"
        case .invalidConcurrentOperations:
            return "Maximum concurrent operations must be greater than 0"
        }
    }
}


// Old
/*
import Foundation

public struct ProcessingConfiguration {
    // Basic settings
    public let width: Int
    public let density: String
    public let format: String
    public let duration: Int
    
    // Preview settings
    public let previewDuration: Int
    
    // Processing options
    public let overwrite: Bool
    public let saveAtRoot: Bool
    public let separateFolders: Bool
    public let summary: Bool
    public let customLayout: Bool
    public let addFullPath: Bool
    
    // Generator config
    public let generatorConfig: MosaicGeneratorConfig
    
    public static let `default` = ProcessingConfiguration(
        width: 5120,
        density: "M",
        format: "heic",
        duration: 0,
        previewDuration: 60,
        overwrite: false,
        saveAtRoot: false,
        separateFolders: true,
        summary: false,
        customLayout: true,
        addFullPath: false,
        generatorConfig: .default
    )
    
    public init(
        width: Int = 5120,
        density: String = "M",
        format: String = "heic",
        duration: Int = 0,
        previewDuration: Int = 60,
        overwrite: Bool = false,
        saveAtRoot: Bool = false,
        separateFolders: Bool = true,
        summary: Bool = false,
        customLayout: Bool = true,
        addFullPath: Bool = false,
        generatorConfig: MosaicGeneratorConfig = .default
    ) {
        self.width = width
        self.density = density
        self.format = format
        self.duration = duration
        self.previewDuration = previewDuration
        self.overwrite = overwrite
        self.saveAtRoot = saveAtRoot
        self.separateFolders = separateFolders
        self.summary = summary
        self.customLayout = customLayout
        self.addFullPath = addFullPath
        self.generatorConfig = generatorConfig
    }
}
*/
