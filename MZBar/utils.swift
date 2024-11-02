import Foundation
import CoreGraphics
import AVFoundation
import AppKit

public struct VideoMetadata {
    public let file: URL
    public let duration: Double
    public let resolution: CGSize
    public let codec: String
    public let type: String

    public var description: String {
        """
        File: \(file.lastPathComponent)
        Codec: \(codec)
        Resolution: \(Int(resolution.width))x\(Int(resolution.height))
        Duration: \(String(format: "%.2f", duration)) seconds
        """
    }

    public init(file: URL, duration: Double, resolution: CGSize, codec: String, type: String) {
        self.file = file
        self.duration = duration
        self.resolution = resolution
        self.codec = codec
        self.type = type
    }
}

public enum MosaicError: Error {
    case inputNotFound
    case notAVideoFile
    case noVideoTrack
    case unableToGetCodec
    case unableToGenerateMosaic
    case unableToSaveMosaic
    case unsupportedOutputFormat
    case thumbnailExtractionFailed
    case unableToCreateContext
    case existingVid
    case unableToCreateGPUExtractor
    case unableToCreateCompositionTracks
    case noVideoOrAudioTrack
    case unableToCreateExportSession
    case tooShort
}

public extension CGImage {
    func jpegData(compressionQuality: CGFloat) -> Data? {
        let bitmapRep = NSBitmapImageRep(cgImage: self)
        return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }

    func pngData() -> Data? {
        let bitmapRep = NSBitmapImageRep(cgImage: self)
        return bitmapRep.representation(using: .png, properties: [:])
    }
    
    static func create(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil,
                                width: width,
                                height: height,
                                bitsPerComponent: 8,
                                bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }


    
}
extension CGImage {
    func toPixelBuffer(size: CGSize) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
                     kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         Int(size.width),
                                         Int(size.height),
                                         kCVPixelFormatType_32ARGB,
                                         attrs,
                                         &pixelBuffer)
        
        guard status == kCVReturnSuccess, let pixelBuffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer)
        
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: pixelData,
                                width: Int(size.width),
                                height: Int(size.height),
                                bitsPerComponent: 8,
                                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                space: rgbColorSpace,
                                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
        
        context?.draw(self, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        
        return pixelBuffer
    }
}


@available(macOS 12, *)
public extension AVAssetTrack {
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

extension FourCharCode {
    func toString() -> String {
        let bytes: [CChar] = [
            CChar((self >> 24) & 0xff),
            CChar((self >> 16) & 0xff),
            CChar((self >> 8) & 0xff),
            CChar(self & 0xff),
            0
        ]
        let result = String(cString: bytes)
        let characterSet = CharacterSet.whitespaces
        return result.trimmingCharacters(in: characterSet)
    }
}

enum ThumbnailExtractionError: Error {
    case generationFailed(time: CMTime, underlyingError: Error)
    case partialFailure(successfulCount: Int, failedCount: Int)
}

extension ThumbnailExtractionError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .generationFailed(let time, let underlyingError):
            return "Failed to generate thumbnail at time \(time.seconds): \(underlyingError.localizedDescription)"
        case .partialFailure(let successfulCount, let failedCount):
            return "Partial failure in thumbnail extraction: \(successfulCount) successful, \(failedCount) failed"
        }
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

