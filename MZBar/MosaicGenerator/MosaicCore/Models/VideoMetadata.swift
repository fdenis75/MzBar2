//
//  VideoMetadata.swift
//  MZBar
//
//  Created by Francois on 02/11/2024.
//
import Foundation
import CoreGraphics
import AVFoundation

/// Represents metadata for a video file
public struct VideoMetadata {
    /// The URL of the video file
    public let file: URL
    
    /// Duration of the video in seconds
    public let duration: Double
    
    /// Resolution of the video
    public let resolution: CGSize
    
    /// Codec used for the video
    public let codec: String
    
    /// Type classification of the video (XS, S, M, L, XL)
    public let type: String

    /// Creation date of the video
    public let creationDate: String?
    
    /// Initialize new video metadata
    /// - Parameters:
    ///   - file: Video file URL
    ///   - duration: Duration in seconds
    ///   - resolution: Video resolution
    ///   - codec: Video codec
    ///   - type: Video type classification
    public init(
        file: URL,
        duration: Double,
        resolution: CGSize,
        codec: String,
        type: String,
        creationDate: String?
    ) {
        self.file = file
        self.duration = duration
        self.resolution = resolution
        self.codec = codec
        self.type = type
        self.creationDate = creationDate
    }
}

// MARK: - Type Classification
extension VideoMetadata {
    /// Classifies video type based on duration
    /// - Parameter duration: Video duration in seconds
    /// - Returns: Type classification string
    public static func classifyType(duration: Double) -> String {
        switch duration {
        case 0..<60:     return "XS"  // Under 1 minute
        case 60..<300:   return "S"   // 1-5 minutes
        case 300..<900:  return "M"   // 5-15 minutes
        case 900..<1800: return "L"   // 15-30 minutes
        default:         return "XL"  // Over 30 minutes
        }
    }
    
    /// Video duration category
    public var durationCategory: String {
        return VideoMetadata.classifyType(duration: duration)
    }
}

// MARK: - Computed Properties
extension VideoMetadata {
    /// Aspect ratio of the video
    public var aspectRatio: Double {
        return Double(resolution.width / resolution.height)
    }
    
    /// Whether the video is in portrait orientation
    public var isPortrait: Bool {
        return resolution.height > resolution.width
    }
    
    /// Formatted duration string (HH:MM:SS)
    public var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

// MARK: - Equatable
extension VideoMetadata: Equatable {
    public static func == (lhs: VideoMetadata, rhs: VideoMetadata) -> Bool {
        return lhs.file == rhs.file &&
            lhs.duration == rhs.duration &&
            lhs.resolution == rhs.resolution &&
            lhs.codec == rhs.codec &&
            lhs.type == rhs.type
    }
}

// MARK: - CustomStringConvertible
extension VideoMetadata: CustomStringConvertible {
    public var description: String {
        return """
        Video: \(file.lastPathComponent)
        Duration: \(formattedDuration)
        Resolution: \(Int(resolution.width))x\(Int(resolution.height))
        Codec: \(codec)
        Type: \(type)
        Creation Date: \(creationDate)
        """
    }
}

// MARK: - Asset Extension
@available(macOS 12.0, *)
extension VideoMetadata {
    /// Create metadata from an AVAsset
    /// - Parameter asset: The AVAsset to extract metadata from
    /// - Returns: VideoMetadata instance
    public static func from(_ asset: AVAsset) async throws -> VideoMetadata {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            throw MosaicError.noVideoTrack
        }
        
        let duration = try await asset.load(.duration).seconds
        let size = try await track.load(.naturalSize)
        let codec = try await track.mediaFormat
        let type = VideoMetadata.classifyType(duration: duration)
        let creationDate: AVMetadataItem? = try await asset.load(.creationDate)
        // Handle URL based on asset type
        let fileURL: URL
        if let urlAsset = asset as? AVURLAsset {
            fileURL = urlAsset.url
        } else {
            fileURL = URL(fileURLWithPath: "unknown")
        }
        
        return VideoMetadata(
            file: fileURL,
            duration: duration,
            resolution: size,
            codec: codec,
                type: type,
            creationDate: creationDate?.stringValue
        )
    }
}

/* old
 
 
import Foundation
import CoreGraphics

/// Represents metadata for a video file
public struct VideoMetadata: Hashable {
    /// The URL of the video file
    public let file: URL
    
    /// Duration of the video in seconds
    public let duration: Double
    
    /// Resolution of the video
    public let resolution: CGSize
    
    /// Codec used for the video
    public let codec: String
    
    /// Type classification of the video (XS, S, M, L, XL)
    public let type: String

    public init(file: URL, duration: Double, resolution: CGSize, codec: String, type: String) {
        self.file = file
        self.duration = duration
        self.resolution = resolution
        self.codec = codec
        self.type = type
    }
    
    /// Classifies video type based on duration
    public static func classifyType(duration: Double) -> String {
        switch duration {
        case 0..<60:     return "XS"
        case 60..<300:   return "S"
        case 300..<900:  return "M"
        case 900..<1800: return "L"
        default:         return "XL"
        }
    }
}


/// Represents a timestamp overlay in the mosaic
public struct TimeStamp: Equatable {
    /// Timestamp text
    public let ts: String
    
    /// X position in the mosaic
    public let x: Int
    
    /// Y position in the mosaic
    public let y: Int
    
    /// Width of the timestamp area
    public let w: Int
    
    /// Height of the timestamp area
    public let h: Int
}

/// Represents progress information for the mosaic generation process
public struct ProgressInfo {
    /// Current progress (0.0 - 1.0)
    public let progress: Double
    
    /// Name of the current file being processed
    public let currentFile: String
    
    /// Number of files processed
    public let processedFiles: Int
    
    /// Total number of files to process
    public let totalFiles: Int
    
    /// Current processing stage
    public let currentStage: String
    
    /// Time elapsed since start
    public let elapsedTime: TimeInterval
    
    /// Estimated time remaining
    public let estimatedTimeRemaining: TimeInterval
    
    /// Number of files skipped
    public let skippedFiles: Int
    
    /// Number of files with errors
    public let errorFiles: Int
    
    /// Whether processing is currently running
    public let isRunning: Bool
}
*/
