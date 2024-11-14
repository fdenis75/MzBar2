//
//  MosaicGenerator.swift
//  MZBar
//
//  Created by Francois on 02/11/2024.
//
import Foundation
import AVFoundation
import CoreGraphics
import os.log
import SwiftUI

struct TimeStamp {
    let ts: String
    let x: Int
    let y: Int
    let w: Int
    let h: Int
}
/// Main class responsible for generating mosaic images from video files
public final class MosaicGenerator {
    // MARK: - Properties
    
    
    private let logger = Logger(subsystem: "com.mosaic.generation", category: "MosaicGenerator")
    private let config: MosaicGeneratorConfig
    private let videoProcessor: VideoProcessor
    private let thumbnailProcessor: ThumbnailProcessor
    private let layoutProcessor: LayoutProcessor
    private var progressHandler: ((ProgressInfo) -> Void)?
    
    /// Whether processing should be cancelled
    private var isCancelled = false
    
    /// Current files being processed
    public private(set) var videosFiles: [(URL, URL)] = []
    
    // MARK: - Initialization
    
    /// Initialize mosaic generator with configuration
    /// - Parameter config: Generator configuration
    public init(config: MosaicGeneratorConfig = .default) {
        self.config = config
        self.videoProcessor = VideoProcessor()
        self.thumbnailProcessor = ThumbnailProcessor(config: config)
        self.layoutProcessor = LayoutProcessor()
    }
    
    // MARK: - Public Methods
    
    /// Set progress handler for generation updates
    /// - Parameter handler: Progress handler closure
    public func setProgressHandler(_ handler: @escaping (ProgressInfo) -> Void) {
        self.progressHandler = handler
    }
    
    /// Cancel ongoing generation
    public func cancelGeneration() {
        isCancelled = true
    }
    
  
  
    // MARK: - Private Methods
    
    /// Processes a single video file to generate a mosaic image
    /// - Parameters:
    ///   - video: The input video file URL to process
    ///   - output: The output directory URL where the mosaic will be saved
    ///   - config: Configuration options for processing the video
    /// - Returns: A tuple containing (input video URL, output mosaic URL)
    /// - Throws: `MosaicError` for various failure conditions
    public func processSingleFile(
        video: URL,
        output: URL,
        config: ProcessingConfiguration
    ) async throws -> (URL, URL) {
        // Initialize timing and logging
        let startTime = CFAbsoluteTimeGetCurrent()
        logger.debug("Processing file: \(video.lastPathComponent)")
        let asset = AVURLAsset(url: video)
        if try await !asset.load(.isPlayable) {
            throw MosaicError.notAVideoFile
        }	
        // MARK: - Initial Metadata Processing
        updateProgress(
            currentFile: video.path,
            processedFiles: 0,
            totalFiles: 1,
            stage: "Processing metadata",
            startTime: startTime,
            fileProgress: 0.2
        )
        
        do {
            let metadata = try await videoProcessor.processVideo(file: video, asset: asset)
            
            // Early validation checks
            guard config.duration <= 0 || Int(metadata.duration) >= config.duration else {
                logger.debug("File too short: \(video.lastPathComponent)")
                throw MosaicError.tooShort
            }
            
            if try await isExistingFile(
                for: video,
                in: output,
                format: config.format,
                type: metadata.type,
                density: config.density.rawValue,
                addPath: config.addFullPath
            ) && !config.overwrite {
                logger.debug("Existing file: \(video.lastPathComponent)")
                throw MosaicError.existingVid
            }
            
            // MARK: - Layout Processing
            let aspectRatio = metadata.resolution.width / metadata.resolution.height
            let thumbnailCount = layoutProcessor.calculateThumbnailCount(
                duration: metadata.duration,
                width: config.width,
                density: config.density
            )
            
            updateProgress(
                currentFile: video.path,
                processedFiles: 0,
                totalFiles: 1,
                stage: "Generating layout",
                startTime: startTime,
                fileProgress: 0.4
            )
            
            let layout = layoutProcessor.calculateLayout(
                originalAspectRatio: aspectRatio,
                thumbnailCount: thumbnailCount,
                mosaicWidth: config.width,
                density: config.density,
                useCustomLayout: config.customLayout
            )
            
            // MARK: - Thumbnail Processing
            let thumbnails = try await thumbnailProcessor.extractThumbnails(
                from: video,
                layout: layout,
                asset: asset,
                preview: false,
                accurate: config.generatorConfig.accurateTimestamps
            )
            
            // MARK: - Mosaic Generation
            updateProgress(
                currentFile: video.path,
                processedFiles: 0,
                totalFiles: 1,
                stage: "Creating mosaic",
                startTime: startTime,
                fileProgress: 0.6
            )
            
            let mosaic = try await generateMosaic(
                from: thumbnails,
                layout: layout,
                metadata: metadata
            )
            
            // MARK: - Save Results
            updateProgress(
                currentFile: video.path,
                processedFiles: 0,
                totalFiles: 1,
                stage: "Saving mosaic",
                startTime: startTime,
                fileProgress: 0.8
            )
            
            let finalOutputDirectory = config.separateFolders 
                ? output.appendingPathComponent(metadata.type, isDirectory: true)
                : output
            
            let result = try await saveMosaic(
                mosaic,
                for: video,
                in: finalOutputDirectory,
                format: config.format,
                type: metadata.type,
                density: config.density.rawValue,
                addPath: config.addFullPath
            )
            
            updateProgress(
                currentFile: video.path,
                processedFiles: 1,
                totalFiles: 1,
                stage: "Mosaic generation complete",
                startTime: startTime,
                fileProgress: 1.0
            )
            
            return result
            
        } catch {
            let (stage, errorToThrow): (String, Error) = {
                switch error {
                case MosaicError.tooShort:
                    return ("File too short", error)
                case MosaicError.existingVid:
                    return ("File already exists", error)
                default:
                    return ("Error while processing file", error)
                }
            }()
            
            updateProgress(
                currentFile: video.path,
                processedFiles: 1,
                totalFiles: 1,
                stage: stage,
                startTime: startTime,
                fileProgress: 1.0
            )
            
            throw errorToThrow
        }
    }
    
    
    private func updateProgress(
        currentFile: String,
        processedFiles: Int,
        totalFiles: Int,
        stage: String,
        startTime: CFAbsoluteTime,
        fileProgress: Double = 0.0
    ) {
        // Calculate elapsed time once
        let elapsedTime = CFAbsoluteTimeGetCurrent() - startTime
        
        // Use safer calculation for overall progress
        let progress = totalFiles > 0 ? Double(processedFiles) / Double(totalFiles) : 0
        
        // Calculate estimated time remaining only if there's actual progress
        let estimatedTimeRemaining: TimeInterval = processedFiles > 0 && progress > 0 
            ? (elapsedTime / progress) - elapsedTime 
            : 0
        
        let info = ProgressInfo(
            progressType: .file,
            progress: progress,
            currentFile: currentFile,
            processedFiles: processedFiles,
            totalFiles: totalFiles,
            currentStage: stage,
            elapsedTime: elapsedTime,
            estimatedTimeRemaining: estimatedTimeRemaining,
            skippedFiles: 0,
            errorFiles: 0,
            isRunning: true,
            fileProgress: fileProgress // Use the passed fileProgress instead of overall progress
        )
        
        DispatchQueue.main.async { [weak self] in
            self?.progressHandler?(info)
        }
    }
    
    /// Generate a mosaic from thumbnails
    /// - Parameters:
    ///   - thumbnails: Array of thumbnails with timestamps
    ///   - layout: Layout information
    ///   - metadata: Video metadata
    /// - Returns: Generated mosaic image
    public func generateMosaic(
        from thumbnails: [(image: CGImage, timestamp: String)],
        layout: MosaicLayout,
        metadata: VideoMetadata
    ) async throws -> CGImage {
        logger.debug("Generating mosaic for: \(metadata.file.lastPathComponent)")
        
        
            // Create drawing context
            guard let context = createContext(width: Int(layout.mosaicSize.width),
                                           height: Int(layout.mosaicSize.height)) else {
                throw MosaicError.unableToCreateContext
            }
            
            // Fill background
            context.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0))
            context.fill(CGRect(x: 0, y: 0,
                              width: layout.mosaicSize.width,
                              height: layout.mosaicSize.height))
            
            // Draw thumbnails concurrently
            var timestampInfo = Array(repeating: TimeStamp(ts: "", x: 0, y: 0, w: 0, h: 0),
                                    count: min(thumbnails.count, layout.positions.count))
            
            DispatchQueue.concurrentPerform(
                iterations: min(thumbnails.count, layout.positions.count)
            ) { index in
                let (thumbnail, timestamp) = thumbnails[index]
                let position = layout.positions[index]
                let thumbnailSize = layout.thumbnailSizes[index]
                let x = position.x
                let y = Int(layout.mosaicSize.height) - Int(thumbnailSize.height) - position.y
                
                context.draw(thumbnail, in: CGRect(
                    x: x, y: y,
                    width: Int(thumbnailSize.width),
                    height: Int(thumbnailSize.height)
                ))
                
                timestampInfo[index] = TimeStamp(
                    ts: timestamp,
                    x: x,
                    y: y,
                    w: Int(thumbnailSize.width),
                    h: Int(thumbnailSize.height)
                )
            }
            
            // Draw timestamps
            drawTimestamps(context: context, timestamps: timestampInfo)
            
            // Draw metadata
            drawMetadata(context: context, metadata: metadata,
                        width: Int(layout.mosaicSize.width),
                        height: Int(layout.mosaicSize.height))
            
            guard let outputImage = context.makeImage() else {
                throw MosaicError.unableToGenerateMosaic
            }
            
            return outputImage
        
    }

    // MARK: - Private Methods
    
    private func createContext(width: Int, height: Int) -> CGContext? {
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }
    
    private func drawTimestamps(context: CGContext, timestamps: [TimeStamp]) {
        for ts in timestamps {
            let fontSize = CGFloat(ts.h) / 6 / 1.618
            let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white.cgColor
            ]
            
            let attributedTimestamp = CFAttributedStringCreate(
                nil,
                ts.ts as CFString,
                attributes as CFDictionary
            )
            let line = CTLineCreateWithAttributedString(attributedTimestamp!)
            
            context.saveGState()
            context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.1))
            
            let textRect = CGRect(
                x: ts.x,
                y: ts.y,
                width: ts.w,
                height: Int(CGFloat(ts.h) / 7)
            )
            context.fill(textRect)
            
            let textWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
            let textPosition = CGPoint(
                x: ts.x + ts.w - Int(textWidth) - 5,
                y: ts.y + 10
            )
            
            context.textPosition = textPosition
            CTLineDraw(line, context)
            context.restoreGState()
        }
    }
    
    private func drawMetadata(context: CGContext, metadata: VideoMetadata, width: Int, height: Int) {
        let metadataHeight = Int(round(Double(height) * 0.1))
        let lineHeight = metadataHeight / 4
        let fontSize = round(Double(lineHeight) / 1.618)
        
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 0.2))
        context.fill(CGRect(
            x: 0,
            y: height - metadataHeight,
            width: width,
            height: metadataHeight
        ))
        
        let metadataText = """
        File: \(metadata.file.standardizedFileURL.standardizedFileURL)
        Codec: \(metadata.codec)
        Resolution: \(Int(metadata.resolution.width))x\(Int(metadata.resolution.height))
        Duration: \(formatDuration(seconds: metadata.duration))
        """
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: CTFontCreateWithName("Helvetica" as CFString, fontSize, nil),
            .foregroundColor: NSColor.white.cgColor
        ]
        
        let attributedString = NSAttributedString(string: metadataText, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        
        let rect = CGRect(
            x: 10,
            y: height - metadataHeight + 10,
            width: width - 20,
            height: metadataHeight - 20
        )
        let path = CGPath(rect: rect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
        
        context.saveGState()
        CTFrameDraw(frame, context)
        context.restoreGState()
    }
    
    private func formatDuration(seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let seconds = Int(seconds) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

extension MosaicGenerator {
    private func saveMosaic(
        _ mosaic: CGImage,
        for videoFile: URL,
        in outputDirectory: URL,
        format: String,
        type: String,
        density: String,
        addPath: Bool
    ) async throws -> (URL, URL) {
        // Create export manager if not exists
        let exportManager = ExportManager(config: self.config)
        
        // Save the mosaic
        let outputURL = try await exportManager.saveMosaic(
            mosaic,
            for: videoFile,
            in: outputDirectory,
            format: format,
            type: type,
            density: density,
            addPath: addPath
        )
        return (videoFile, outputURL)
    }
    
    
    private func isExistingFile( for videoFile: URL,
                                 in outputDirectory: URL,
                                 format: String,
                                 type: String,
                                 density: String,
                                 addPath: Bool) async throws -> Bool
    {
        let exportManager = ExportManager(config: self.config)
        return try await exportManager.FileExists(for: videoFile, in: outputDirectory, format: format, type: type, density: density, addPath: addPath)
    }
}




