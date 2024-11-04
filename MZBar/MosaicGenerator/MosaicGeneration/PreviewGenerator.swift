//
//  PreviewGenerator.swift
//  MZBar
//
//  Created by Francois on 02/11/2024.
//

import Foundation
import AVFoundation
import CoreGraphics
import os.log

/// Responsible for generating video previews
public final class PreviewGenerator {
    // MARK: - Properties
    
    private let config: MosaicGeneratorConfig
    private let logger = Logger(subsystem: "com.mosaic.generation", category: "PreviewGenerator")
    private let minExtractDuration: Double = 2.0
    
    // MARK: - Initialization
    
    /// Initialize preview generator with configuration
    /// - Parameter config: Generator configuration
    public init(config: MosaicGeneratorConfig) {
        self.config = config
    }
    
    // MARK: - Public Methods
    
    /// Generate preview for a video file
    /// - Parameters:
    ///   - videoFile: Source video file
    ///   - outputDirectory: Output directory
    ///   - density: Density configuration
    ///   - previewDuration: Desired preview duration
    /// - Returns: URL of generated preview
    public func generatePreview(
        for videoFile: URL,
        outputDirectory: URL,
        density: DensityConfig,
        previewDuration: Int
    ) async throws -> URL {
        logger.debug("Generating preview for: \(videoFile.lastPathComponent)")
        let startTime = CFAbsoluteTimeGetCurrent()
        var speedMultiplier: Double = 1.0
        
        // Create asset
        let asset = AVURLAsset(url: videoFile)
        let duration = try await asset.load(.duration).seconds
        
        // Calculate extract parameters
        let extractParams = try calculateExtractionParameters(
            duration: duration,
            density: density,
            previewDuration: Double(previewDuration),
            minExtractDuration: minExtractDuration
        )
        
        // Setup output location
        let previewDirectory = try await setupOutputDirectory(baseDirectory: outputDirectory)
        let previewURL = previewDirectory.appendingPathComponent(
            "\(videoFile.deletingPathExtension().lastPathComponent)-amprv-\(density.rawValue)-\(extractParams.extractCount).mp4"
        )
        
        // Remove existing preview if present
        try? FileManager.default.removeItem(at: previewURL)
        
        // Create composition
        let (composition, videoTrack, audioTrack) = try await createComposition(
            asset: asset,
            extractParams: extractParams,
            speedMultiplier: speedMultiplier
        )
        
        // Export preview
        try await exportPreview(
            composition: composition,
            videoTrack: videoTrack,
            audioTrack: audioTrack,
            to: previewURL,
            speedMultiplier: speedMultiplier
        )
        
        logger.debug("Preview generation completed in \(CFAbsoluteTimeGetCurrent() - startTime) seconds")
        return previewURL
    }
    
    // MARK: - Private Methods
    
    private func calculateExtractionParameters(
        duration: Double,
        density: DensityConfig,
        previewDuration: Double,
        minExtractDuration: Double
    ) throws -> (extractCount: Int, extractDuration: Double, finalPreviewDuration: Double) {
        let baseExtractsPerMinute: Double
        if duration > 0 {
            let durationInMinutes = duration / 60.0
            let initialRate = 12.0
            let decayFactor = 0.2
            baseExtractsPerMinute = (initialRate / (1 + decayFactor * durationInMinutes)) / density.extractsMultiplier
        } else {
            baseExtractsPerMinute = 12.0
        }
        
        let extractCount = Int(ceil(duration / 60.0 * baseExtractsPerMinute))
        var extractDuration = previewDuration / Double(extractCount)
        
        if extractDuration < minExtractDuration {
            extractDuration = minExtractDuration
        }
        
        let finalPreviewDuration = extractDuration * Double(extractCount)
        
        return (extractCount, extractDuration, finalPreviewDuration)
    }
    
    private func setupOutputDirectory(baseDirectory: URL) async throws -> URL {
        let previewDirectory = baseDirectory.deletingLastPathComponent()
            .appendingPathComponent("amprv", isDirectory: true)
        try FileManager.default.createDirectory(
            at: previewDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return previewDirectory
    }
    
    private func createComposition(
        asset: AVAsset,
        extractParams: (extractCount: Int, extractDuration: Double, finalPreviewDuration: Double),
        speedMultiplier: Double
    ) async throws -> (AVMutableComposition, AVAssetTrack, AVAssetTrack) {
        let composition = AVMutableComposition()
        
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ),
        let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ),
        let videoTrack = try await asset.loadTracks(withMediaType: .video).first,
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        else {
            throw MosaicError.unableToCreateCompositionTracks
        }
        
        try await insertSegments(
            into: composition,
            videoTrack: videoTrack,
            audioTrack: audioTrack,
            compositionVideoTrack: compositionVideoTrack,
            compositionAudioTrack: compositionAudioTrack,
            extractParams: extractParams,
            speedMultiplier: speedMultiplier
        )
        
        return (composition, videoTrack, audioTrack)
    }
    
    private func insertSegments(
        into composition: AVMutableComposition,
        videoTrack: AVAssetTrack,
        audioTrack: AVAssetTrack,
        compositionVideoTrack: AVMutableCompositionTrack,
        compositionAudioTrack: AVMutableCompositionTrack,
        extractParams: (extractCount: Int, extractDuration: Double, finalPreviewDuration: Double),
        speedMultiplier: Double
    ) async throws {
        let duration = try await composition.load(.duration).seconds
        let timescale: CMTimeScale = 600
        var currentTime = CMTime.zero
        
        for i in 0..<extractParams.extractCount {
            let startTime = CMTime(
                seconds: Double(i) * (duration - extractParams.extractDuration) / Double(extractParams.extractCount - 1),
                preferredTimescale: timescale
            )
            
            let extractDuration = CMTime(
                seconds: extractParams.extractDuration,
                preferredTimescale: timescale
            )
            
            let fastPlaybackDuration = CMTime(
                seconds: extractParams.extractDuration / speedMultiplier,
                preferredTimescale: timescale
            )
            
            let timeRange = CMTimeRange(start: currentTime, duration: extractDuration)
            
            try await compositionVideoTrack.insertTimeRange(
                CMTimeRange(start: startTime, duration: extractDuration),
                of: videoTrack,
                at: currentTime
            )
            try compositionVideoTrack.scaleTimeRange(timeRange, toDuration: fastPlaybackDuration)
            
            try await compositionAudioTrack.insertTimeRange(
                CMTimeRange(start: startTime, duration: extractDuration),
                of: audioTrack,
                at: currentTime
            )
            try compositionAudioTrack.scaleTimeRange(timeRange, toDuration: fastPlaybackDuration)
            
            currentTime = CMTimeAdd(currentTime, fastPlaybackDuration)
        }
    }
    
    private func exportPreview(
        composition: AVMutableComposition,
        videoTrack: AVAssetTrack,
        audioTrack: AVAssetTrack,
        to outputURL: URL,
        speedMultiplier: Double
    ) async throws {
        let originalFrameRate = try await videoTrack.load(.nominalFrameRate)
        
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: config.videoExportPreset
        ) else {
            throw MosaicError.unableToCreateExportSession
        }
        
        let videoComposition = AVMutableVideoComposition(propertiesOf: composition)
        videoComposition.frameDuration = CMTime(
            value: 1,
            timescale: CMTimeScale(originalFrameRate * Float(speedMultiplier))
        )
        
        let audioMix = AVMutableAudioMix()
        let audioParameters = AVMutableAudioMixInputParameters(track: audioTrack)
        audioMix.inputParameters = [audioParameters]
        
        try await configureAndExecuteExport(
            exportSession: exportSession,
            videoComposition: videoComposition,
            audioMix: audioMix,
            outputURL: outputURL
        )
    }
    
    private func configureAndExecuteExport(
        exportSession: AVAssetExportSession,
        videoComposition: AVMutableVideoComposition,
        audioMix: AVMutableAudioMix,
        outputURL: URL
    ) async throws {
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = false
        exportSession.videoComposition = videoComposition
        exportSession.audioMix = audioMix
        exportSession.allowsParallelizedExport = true
        
        try await exportSession.export()
        
        guard exportSession.status == .completed else {
            if let error = exportSession.error {
                throw error
            }
            throw MosaicError.unableToGenerateMosaic
        }
    }
}

/* old

import Foundation
import AVFoundation
import CoreGraphics
import os.log

/// Responsible for generating video previews
public final class PreviewGenerator {
    private let logger = Logger(subsystem: "com.mosaic.generation", category: "PreviewGenerator")
    private let config: MosaicGeneratorConfig
    
    /// Initialize a new preview generator
    /// - Parameter config: Configuration for preview generation
    public init(config: MosaicGeneratorConfig) {
        self.config = config
    }
    
    /// Generate animated preview for a video
    /// - Parameters:
    ///   - videoFile: Source video file
    ///   - outputDirectory: Output directory for preview
    ///   - density: Density configuration
    ///   - previewDuration: Desired duration of preview
    /// - Returns: URL of generated preview
    public func generatePreview(
        for videoFile: URL,
        outputDirectory: URL,
        density: String,
        previewDuration: Int
    ) async throws -> URL {
        logger.debug("Generating preview for: \(videoFile.lastPathComponent)")
        
        let asset = AVURLAsset(url: videoFile)
        let duration = try await asset.load(.duration).seconds
        let minExtractDuration = 2.0
        var speedMultiplier: Double = 1.0
        
        // Calculate extract parameters
        let extractParams = try await calculateExtractionParameters(
            duration: duration,
            density: density,
            previewDuration: Double(previewDuration),
            minExtractDuration: minExtractDuration
        )
        
        // Setup output location
        let previewDirectory = try await setupOutputDirectory(
            baseDirectory: outputDirectory
        )
        
        let previewURL = previewDirectory.appendingPathComponent(
            "\(videoFile.deletingPathExtension().lastPathComponent)-amprv-\(density)-\(extractParams.extractCount).mp4"
        )
        
        try await removeExistingPreview(at: previewURL)
        
        // Create composition
        let (composition, videoTrack, audioTrack) = try await createComposition(
            asset: asset,
            extractParams: extractParams,
            speedMultiplier: speedMultiplier
        )
        
        // Export preview
        try await exportPreview(
            composition: composition,
            videoTrack: videoTrack,
            audioTrack: audioTrack,
            to: previewURL,
            speedMultiplier: speedMultiplier
        )
        
        return previewURL
    }
    
    // MARK: - Private Methods
    
    private func calculateExtractionParameters(
        duration: Double,
        density: DensityConfig,
        previewDuration: Double,
        minExtractDuration: Double
    ) async throws -> (extractCount: Int, extractDuration: Double, finalPreviewDuration: Double) {
        let densityConfig = DensityConfig.from(density)
        
        let baseExtractsPerMinute: Double
        if duration > 0 {
            let durationInMinutes = duration / 60.0
            let initialRate = 12.0
            let decayFactor = 0.2
            baseExtractsPerMinute = (initialRate / (1 + decayFactor * durationInMinutes)) / densityConfig.extractsMultiplier
        } else {
            baseExtractsPerMinute = 12.0
        }
        
        let extractCount = Int(ceil(duration / 60.0 * baseExtractsPerMinute))
        var extractDuration = previewDuration / Double(extractCount)
        
        if extractDuration < minExtractDuration {
            extractDuration = minExtractDuration
        }
        
        let finalPreviewDuration = extractDuration * Double(extractCount)
        
        return (extractCount, extractDuration, finalPreviewDuration)
    }
    
    private func setupOutputDirectory(baseDirectory: URL) async throws -> URL {
        let previewDirectory = baseDirectory.deletingLastPathComponent()
            .appendingPathComponent("amprv", isDirectory: true)
        try FileManager.default.createDirectory(
            at: previewDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return previewDirectory
    }
    
    private func removeExistingPreview(at url: URL) async throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
            logger.info("Removed existing preview: \(url.path)")
        }
    }
    
    private func createComposition(
        asset: AVAsset,
        extractParams: (extractCount: Int, extractDuration: Double, finalPreviewDuration: Double),
        speedMultiplier: Double
    ) async throws -> (AVMutableComposition, AVAssetTrack, AVAssetTrack) {
        let composition = AVMutableComposition()
        
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ),
        let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ),
        let videoTrack = try await asset.loadTracks(withMediaType: .video).first,
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        else {
            throw MosaicError.unableToCreateCompositionTracks
        }
        
        let duration = try await asset.load(.duration).seconds
        let timescale: CMTimeScale = 600
        
        var currentTime = CMTime.zero
        for i in 0..<extractParams.extractCount {
            let startTime = CMTime(
                seconds: Double(i) * (duration - extractParams.extractDuration)
                    / Double(extractParams.extractCount - 1),
                preferredTimescale: timescale
            )
            
            let extractDuration = CMTime(
                seconds: extractParams.extractDuration,
                preferredTimescale: timescale
            )
            
            let fastPlaybackDuration = CMTime(
                seconds: extractParams.extractDuration / speedMultiplier,
                preferredTimescale: timescale
            )
            
            try await insertAndScaleSegment(
                compositionVideoTrack: compositionVideoTrack,
                compositionAudioTrack: compositionAudioTrack,
                videoTrack: videoTrack,
                audioTrack: audioTrack,
                startTime: startTime,
                extractDuration: extractDuration,
                currentTime: currentTime,
                fastPlaybackDuration: fastPlaybackDuration
            )
            
            currentTime = CMTimeAdd(currentTime, fastPlaybackDuration)
        }
        
        return (composition, videoTrack, audioTrack)
    }
    
    private func insertAndScaleSegment(
        compositionVideoTrack: AVMutableCompositionTrack,
        compositionAudioTrack: AVMutableCompositionTrack,
        videoTrack: AVAssetTrack,
        audioTrack: AVAssetTrack,
        startTime: CMTime,
        extractDuration: CMTime,
        currentTime: CMTime,
        fastPlaybackDuration: CMTime
    ) async throws {
        let timeRange = CMTimeRange(start: currentTime, duration: extractDuration)
        
        // Insert and scale video segment
        try await compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: startTime, duration: extractDuration),
            of: videoTrack,
            at: currentTime
        )
        try compositionVideoTrack.scaleTimeRange(timeRange, toDuration: fastPlaybackDuration)
        
        // Insert and scale audio segment
        try await compositionAudioTrack.insertTimeRange(
            CMTimeRange(start: startTime, duration: extractDuration),
            of: audioTrack,
            at: currentTime
        )
        try compositionAudioTrack.scaleTimeRange(timeRange, toDuration: fastPlaybackDuration)
        
        logger.debug("""
            Inserted segment at \(startTime.seconds)s, \
            duration: \(extractDuration.seconds)s, \
            scaled to: \(fastPlaybackDuration.seconds)s
            """)
    }

    private func exportPreview(
            composition: AVMutableComposition,
            videoTrack: AVAssetTrack,
            audioTrack: AVAssetTrack,
            to outputURL: URL,
            speedMultiplier: Double
        ) async throws {
            let originalFrameRate = try await videoTrack.load(.nominalFrameRate)
            
            guard let exportSession = AVAssetExportSession(
                asset: composition,
                presetName: config.videoExportPreset
            ) else {
                throw MosaicError.unableToCreateExportSession
            }
            
            // Configure video composition
            let videoComposition = AVMutableVideoComposition(propertiesOf: composition)
            videoComposition.frameDuration = CMTime(
                value: 1,
                timescale: CMTimeScale(originalFrameRate * Float(speedMultiplier))
            )
            
            // Configure audio mix if needed
            let audioMix = AVMutableAudioMix()
            let audioParameters = AVMutableAudioMixInputParameters(track: audioTrack)
            audioMix.inputParameters = [audioParameters]
            
            // Configure export session
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .mp4
            exportSession.shouldOptimizeForNetworkUse = false
            exportSession.videoComposition = videoComposition
            exportSession.audioMix = audioMix
            exportSession.allowsParallelizedExport = true
            exportSession.directoryForTemporaryFiles = FileManager.default.temporaryDirectory
            
            // Track export progress
            let progressTracking = Task {
                await trackExportProgress(exportSession: exportSession, outputURL: outputURL)
            }
            
            // Perform export
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    await progressTracking.value
                }
                
                group.addTask {
                    try await exportSession.export(to: outputURL, as: .mp4)
                }
                
                try await group.waitForAll()
            }
            
            // Verify export status
            switch await exportSession.status {
            case .completed:
                logger.info("Preview export completed: \(outputURL.path)")
            case .failed:
                logger.error("Preview export failed: \(String(describing: exportSession.error))")
                throw MosaicError.unableToGenerateMosaic
            case .cancelled:
                logger.info("Preview export cancelled")
                throw CancellationError()
            default:
                logger.error("Preview export ended with unexpected state: \(exportSession.status.rawValue)")
                throw MosaicError.unableToGenerateMosaic
            }
        }
        
        private func trackExportProgress(
            exportSession: AVAssetExportSession,
            outputURL: URL
        ) async {
            let updateInterval: TimeInterval = 0.5
            
            for await state in await exportSession.states(updateInterval: updateInterval) {
                if Task.isCancelled { break }
                
                let progress = exportSession.progress
                let percentage = Int(progress * 100)
                
                logger.debug("Export progress: \(percentage)% for \(outputURL.lastPathComponent)")
                
                if exportSession.status == .completed { break }
            }
        }
    }
*/
