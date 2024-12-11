//
//  VideoProcessor.swift
//  MZBar
//
//  Created by Francois on 02/11/2024.
//


import Foundation
import AVFoundation
import CoreGraphics
import os.log

/// Handles video processing operations including metadata extraction and format validation
public final class VideoProcessor: VideoProcessing {
    private let logger = Logger(subsystem: "com.mosaic.processing", category: "VideoProcessor")
    private let signposter = OSSignposter(logHandle: .processing)

    /// Initialize a new video processor
    public init() {}
    
    /// Process video to extract metadata and validate format
    /// - Parameters:
    ///   - file: URL of the video file
    ///   - asset: Pre-loaded asset for the video
    /// - Returns: Metadata for the video
    public func processVideo(file: URL, asset: AVAsset) async throws -> VideoMetadata {
        logger.info("Processing video: \(file.lastPathComponent)")
        let state = signposter.beginInterval("get metadata for Video")
        defer{
            signposter.endInterval("get metadata for Video", state)
        }
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            logger.error("No video track found: \(file.lastPathComponent)")
            throw MosaicError.noVideoTrack
        }
        
        async let durationFuture = asset.load(.duration)
        async let sizeFuture = track.load(.naturalSize)
        
        let duration = try await durationFuture.seconds
        let size = try await sizeFuture
        let codec = try await track.mediaFormat
        let type = VideoMetadata.classifyType(duration: duration)
        
        logger.info("""
            Video processed: \
            duration=\(String(describing: duration)), \
            size=\(String(describing: size)), \
            codec=\(String(describing: codec)), \
            type=\(String(describing: type))
            """)

        
        return VideoMetadata(
            file: file,
            duration: duration,
            resolution: size,
            codec: codec,
            type: type
        )
    }
    
    /// Validates if a file is a supported video format
    /// - Parameter url: URL of the file to check
    /// - Returns: Boolean indicating if the file is a supported video
    public func isVideoFile(_ url: URL) -> Bool {
        let videoExtensions = ["mp4", "mov", "avi", "mkv", "m4v", "webm", "ts"]
        return videoExtensions.contains(url.pathExtension.lowercased())
    }
}

extension AVAssetTrack {
    var mediaFormat: String {
        get async throws {
            var format = ""
            let descriptions = try await load(.formatDescriptions)
            for (index, formatDesc) in descriptions.enumerated() {
                let type = CMFormatDescriptionGetMediaType(formatDesc).toString()
                let subType = CMFormatDescriptionGetMediaSubType(formatDesc).toString()
                format += "\(type)/\(subType)"
                if index < descriptions.count - 1 {
                    format += ","
                }
            }
            return format
        }
    }
}
