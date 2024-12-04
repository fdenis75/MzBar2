//
//  MosaicGeneratorConfig.swift
//  MZBar
//
//  Created by Francois on 02/11/2024.
//
import Foundation
import AVFoundation
public enum PreviewEngine {
        case avFoundation
        case ffmpeg
    }
/// Configuration options for the mosaic generation process
public struct MosaicGeneratorConfig {
    /// Maximum number of concurrent operations
    public var maxConcurrentOperations: Int
    
    /// Size of processing batches
    public var batchSize: Int
    
    /// Export preset for video generation
    public var videoExportPreset: String
    
    /// Compression quality for image outputs (0.0 - 1.0)
    public var compressionQuality: Float
    
    /// Whether to use accurate timestamps in thumbnails
    public var accurateTimestamps: Bool
    
    /// Whether to use debug logging
    public let debug: Bool
    
    /// Preview engine
    public let previewEngine: PreviewEngine
    
    /// Default configuration
    public static let `default` = MosaicGeneratorConfig(
        maxConcurrentOperations: 8,
        batchSize: 24,
        videoExportPreset: AVAssetExportPresetHEVC1920x1080,
        compressionQuality: 0.4,
        accurateTimestamps: false,
        debug: false,
        previewEngine: .avFoundation
    )
    
    /// Initialize with custom settings
    /// - Parameters:
    ///   - maxConcurrentOperations: Maximum number of concurrent operations
    ///   - batchSize: Size of processing batches
    ///   - videoExportPreset: Export preset for video generation
    ///   - compressionQuality: Compression quality for image outputs
    ///   - accurateTimestamps: Whether to use accurate timestamps
    ///   - debug: Whether to use debug logging
    ///   - previewEngine: Preview engine
    public init(
        maxConcurrentOperations: Int = 8,
        batchSize: Int = 24,
        videoExportPreset: String = AVAssetExportPresetHEVC1920x1080,
        compressionQuality: Float = 0.4,
        accurateTimestamps: Bool = false,
        debug: Bool = false,
        previewEngine: PreviewEngine = .avFoundation
    ) {
        self.maxConcurrentOperations = maxConcurrentOperations
        self.batchSize = batchSize
        self.videoExportPreset = videoExportPreset
        self.compressionQuality = compressionQuality
        self.accurateTimestamps = accurateTimestamps
        self.debug = debug
        self.previewEngine = previewEngine
    }
}

public enum QualityPreset: Int {
    case balanced = 0
    case performance = 1
    case quality = 2
    
    var compressionQuality: Float {
        switch self {
        case .balanced:
            return 0.4
        case .performance:
            return 0.2
        case .quality:
            return 0.8
        }
    }
}


