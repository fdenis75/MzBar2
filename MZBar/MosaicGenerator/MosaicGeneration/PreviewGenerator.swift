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
import Cocoa

/// Responsible for generating video previews
public final class PreviewGenerator {
    // MARK: - Properties
    
    private let config: MosaicGeneratorConfig
    private let logger = Logger(subsystem: "com.mosaic.generation", category: "PreviewGenerator")
    private let minExtractDuration: Double = 0.0
    private var progressHandler: ((ProgressInfo) -> Void)?
    public  var isCancelled: Bool = false
    private var currentExportSession: AVAssetExportSession?
    private var currentVideoFile: URL?
    private let signposter = OSSignposter(logHandle: .preview)
    
    
    
    // MARK: - Initialization
    
    /// Initialize preview generator with configuration
    /// - Parameter config: Generator configuration
    public init(config: MosaicGeneratorConfig) {
        self.config = config
        
    }
    public func setProgressHandler(_ handler: @escaping (ProgressInfo) -> Void) {
        self.progressHandler = handler
    }
    public func cancelCurrentPreview(for videoFile: URL) {
        if currentVideoFile == videoFile {
            isCancelled = true
            currentExportSession?.cancelExport()
        }
    }
    
    
    private func updateProgress(
        currentFile: String,
        processedFiles: Int,
        totalFiles: Int,
        stage: String,
        startTime: CFAbsoluteTime,
        progress: Float
    ) {
        let elapsedTime = CFAbsoluteTimeGetCurrent() - startTime
        var estimatedTimeRemaining = TimeInterval(0.0)
        
        if processedFiles > 0 {
            estimatedTimeRemaining = elapsedTime / Double(progress) - elapsedTime
        }
        var gProg = Double(processedFiles) / Double(totalFiles)
        
        if gProg.isNaN
        {
            gProg = 0
        }
        
        let info = ProgressInfo(
            progressType: .file,
            progress: gProg,
            currentFile: currentFile,
            processedFiles: processedFiles,
            totalFiles: totalFiles,
            currentStage: stage,
            elapsedTime: elapsedTime,
            estimatedTimeRemaining: estimatedTimeRemaining,
            skippedFiles: 0,
            errorFiles: 0,
            isRunning: true,
            fileProgress: Double(progress)
        )
        
        DispatchQueue.main.async {
            self.progressHandler?(info)
        }
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
       
       
        let state = signposter.beginInterval("Process Video")
        defer{
            signposter.endInterval("Process Video", state)
        }
        var previewURL: URL = outputDirectory
        
            logger.debug("Generating preview for: \(videoFile.lastPathComponent)")
            isCancelled = false
            let startTime = CFAbsoluteTimeGetCurrent()
            var speedMultiplier: Double = 1.0
            if isCancelled { throw CancellationError() }
            currentVideoFile = videoFile
            // Create asset
            let asset = AVURLAsset(url: videoFile)
            let duration = try await asset.load(.duration).seconds
            logger.debug("extracting params for: \(videoFile.lastPathComponent)")
            // Calculate extract parameters
           
            let extractParams = try calculateExtractionParameters(
                duration: duration,
                density: density,
                previewDuration: Double(previewDuration),
                minExtractDuration: minExtractDuration
            )
         
            if isCancelled { throw CancellationError() }
            
            // Setup output location
            let previewDirectory = try await setupOutputDirectory(baseDirectory: outputDirectory)
            previewURL = previewDirectory.appendingPathComponent(
                "\(videoFile.deletingPathExtension().lastPathComponent)-amprv-\(density.rawValue)-\(extractParams.extractCount).mp4"
            )
            updateProgress(
                currentFile: videoFile.path,
                processedFiles: 0,
                totalFiles: 1,
                stage: "Starting preview generation",
                startTime: startTime,
                progress: 0.0
            )
            if (FileManager.default.fileExists(atPath: previewURL.path) && !FileManager.default.isDeletableFile(atPath: previewURL.path)){
                // Remove existing preview if present
                try? FileManager.default.removeItem(at: previewURL)
            }
            if isCancelled { throw CancellationError() }
            logger.debug("create composition  for: \(videoFile.lastPathComponent)")
            
            // Create composition
            let (composition, videoTrack, audioTrack) = try await createComposition(
                asset: asset,
                extractParams: extractParams,
                speedMultiplier: speedMultiplier
            )
            
            // Export preview
            logger.debug("export preview  for: \(videoFile.lastPathComponent)")
            
            try await exportPreview(
                composition: composition,
                videoTrack: videoTrack,
                audioTrack: audioTrack,
                to: previewURL
                
            )
            
            logger.debug("Preview generation completed in \(CFAbsoluteTimeGetCurrent() - startTime) seconds")
            updateProgress(
                currentFile: videoFile.path,
                processedFiles: 1,
                totalFiles: 1,
                stage: "Preview generation complete",
                startTime: startTime,
                progress: 1.0
            )
            if isCancelled {
                try? FileManager.default.removeItem(at: previewURL)
                throw CancellationError()
            }
        
            return previewURL
        }
    
    
    // MARK: - Private Methods
    
    private func calculateExtractionParameters(
        duration: Double,
        density: DensityConfig,
        previewDuration: Double,
        minExtractDuration: Double
    ) throws -> (extractCount: Int, extractDuration: Double, finalPreviewDuration: Double) {
        let state = signposter.beginInterval("calculateExtractionParameters")
        defer{
            signposter.endInterval("calculateExtractionParameters", state)
        }
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
        if !FileManager.default.fileExists(atPath: previewDirectory.path) {
            try FileManager.default.createDirectory(
                at: previewDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
        
        return previewDirectory
    }
    
    private func createComposition(
        asset: AVAsset,
        extractParams: (extractCount: Int, extractDuration: Double, finalPreviewDuration: Double),
        speedMultiplier: Double
    ) async throws -> (AVMutableComposition, AVAssetTrack, AVAssetTrack) {
        let state = signposter.beginInterval("createComposition")
        defer{
            signposter.endInterval("createComposition", state)
        }
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
            asset: asset,
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
        asset: AVAsset,
        into composition: AVMutableComposition,
        videoTrack: AVAssetTrack,
        audioTrack: AVAssetTrack,
        compositionVideoTrack: AVMutableCompositionTrack,
        compositionAudioTrack: AVMutableCompositionTrack,
        extractParams: (extractCount: Int, extractDuration: Double, finalPreviewDuration: Double),
        speedMultiplier: Double
    ) async throws {
        let state = signposter.beginInterval("insertSegments")
        defer{
            signposter.endInterval("insertSegments", state)
        }
        let duration = try await asset.load(.duration).seconds
        let timescale: CMTimeScale = 600
        var currentTime = CMTime.zero
        let durationCMTime = CMTime(seconds: extractParams.extractDuration, preferredTimescale: timescale)
        let fastPlaybackDuration = CMTime(
            seconds: extractParams.extractDuration / speedMultiplier,
            preferredTimescale: timescale
        )
        for i in 0..<extractParams.extractCount {
            let startTime = CMTime(
                seconds: Double(i) * (duration - extractParams.extractDuration) / Double(extractParams.extractCount - 1),
                preferredTimescale: timescale
            )
            do {
                let timeRange = CMTimeRange(start: currentTime, duration: durationCMTime)
                
                //  print("extract i: \(i), timerange: \(timeRange.duration.seconds), at \(currentTime.seconds), changing time range to \(fastPlaybackDuration.seconds)")
                
                try  compositionVideoTrack.insertTimeRange(
                    CMTimeRange(start: startTime, duration: durationCMTime),
                    of: videoTrack,
                    at: currentTime
                )
                compositionVideoTrack.scaleTimeRange(timeRange, toDuration: fastPlaybackDuration)
                
                try  compositionAudioTrack.insertTimeRange(
                    CMTimeRange(start: startTime, duration: durationCMTime),
                    of: audioTrack,
                    at: currentTime
                )
                compositionAudioTrack.scaleTimeRange(timeRange, toDuration: fastPlaybackDuration)
                
                currentTime = CMTimeAdd(currentTime, fastPlaybackDuration)
            }catch {
                logger.error("Failed to insert or scale time range: \(error.localizedDescription)")
            }
        }
    }
    
    private func exportPreview(
        composition: AVComposition,
        videoTrack: AVAssetTrack?,
        audioTrack: AVAssetTrack?,
        to outputURL: URL
    ) async throws {
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: config.videoExportPreset
        ) else {
            throw MosaicError.unableToGenerateMosaic
        }
        
        currentExportSession = exportSession
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.allowsParallelizedExport = true
        exportSession.directoryForTemporaryFiles = FileManager.default.temporaryDirectory
        
        let exportTask = Task {
            try await exportSession.export(to: outputURL, as: .mp4)
        }
        
        let progressTask = Task {
            await trackExportProgress(exportSession: exportSession, outputURL: outputURL)
        }
        
        do {
            try await withThrowingTaskGroup(of: Void.self) { taskGroup in
                taskGroup.addTask {
                    try await exportTask.value
                }
                
                taskGroup.addTask {
                    await progressTask.value
                }
                
                taskGroup.addTask {
                    while !Task.isCancelled && !self.isCancelled {
                        try await Task.sleep(nanoseconds: 100_000_000)
                    }
                    if self.isCancelled || Task.isCancelled {
                        exportTask.cancel()
                        progressTask.cancel()
                        exportSession.cancelExport()
                        throw CancellationError()
                    }
                }
            
                try await taskGroup.waitForAll()
            }
        } catch is CancellationError {
            throw CancellationError()
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
