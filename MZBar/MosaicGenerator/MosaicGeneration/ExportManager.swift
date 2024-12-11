//
//  ExportManager.swift
//  MZBar
//
//  Created by Francois on 02/11/2024.
//


import Foundation
import CoreGraphics
import AVFoundation
import os.log

/// Manages the export of generated mosaics in different formats
public final class ExportManager {
    private let logger = Logger(subsystem: "com.mosaic.generation", category: "ExportManager")
    private let config: MosaicGeneratorConfig
    
    /// Initialize a new export manager
    /// - Parameter config: Configuration for export operations
    public init(config: MosaicGeneratorConfig) {
        self.config = config
    }
    
    /// Save mosaic image in specified format
    /// - Parameters:
    ///   - mosaic: Generated mosaic image
    ///   - videoFile: Original video file
    ///   - outputDirectory: Directory for output
    ///   - format: Output format
    ///   - type: Video type classification
    ///   - density: Density setting used
    ///   - addPath: Whether to include full path in filename
    /// - Returns: URL of saved file
    public func saveMosaic(
        _ mosaic: CGImage,
        for videoFile: URL,
        in outputDirectory: URL,
        format: String,
        type: String,
        density: String,
        addPath: Bool
    ) async throws -> URL {
        try await createDirectoryIfNeeded(outputDirectory)
        
        let fileName = try generateFileName(
            for: videoFile,
            in: outputDirectory,
            format: format,
            type: type,
            density: density,
            addPath: addPath
        )
        
        let outputURL = outputDirectory.appendingPathComponent(fileName)
        
        switch format.lowercased() {
        case "heic":
            try await saveAsHEIC(mosaic, to: outputURL)
        case "jpeg", "jpg":
            try await saveAsJPEG(mosaic, to: outputURL)
        case "png":
            try await saveAsPNG(mosaic, to: outputURL)
        default:
            throw MosaicError.unsupportedOutputFormat
        }
        
        logger.info("Saved mosaic: \(outputURL.path)")
        return outputURL
    }
    
    public func FileExists(for videoFile: URL,
                           in directory: URL,
                           format: String,
                           type: String,
                           density: String,
                           addPath: Bool) async throws -> Bool {
        let fileName =  generateFileName(for: videoFile, in: directory, format: format, type: type, density: density,addPath: addPath)
        let URL = directory.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: URL.path)
    }
    
    public func getFileName(
        for videoFile: URL,
        in directory: URL,
        format: String,
        type: String,
        density: String,
        addPath: Bool
    )  -> URL {
        let fileName =  generateFileName(for: videoFile, in: directory, format: format, type: type, density: density,addPath: addPath)
        let URL = directory.appendingPathComponent(fileName)
        return URL
    }
    
    public func previewExists(for preview: URL)
    async throws -> Bool {
        return FileManager.default.fileExists(atPath: preview.path)
    }
    
    // MARK: - Private Methods
    
    private func createDirectoryIfNeeded(_ directory: URL) async throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }
    
    private func generateFileName(
        for videoFile: URL,
        in directory: URL,
        format: String,
        type: String,
        density: String,
        addPath: Bool
    )  -> String {
        let fileExtension = format.lowercased()
        let baseName: String
        
        // Get initial base name
        if addPath {
            baseName = videoFile.deletingPathExtension().path
                .split(separator: "/")
                .joined(separator: "-")
        } else {
            baseName = videoFile.deletingPathExtension().lastPathComponent
        }
        
        // Calculate available space for base name
        // Format: name-density-type.ext
        let suffixLength = 1 + density.count + 1 + type.count + 1 + fileExtension.count // counts separators and extension
        let maxBaseLength = 128 - suffixLength
        
        // Truncate base name if needed
        let truncatedBase = String(baseName.prefix(maxBaseLength))
        
        return "\(truncatedBase)-\(density)-\(type).\(fileExtension)"
    }
    
    private func saveAsHEIC(_ image: CGImage, to url: URL) async throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            AVFileType.heic.rawValue as CFString,
            1,
            nil
        ) else {
            throw MosaicError.unableToSaveMosaic
        }
        
        let options: [String: Any] = [
            kCGImageDestinationLossyCompressionQuality as String: config.compressionQuality,
            kCGImageDestinationEmbedThumbnail as String: true,
            kCGImagePropertyHasAlpha as String: false
        ]
        
        CGImageDestinationAddImage(destination, image, options as CFDictionary?)
        
        if !CGImageDestinationFinalize(destination) {
            throw MosaicError.unableToSaveMosaic
        }
    }
    
    private func saveAsJPEG(_ image: CGImage, to url: URL) async throws {
        guard let imageData = image.jpegData(compressionQuality: CGFloat(config.compressionQuality)) else {
            throw MosaicError.unableToSaveMosaic
        }
        try imageData.write(to: url)
    }
    
    private func saveAsPNG(_ image: CGImage, to url: URL) async throws {
        guard let imageData = image.pngData() else {
            throw MosaicError.unableToSaveMosaic
        }
        try imageData.write(to: url)
    }
}
