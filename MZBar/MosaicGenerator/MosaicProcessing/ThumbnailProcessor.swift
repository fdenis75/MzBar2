//
//  ThumbnailProcessor.swift
//  MZBar
//
//  Created by Francois on 02/11/2024.
//


import Foundation
import AVFoundation
import CoreGraphics
import os.log

/// Handles thumbnail extraction and timestamp generation
public final class ThumbnailProcessor: ThumbnailExtraction {
    private let logger = Logger(subsystem: "com.mosaic.processing", category: "ThumbnailProcessor")
    private let config: MosaicGeneratorConfig
    
    /// Initialize a new thumbnail processor
    /// - Parameter config: Configuration for thumbnail processing
    public init(config: MosaicGeneratorConfig) {
        self.config = config
    }
    
    /// Extract thumbnails from video with timestamps
    /// - Parameters:
    ///   - file: Video file URL
    ///   - layout: Layout information
    ///   - asset: Video asset
    ///   - preview: Whether generating previews
    ///   - accurate: Whether to use accurate timestamp extraction
    /// - Returns: Array of thumbnails with timestamps
    public func extractThumbnails(
        from file: URL,
        layout: MosaicLayout,
        asset: AVAsset,
        preview: Bool,
        accurate: Bool
    ) async throws -> [(image: CGImage, timestamp: String)] {
        logger.debug("Starting thumbnail extraction: \(file.lastPathComponent)")
        
        let duration = try await asset.load(.duration).seconds
        let generator = configureGenerator(for: asset, accurate: accurate, preview: preview, layout: layout)
        
        let times = try await calculateExtractionTimes(
            duration: duration,
            count: layout.thumbCount
        )
        
        var thumbnails: [(Int, CGImage, String)] = []
        var failedCount = 0
        
        for await result in generator.images(for: times) {
            switch result {
            case .success(requestedTime: _, image: let image, actualTime: let actual):
                thumbnails.append((thumbnails.count, image, formatTimestamp(seconds: actual.seconds)))
            case .failure(requestedTime: _, error: let error):
                logger.error("Thumbnail extraction failed: \(error.localizedDescription)")
                failedCount += 1
            }
        }
        
        if failedCount > 0 {
            logger.warning("Partial extraction failure: \(failedCount) failed")
            if thumbnails.isEmpty {
                throw ThumbnailExtractionError.partialFailure(
                    successfulCount: thumbnails.count,
                    failedCount: failedCount
                )
            }
        }
        
        return thumbnails
            .sorted { $0.0 < $1.0 }
            .map { ($0.1, $0.2) }
    }
    
    // MARK: - Private Methods
    
    private func configureGenerator(
        for asset: AVAsset,
        accurate: Bool,
        preview: Bool,
        layout: MosaicLayout
    ) -> AVAssetImageGenerator {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        
        if accurate {
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
        } else {
            generator.requestedTimeToleranceBefore = CMTime(seconds: 2, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 2, preferredTimescale: 600)
        }
        
        if !preview {
            generator.maximumSize = CGSize(
                width: layout.thumbnailSize.width * 2,
                height: layout.thumbnailSize.width * 2
            )
        }
        
        return generator
    }
    
    private func calculateExtractionTimes(duration: Double, count: Int) -> [CMTime] {
        let startPoint = duration * 0.05
        let endPoint = duration * 0.95
        let effectiveDuration = endPoint - startPoint
        
        let firstThirdCount = Int(Double(count) * 0.2)
        let middleCount = Int(Double(count) * 0.6)
        let lastThirdCount = count - firstThirdCount - middleCount
        
        let firstThirdEnd = startPoint + effectiveDuration * 0.33
        let lastThirdStart = startPoint + effectiveDuration * 0.67
        
        let firstThirdStep = (firstThirdEnd - startPoint) / Double(firstThirdCount)
        let middleStep = (lastThirdStart - firstThirdEnd) / Double(middleCount)
        let lastThirdStep = (endPoint - lastThirdStart) / Double(lastThirdCount)
        
        let firstThirdTimes = (0..<firstThirdCount).map { index in
            CMTime(seconds: startPoint + Double(index) * firstThirdStep, preferredTimescale: 600)
        }
        
        let middleTimes = (0..<middleCount).map { index in
            CMTime(seconds: firstThirdEnd + Double(index) * middleStep, preferredTimescale: 600)
        }
        
        let lastThirdTimes = (0..<lastThirdCount).map { index in
            CMTime(seconds: lastThirdStart + Double(index) * lastThirdStep, preferredTimescale: 600)
        }
        
        return firstThirdTimes + middleTimes + lastThirdTimes
    }
    
    private func formatTimestamp(seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let seconds = Int(seconds) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}