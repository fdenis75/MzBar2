//
//  MosaicGeneratorConfig.swift
//  MZBar
//
//  Created by Francois on 02/11/2024.
//
import Foundation
import AVFoundation

/// Configuration options for the mosaic generation process
public struct MosaicGeneratorConfig {
    /// Maximum number of concurrent operations
    public let maxConcurrentOperations: Int
    
    /// Size of processing batches
    public let batchSize: Int
    
    /// Export preset for video generation
    public let videoExportPreset: String
    
    /// Compression quality for image outputs (0.0 - 1.0)
    public let compressionQuality: Float
    
    /// Whether to use accurate timestamps in thumbnails
    public let accurateTimestamps: Bool
    
    /// Whether to use debug logging
    public let debug: Bool
    
    /// Default configuration
    public static let `default` = MosaicGeneratorConfig(
        maxConcurrentOperations: 24,
        batchSize: 24,
        videoExportPreset: AVAssetExportPresetHEVC1920x1080,
        compressionQuality: 0.4,
        accurateTimestamps: false,
        debug: false
    )
    
    /// Initialize with custom settings
    /// - Parameters:
    ///   - maxConcurrentOperations: Maximum number of concurrent operations
    ///   - batchSize: Size of processing batches
    ///   - videoExportPreset: Export preset for video generation
    ///   - compressionQuality: Compression quality for image outputs
    ///   - accurateTimestamps: Whether to use accurate timestamps
    ///   - debug: Whether to use debug logging
    public init(
        maxConcurrentOperations: Int = 24,
        batchSize: Int = 24,
        videoExportPreset: String = AVAssetExportPresetHEVC1920x1080,
        compressionQuality: Float = 0.4,
        accurateTimestamps: Bool = false,
        debug: Bool = false
    ) {
        self.maxConcurrentOperations = maxConcurrentOperations
        self.batchSize = batchSize
        self.videoExportPreset = videoExportPreset
        self.compressionQuality = compressionQuality
        self.accurateTimestamps = accurateTimestamps
        self.debug = debug
    }
}

/*

import AVFoundation
import Foundation

/// Configuration options for the mosaic generation process.
public struct MosaicGeneratorConfig {
    /// Maximum number of concurrent operations allowed
    public let maxConcurrentOperations: Int
    
    /// Size of processing batches
    public let batchSize: Int
    
    /// Export preset for video generation
    public let videoExportPreset: String
    
    /// Compression quality for image outputs (0.0 - 1.0)
    public let compressionQuality: Float
    
    
    public let accurateTimestamps: Bool  // Add this line

    
    /// Default configuration settings
    public static let `default` = MosaicGeneratorConfig(
        maxConcurrentOperations: 24,
        batchSize: 24,
        videoExportPreset: AVAssetExportPresetHEVC1920x1080,
        compressionQuality: 0.4,
        accurateTimestamps: false        // Add this line

    )
    
    /// Creates a new configuration with custom settings.
    /// - Parameters:
    ///   - maxConcurrentOperations: Maximum number of concurrent operations
    ///   - batchSize: Size of processing batches
    ///   - videoExportPreset: Export preset for video generation
    ///   - compressionQuality: Compression quality for image outputs
    public init(
        maxConcurrentOperations: Int = 24,
        batchSize: Int = 24,
        videoExportPreset: String = AVAssetExportPresetHEVC1920x1080,
        compressionQuality: Float = 0.4,
        accurateTimestamps: Bool = false  // Add this line

    ) {
        self.maxConcurrentOperations = maxConcurrentOperations
        self.batchSize = batchSize
        self.videoExportPreset = videoExportPreset
        self.compressionQuality = compressionQuality
        self.accurateTimestamps = accurateTimestamps  // Add this li
    }
}

/// Density configuration for mosaic generation
public struct DensityConfig {
    /// Factor to adjust extraction density
    public let factor: Double
    
    /// Multiplier for number of extracts
    public let extractsMultiplier: Double
    
    /// Creates density configuration from a string identifier
    /// - Parameter density: Density identifier (XXS, XS, S, M, L, XL, XXL)
    public static func from(_ density: String) -> DensityConfig {
        switch density.lowercased() {
        case "xxl": return DensityConfig(factor: 4.0, extractsMultiplier: 0.25)
        case "xl":  return DensityConfig(factor: 3.0, extractsMultiplier: 0.5)
        case "l":   return DensityConfig(factor: 2.0, extractsMultiplier: 0.75)
        case "m":   return DensityConfig(factor: 1.0, extractsMultiplier: 1.0)
        case "s":   return DensityConfig(factor: 0.75, extractsMultiplier: 1.5)
        case "xs":  return DensityConfig(factor: 0.5, extractsMultiplier: 2.0)
        case "xxs": return DensityConfig(factor: 0.25, extractsMultiplier: 3.0)
        default:    return DensityConfig(factor: 1.0, extractsMultiplier: 1.0)
        }
    }
}
*/

