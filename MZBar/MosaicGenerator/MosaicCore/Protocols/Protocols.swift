//
//  Protocols.swift
//  MZBar
//
//  Created by Francois on 02/11/2024.
//


import Foundation
import AVFoundation
import CoreGraphics

/// Protocol for video processing operations
public protocol VideoProcessing {
    /// Extracts metadata from a video file
    /// - Parameters:
    ///   - file: URL of the video file
    ///   - asset: Pre-loaded asset for the video
    /// - Returns: Metadata for the video
    func processVideo(file: URL, asset: AVAsset) async throws -> VideoMetadata
}

/// Protocol for thumbnail extraction operations
public protocol ThumbnailExtraction {
    /// Extracts thumbnails from a video with timestamps
    /// - Parameters:
    ///   - file: Video file URL
    ///   - layout: Layout information for the mosaic
    ///   - asset: Video asset
    ///   - preview: Whether this is for preview generation
    ///   - accurate: Whether to use accurate timestamp extraction
    /// - Returns: Array of thumbnails with timestamps
    func extractThumbnails(
        from file: URL,
        layout: MosaicLayout,
        asset: AVAsset,
        preview: Bool,
        accurate: Bool
    ) async throws -> [(image: CGImage, timestamp: String)]
}
/*
/// Protocol for mosaic generation operations
public protocol MosaicGeneration {
    /// Generates a mosaic from thumbnails
    /// - Parameters:
    ///   - thumbnails: Array of thumbnails with timestamps
    ///   - layout: Layout information
    ///   - metadata: Video metadata
    /// - Returns: Generated mosaic image
    func generateMosaic(
        from thumbnails: [(image: CGImage, timestamp: String)],
        layout: MosaicLayout,
        metadata: VideoMetadata
    ) async throws -> CGImage
}*/

/// Protocol for file management operations
public protocol FileManagement {
    /// Discovers video files in a location
    /// - Parameters:
    ///   - input: Input path
    ///   - width: Width for output organization
    /// - Returns: Array of video files and their output locations
    func discoverFiles(input: String, width: Int) async throws -> [(URL, URL)]
    
    /// Saves a mosaic image
    /// - Parameters:
    ///   - mosaic: Mosaic image
    ///   - videoFile: Original video file
    ///   - outputDirectory: Output directory
    ///   - format: Output format
    ///   - config: Generation configuration
    /// - Returns: URL of saved file
    func saveMosaic(
        _ mosaic: CGImage,
        for videoFile: URL,
        in outputDirectory: URL,
        format: String,
        config: MosaicGeneratorConfig
    ) async throws -> URL
}
/// Protocol defining processing pipeline configuration
public protocol ProcessingConfigurable {
    var config: ProcessingConfiguration { get }
}

/// Protocol defining progress reporting
public protocol ProgressReporting {
    var progressHandler: ((ProgressInfo) -> Void)? { get set }
    func updateProgress(_ info: ProgressInfo)
}

/// Protocol defining file handling operations
public protocol FileHandling {
    func getFiles(from path: String, width: Int) async throws -> [(URL, URL)]
    func getTodayFiles(width: Int) async throws -> [(URL, URL)]
    func createPlaylist(from path: String) async throws
}

/// Protocol defining mosaic generation operations
public protocol MosaicGeneration {
    func generateMosaics(
        for files: [(video: URL, output: URL)],
        config: ProcessingConfiguration
    ) async throws
    
    func generatePreviews(
        for files: [(video: URL, output: URL)],
        config: ProcessingConfiguration
    ) async throws
}
