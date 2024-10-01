import Foundation
import AVFoundation
import CoreGraphics
import AppKit
import ImageIO
import Accelerate
import CoreVideo
import os
import os.signpost
import Metal
import MetalKit

/// A class for generating mosaic images from video files.
public class MosaicGenerator {
    // MARK: - Enums
    
    /// Rendering modes for mosaic generation.
    public enum RenderingMode {
        case auto
        case metal
        case classic
    }
    
    // MARK: - Nested Types
    
    /// Represents the layout of thumbnails in the mosaic.
    struct MosaicLayout {
        let rows: Int
        let cols: Int
        let thumbnailSize: CGSize
        let positions: [(x: Int, y: Int)]
        let thumbCount: Int
    }

    struct Uniforms {
        var position: SIMD2<Float>
        var size: SIMD2<Float>
        var renderType: Int32
        var padding: Int32 // Add padding to ensure 16-byte alignment
    }
    
    // MARK: - Properties
    
    private let debug: Bool
    private let renderingMode: RenderingMode
    private let maxConcurrentOperations: Int
    private let time: Bool
    private let skip: Bool
    private let logger: Logger
    private let smart: Bool
    private let signposter: OSSignposter
    private let signpostID: OSSignpostID
    private let createPreview: Bool
    private let batchSize: Int
    private let accurate: Bool
    // Metal device and queue
    private let metalDevice: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?
    private var progressG: Progress
    private var progressT: Progress
    private var progressM: Progress
    private var progressHandlerG: ((Double) -> Void)?
    private var progressHandlerT: ((Double) -> Void)?
    private var progressHandlerM: ((Double) -> Void)?
    private var isCancelled: Bool = false
    private var saveAtRoot: Bool = false
    private var separate: Bool = true


    
    // MARK: - Initialization
    
    /// Initializes a new MosaicGenerator instance.
    ///
    /// - Parameters:
    ///   - debug: Enable debug mode for additional logging.
    ///   - renderingMode: The rendering mode to use for mosaic generation.
    ///   - maxConcurrentOperations: Maximum number of concurrent operations.
    ///   - timeStamps: Include timestamps on thumbnails.
    ///   - skip: Skip processing if output file already exists.
    ///   - smart: Enable smart processing (functionality to be implemented).
    ///   - createPreview: Generate a preview animation.
    ///   - batchsize: Number of videos to process in each batch.
    public init(debug: Bool = false, renderingMode: RenderingMode = .auto, maxConcurrentOperations: Int? = nil, timeStamps: Bool = false, skip: Bool = true, smart: Bool = false, createPreview: Bool = false, batchsize: Int = 24, accurate: Bool = false, saveAtRoot: Bool = false, separate: Bool = true) {
        self.debug = debug
        self.renderingMode = renderingMode
        self.time = timeStamps
        self.skip = skip
        self.smart = smart
        self.createPreview = createPreview
        self.logger = Logger(subsystem: "com.fd.MosaicGenerator", category: "MosaicGeneration")
        self.signposter = OSSignposter()
        self.signpostID = signposter.makeSignpostID()
        self.maxConcurrentOperations = maxConcurrentOperations ?? 24
        self.batchSize = batchsize
        self.accurate = accurate
        self.separate = separate
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        self.metalDevice = device
        self.commandQueue = device.makeCommandQueue()!
        self.progressG = Progress(totalUnitCount: 1) // Initialize with 1, we'll update this later
        self.progressT = Progress(totalUnitCount: 1) // Initialize with 1, we'll update this later
        self.progressM = Progress(totalUnitCount: 1) // Initialize with 1, we'll update this later
        self.saveAtRoot = saveAtRoot
        setupPipeline()

        logger.log(level: .info, "MosaicGenerator initialized with debug: \(debug), maxConcurrentOperations: \(self.maxConcurrentOperations), timeStamps: \(timeStamps), skip: \(skip), smart: \(smart), createPreview: \(createPreview), batchSize: \(batchsize), accurate: \(accurate)")
    }
    
    // MARK: - Public Methods
    public func setProgressHandlerG(_ handler: @escaping (Double) -> Void) {
           self.progressHandlerG = handler
       }
    public func setProgressHandlerT(_ handler: @escaping (Double) -> Void) {
           self.progressHandlerT = handler
       }
    public func setProgressHandlerM(_ handler: @escaping (Double) -> Void) {
           self.progressHandlerM = handler
       }
    public func cancelProcessing() {
           isCancelled = true
       }
    public func getProgressSize() -> Double {
        return Double(self.progressG.totalUnitCount)
    }
    public func processIndivFile(videoFile: URL, width: Int, density: String, format: String, overwrite: Bool, preview: Bool, outputDirectory: URL, accurate: Bool) async throws -> URL {
        defer {
            self.progressG.completedUnitCount += 1
            updateProgressG()
        }
        logger.log(level: .info, "Processing file: \(videoFile.standardizedFileURL)")
        let asset = AVURLAsset(url: videoFile)
        let startTime = CFAbsoluteTimeGetCurrent()
        defer {
            let endTime = CFAbsoluteTimeGetCurrent()
            logger.log(level: .info, "Mosaic generation completed in \(String(format: "%.2f", endTime - startTime)) seconds for \(videoFile.standardizedFileURL)")
           // self.progress.completedUnitCount += 1
        }
       
        
        let metadata = try await self.processVideo(file: videoFile, asset: asset)
        
        let mosaicLayout = try await self.mosaicDesign(metadata: metadata, width: width, density: density)
        let thumbnailCount = mosaicLayout.thumbCount
        logger.log(level: .debug, "Extracting thumbnails for \(videoFile.standardizedFileURL)")
        let thumbnailsWithTimestamps = try await self.extractThumbnailsWithTimestamps2(
            from: metadata.file,
            count: thumbnailCount,
            asset: asset,
            thSize: mosaicLayout.thumbnailSize,
            preview: preview,
            accurate: accurate
        )
        let outputSize = CGSize(width: Int(mosaicLayout.cols * Int(mosaicLayout.thumbnailSize.width)), height: Int(mosaicLayout.rows * Int(mosaicLayout.thumbnailSize.height)))
        
        logger.log(level: .debug, "Generating mosaic for \(videoFile.standardizedFileURL)")
        let mosaic = try await withCheckedThrowingContinuation { continuation in
            autoreleasepool {
                do {
                    switch renderingMode {
                    case .auto, .classic:
                        let startTimeC = CFAbsoluteTimeGetCurrent()
                        let result = try self.generateOptMosaicImagebatch(thumbnailsWithTimestamps: thumbnailsWithTimestamps, layout: mosaicLayout, outputSize: outputSize, metadata: metadata)
                        let endTimeC = CFAbsoluteTimeGetCurrent()
                        logger.log(level: .info, "Mosaic generation without metal completed in \(String(format: "%.2f", endTimeC - startTimeC)) seconds for \(videoFile.standardizedFileURL)")
                        continuation.resume(returning: result)
                    case .metal:
                        let startTimeC = CFAbsoluteTimeGetCurrent()
                        let result = self.textureToImage(texture: self.generateOptMosaicImageMetal(thumbnails: thumbnailsWithTimestamps, layout: mosaicLayout, outputSize: outputSize, metadata: metadata))
                        let endTimeC = CFAbsoluteTimeGetCurrent()
                        logger.log(level: .info, "Mosaic composition with metal completed in \(String(format: "%.2f", endTimeC - startTimeC)) seconds for \(videoFile.standardizedFileURL)")
                        continuation.resume(returning: result!)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        var finalOutputDirectory: URL
        if self.separate
        {
            finalOutputDirectory = outputDirectory.appendingPathComponent(metadata.type, isDirectory: true)
        }
        else
        {
            finalOutputDirectory = outputDirectory
        }
        logger.log(level: .debug, "Saving mosaic for \(videoFile.standardizedFileURL)")
       
        return try await self.saveMosaic(
            mosaic: mosaic,
            for: videoFile,
            in: finalOutputDirectory,
            format: format,
            overwrite: overwrite,
            width: width,
            density: density
        )

        
    }
    func updateProgressG() {
               // let currentProgress = Double(progressG.completedUnitCount) / Double(progressG.totalUnitCount)
                DispatchQueue.main.async {
                    self.progressHandlerG?(self.progressG.fractionCompleted)
                }
            }
    @available(macOS 13, *)
    public func processFiles(input: String, width: Int, density: String, format: String, overwrite: Bool, preview: Bool) async throws -> [(video: URL, preview: URL)] {
        isCancelled = false
        let videoFiles = try await getVideoFiles(from: input, width: width)
        progressG.totalUnitCount = Int64(videoFiles.count) + 1
        
        var ReturnedFiles: [(URL,URL)] = []
        let concurrentTaskLimit = self.maxConcurrentOperations
        var activeTasks = 0
        let pct = 100 / Double(videoFiles.count)
        var prog = 0.0
        let startTime = CFAbsoluteTimeGetCurrent()
        
        logger.log(level: .info, "Starting to process \(videoFiles.count) files")
        
        switch preview {
        case false:
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for (videoFile, outputDirectory) in videoFiles {
                        if isCancelled {
                            throw CancellationError()
                        }
                        if activeTasks >= concurrentTaskLimit {
                            self.signposter.emitEvent("waiting for slots to become available for file process")
                            try await group.next()
                            
                            activeTasks -= 1
                        }
                        
                        activeTasks += 1
                        autoreleasepool {
                            group.addTask {
                                do {
                                    if self.isCancelled {
                                        throw CancellationError()
                                    }
                                    
                                    self.signposter.emitEvent("starting file process", id: self.signpostID)
                                    //prog += pct
                                    let returnfile = try await self.processIndivFile(videoFile: videoFile, width: width, density: density, format: format, overwrite: overwrite, preview: preview, outputDirectory: outputDirectory, accurate: self.accurate)
                                    ReturnedFiles.append((videoFile, returnfile))
                                    
                                } catch {
                                    self.logger.error("Failed to process file: \(videoFile.absoluteString), error: \(error.localizedDescription)")
                                }
                            }
                        }
                    }
                    
                    try await group.waitForAll()
                    let outputFolder = videoFiles.first?.1.deletingLastPathComponent() ?? URL(fileURLWithPath: NSTemporaryDirectory())
                    self.logger.log(level: .info, "startingg video summary creation.")
                    let summaryVideoURL = try await createSummaryVideo(from: ReturnedFiles, outputFolder: outputFolder)
                    
                    self.logger.log(level: .info, "All thumbnails processed.")
                }
            }
            catch is CancellationError {
                logger.log(level: .info, "Processing was cancelled")
                throw CancellationError()
            }
            
        case true:
            try await withThrowingTaskGroup(of: Void.self) { group in
                for (videoFile, outputDirectory) in videoFiles {
                    if activeTasks >= concurrentTaskLimit {
                        try await group.next()
                    } else {
                        activeTasks += 1
                        autoreleasepool {
                            group.addTask {
                                do {
                                    prog += pct
                                    let returnfile = try await self.generateAnimatedPreview(for: videoFile, outputDirectory: outputDirectory, density: density)
                                    ReturnedFiles.append((videoFile, returnfile))
                                    activeTasks -= 1
                                } catch {
                                    self.logger.error("Failed to process file: \(videoFile.absoluteString), error: \(error.localizedDescription)")
                                }
                            }
                        }
                    }
                }
                try await group.waitForAll()
                self.logger.log(level: .info, "All thumbnails processed.")
            }
        }
        
        let endTime = CFAbsoluteTimeGetCurrent()
        logger.log(level: .info, "Mosaic generation totally completed in \(String(format: "%.2f", endTime - startTime)) seconds")
        return ReturnedFiles
    }
    
    public func getVideoFilespair(from input: String, width: Int, density: String) async throws -> [(URL, URL)] {
        let inputURL = URL(fileURLWithPath: input)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: input, isDirectory: &isDirectory) else {
            throw MosaicError.inputNotFound
        }
        var result = [(URL, URL)]()
        if isDirectory.boolValue {
            logger.log(level: .debug, "Input is a directory")
            result = try await getVideoFilesFromDirectory(inputURL, width: width)
        } else if inputURL.pathExtension.lowercased() == "m3u8" {
            logger.log(level: .debug, "Input is an m3u8 playlist")
            result = try await getVideoFilesFromPlaylist(inputURL, width: width)
        } else {
            logger.log(level: .debug, "Input is a file")
            guard isVideoFile(inputURL) else {
                throw MosaicError.notAVideoFile
            }
            let outputDirectory = inputURL.deletingLastPathComponent().appendingPathComponent("0th").appendingPathComponent("\(width)")
            result = [(inputURL, outputDirectory)]
        }
        let finalResult = try result.map { inputURL, outputDirectory in
            let outputFile = try findTargetFileName(for: inputURL, in: outputDirectory, format: "heic", density: density)
            return (inputURL, outputFile)
        }
        return finalResult
    }
    public func currentProgress() -> Float {
           return Float(progressG.fractionCompleted)
       }
    
    // MARK: - Private Methods

    private func setupPipeline() {
        guard let library = metalDevice.makeDefaultLibrary() else {
            logger.error("Unable to create default Metal library")
            fatalError("Unable to create default Metal library")
        }
        
        let vertexFunction = library.makeFunction(name: "vertexShader")
        let fragmentFunction = library.makeFunction(name: "fragmentShader")
        
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = 8
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = 16
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        do {
            pipelineState = try metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
            logger.log(level: .debug, "Metal pipeline state created successfully")
        } catch {
            logger.error("Failed to create pipeline state: \(error)")
            fatalError("Failed to create pipeline state: \(error)")
        }
    }

    private func cgImageToTexture(image: CGImage) -> MTLTexture? {
        let textureLoader = MTKTextureLoader(device: metalDevice)
        let options: [MTKTextureLoader.Option : Any] = [
            .SRGB : false,
            .origin : MTKTextureLoader.Origin.bottomLeft
        ]
        
        guard let texture = try? textureLoader.newTexture(cgImage: image, options: options) else {
            logger.error("Failed to create texture from CGImage")
            return nil
        }
        return texture
    }

    private func mosaicDesign(metadata: VideoMetadata, width: Int, density: String) async throws -> (MosaicLayout) {
        let state = signposter.beginInterval("mosaicDesign", id: signpostID)
        defer {
            signposter.endInterval("mosaicDesign", state)
        }
        let thumbnailCount = calculateThumbnailCount(duration: metadata.duration, width: width, density: density)
        
        let thumbnailAspectRatio = metadata.resolution.width / metadata.resolution.height
        return calculateOptimalMosaicLayout(originalAspectRatio: thumbnailAspectRatio, estimatedThumbnailCount: thumbnailCount, mosaicWidth: width)
    }
    
    /// Retrieves video files from the input source.
    public func getVideoFiles(from input: String, width: Int) async throws -> [(URL, URL)] {
        let inputURL = URL(fileURLWithPath: input)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: input, isDirectory: &isDirectory) else {
            throw MosaicError.inputNotFound
        }
        
        if isDirectory.boolValue {
            logger.log(level: .debug, "Input is a directory")
                        return try await getVideoFilesFromDirectory(inputURL, width: width)
                    } else if inputURL.pathExtension.lowercased() == "m3u8" {
                        logger.log(level: .debug, "Input is an m3u8 playlist")
                        return try await getVideoFilesFromPlaylist(inputURL, width: width)
                    } else {
                        logger.log(level: .debug, "Input is a file")
                        guard isVideoFile(inputURL) else {
                            throw MosaicError.notAVideoFile
                        }
                        let outputDirectory = inputURL.deletingLastPathComponent().appendingPathComponent("0th").appendingPathComponent("\(width)")
                        return [(inputURL, outputDirectory)]
                    }
                }
                
                /// Retrieves video files from a directory.
                private func getVideoFilesFromDirectory(_ directory: URL, width: Int) async throws -> [(URL, URL)] {
                    let fileManager = FileManager.default
                    var result = [(URL, URL)]()
                    
                    guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey], options: [.skipsHiddenFiles]) else {
                        throw NSError(domain: "FileManagerError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create directory enumerator"])
                    }
                    
                    while let fileURL = enumerator.nextObject() as? URL {
                        let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
                        
                        if resourceValues.isDirectory == true {
                            continue
                        }
                        var outputDirectory: URL
                        if resourceValues.isRegularFile == true,
                           self.isVideoFile(fileURL),
                           !fileURL.lastPathComponent.lowercased().contains("amprv") {
                            if saveAtRoot{
                                outputDirectory = directory.appendingPathComponent("0th").appendingPathComponent("\(width)")
                            }else
                            {
                               outputDirectory = fileURL.deletingLastPathComponent().appendingPathComponent("0th").appendingPathComponent("\(width)")
                            }
                           
                            result.append((fileURL, outputDirectory))
                        }
                    }
                    
                    logger.log(level: .info, "Found \(result.count) video files in directory: \(directory)")
                    return result
                }
                
                /// Retrieves video files from an m3u8 playlist.
                private func getVideoFilesFromPlaylist(_ playlistURL: URL, width: Int) async throws -> [(URL, URL)] {
                    let videoURLs = try parseM3U8File(at: playlistURL)
                    
                    let playlistName = playlistURL.deletingPathExtension().lastPathComponent
                    let outputFolder = playlistURL.deletingLastPathComponent().appendingPathComponent("Playlist").appendingPathComponent(playlistName)
                    
                    try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true, attributes: nil)
                    
                    logger.log(level: .info, "Parsed \(videoURLs.count) video URLs from playlist: \(playlistURL)")
                    return videoURLs.map { ($0, outputFolder) }
                }
                
                /// Parses an m3u8 file and returns the video URLs.
                private func parseM3U8File(at url: URL) throws -> [URL] {
                    let contents = try String(contentsOf: url)
                    let lines = contents.components(separatedBy: .newlines)
                    
                    return lines.compactMap { line in
                        if !line.hasPrefix("#") && !line.isEmpty {
                            return URL(fileURLWithPath: line)
                        }
                        return nil
                    }
                }
                
                /// Checks if the given URL is a video file.
                private func isVideoFile(_ url: URL) -> Bool {
                    let videoExtensions = ["mp4", "mov", "avi", "mkv", "m4v", "webm", "ts"]
                    return videoExtensions.contains(url.pathExtension.lowercased())
                }
                
                /// Processes video metadata.
                private func processVideo(file: URL, asset: AVAsset) async throws -> VideoMetadata {
                    let state = signposter.beginInterval("analyzing metadata", id: signpostID)
                    defer {
                        signposter.endInterval("analyzing metadata", state)
                    }
                    let tracks = try await asset.loadTracks(withMediaType: .video)
                    guard let track = tracks.first else {
                        throw MosaicError.noVideoTrack
                    }
                    
                    async let durationFuture = asset.load(.duration)
                    async let sizeFuture = track.load(.naturalSize)
                    let duration = try await durationFuture.seconds
                    let size = try await sizeFuture
                    let codec = try await track.mediaFormat
                var type = "M"
                    
                    switch duration {
                    case 0...60:
                        type = "XS"
                    case 60...300:
                        type = "S"
                    case 300...900:
                        type = "M"
                    case 900...1800:
                        type = "L"
                    case 1800...:
                        type = "XL"
                    default:
                        type  = "M"
                    }
                    
                    logger.log(level: .debug, "Processed video metadata for \(file): duration=\(duration), codec=\(codec)")
                    return VideoMetadata(file: file, duration: duration, resolution: size, codec: codec, type: type)
                }

                /// Calculates the number of thumbnails to extract based on video duration and mosaic width.
                private func calculateThumbnailCount(duration: Double, width: Int, density: String) -> Int {
                    let state = signposter.beginInterval("calculateThumbnailCount", id: signpostID)
                    
                    let base = Double(width) / 200.0
                    let k = 10.0
                    let rawCount = base + k * log(duration)
                    
                    let densityFactor: Double
                    switch density.lowercased() {
                    case "xxs": densityFactor = 0.25
                    case "xs": densityFactor = 0.5
                    case "s": densityFactor = 1.0
                    case "m": densityFactor = 1.5
                    case "l": densityFactor = 2.0
                    case "xl": densityFactor = 4.0
                    case "xxl": densityFactor = 8.0
                    default: densityFactor = 1.0
                    }
                    
                    signposter.endInterval("calculateThumbnailCount", state)
                    
                    if duration < 5 {
                        return 4
                    }
                    let totalCount = Int(rawCount / densityFactor)
                    logger.log(level: .debug, "Calculated thumbnail count: \(totalCount) for duration: \(duration), width: \(width), density: \(density)")
                    return min(totalCount, 800)
                }
                
                private func generateAnimatedPreview(for videoFile: URL, outputDirectory: URL, density: String) async throws -> URL {
                    logger.log(level: .debug, "Generating animated preview for \(videoFile.lastPathComponent)")
                    let asset = AVURLAsset(url: videoFile)
                    let duration = try await asset.load(.duration).seconds
                    var previewDuration = Double(60)
                    let densityFactor: Double
                    switch density.lowercased() {
                    case "xxs": densityFactor = 0.25
                    case "xs": densityFactor = 0.5
                    case "s": densityFactor = 1.0
                    case "m": densityFactor = 1.5
                    case "l": densityFactor = 2.0
                    case "xl": densityFactor = 4.0
                    default: densityFactor = 1.0
                    }
                    
                    let extractsPerMinute: Double
                    if duration < 300 { // Less than 5 minutes
                        extractsPerMinute = 8 / densityFactor
                        previewDuration = Double(30)
                    } else if duration < 1200 { // Less than 20 minutes
                        extractsPerMinute = 3 / densityFactor
                        previewDuration = Double(60)
                    } else {
                        extractsPerMinute = 0.5 / densityFactor
                        previewDuration = Double(90)
                    }
                    let extractCount = Int(ceil(duration / 60 * extractsPerMinute))
                    let extractDuration = min(previewDuration / Double(extractCount), duration / Double(extractCount))
                    logger.log(level: .debug, "Generating \(extractCount) extracts of \(extractDuration) seconds each for preview animation")
                    
                    let previewDirectory = outputDirectory.deletingLastPathComponent().appendingPathComponent("amprv", isDirectory: true)
                    try FileManager.default.createDirectory(at: previewDirectory, withIntermediateDirectories: true, attributes: nil)
                    var previewURL = previewDirectory.appendingPathComponent("\(videoFile.deletingPathExtension().lastPathComponent)-amprv-\(density).mp4")
                    if FileManager.default.fileExists(atPath: previewURL.path) {
                        try FileManager.default.removeItem(at: previewURL)
                        logger.log(level: .info, "Existing preview file removed: \(previewURL.path)")
                    }
                    
                    // Create a composition
                    let composition = AVMutableComposition()
                    guard let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
                          let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                        throw MosaicError.unableToCreateCompositionTracks
                    }
                    
                    // Get the original video and audio tracks
                    guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first,
                          let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
                        throw MosaicError.noVideoOrAudioTrack
                    }
                    
                    // Get the original video's framerate
                    let originalFrameRate = try await videoTrack.load(.nominalFrameRate)
                    
                    var currentTime = CMTime.zero
                    
                    // Create video composition for fade transitions
                    var instructions = [AVMutableVideoCompositionInstruction]()
                    let timescale: CMTimeScale = 600

                    let fastPlaybackDuration = CMTime(seconds: extractDuration/2, preferredTimescale: timescale)
                    for i in 0..<extractCount {
                        let startTime = CMTime(seconds: Double(i) * (duration - extractDuration) / Double(extractCount - 1), preferredTimescale: timescale)
                        let durationCMTime = CMTime(seconds: extractDuration, preferredTimescale: timescale)
                        
                        do {
                            // Insert video segment
                            try await compositionVideoTrack.insertTimeRange(CMTimeRange(start: startTime, duration: durationCMTime),
                                                                            of: videoTrack,
                                                                            at: currentTime)
                            
                            try await compositionAudioTrack.insertTimeRange(CMTimeRange(start: startTime, duration: durationCMTime),
                                                                            of: audioTrack,
                                                                            at: currentTime)
                            
                            // Scale the inserted segments to play faster
                            let timeRange = CMTimeRange(start: currentTime, duration: durationCMTime)
                            try compositionVideoTrack.scaleTimeRange(timeRange, toDuration: fastPlaybackDuration)
                            try compositionAudioTrack.scaleTimeRange(timeRange, toDuration: fastPlaybackDuration)

                            logger.log(level: .debug, "Extracted segment \(i+1) of \(extractCount) for \(videoFile.lastPathComponent)")
                            
                            currentTime = CMTimeAdd(currentTime, fastPlaybackDuration)
                        } catch {
                            logger.error("Failed to insert or scale time range: \(error.localizedDescription)")
                        }
                    }
                    
                    logger.log(level: .debug, "Starting export for \(videoFile.lastPathComponent)")
                    guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
                        throw MosaicError.unableToCreateExportSession
                    }
                    let videoComposition = AVMutableVideoComposition(propertiesOf: composition)
                    videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(originalFrameRate * 2))
                    let audioMix = AVMutableAudioMix()
                    let audioParameters = AVMutableAudioMixInputParameters(track: compositionAudioTrack)
                    
                    exportSession.outputFileType = .mp4
                    exportSession.shouldOptimizeForNetworkUse = false
                    exportSession.videoComposition = videoComposition
                    exportSession.allowsParallelizedExport = true
                    exportSession.directoryForTemporaryFiles = FileManager.default.temporaryDirectory
                    audioMix.inputParameters = [audioParameters]
                    exportSession.audioMix = audioMix
                    
                    try await exportVid(for: exportSession, previewURL: previewURL)
                    return previewURL
                }
                
                private func exportVid(for exportSession: AVAssetExportSession, previewURL: URL) async throws {
                    exportSession.outputURL = previewURL
                    let startTime = CFAbsoluteTimeGetCurrent()
                    // Perform the export
                    exportSession.allowsParallelizedExport = true
                    try await exportSession.export(to: previewURL, as: .mp4)
                    let endTime = CFAbsoluteTimeGetCurrent()
                    logger.log(level: .debug, "Finished export in \(String(format: "%.2f", endTime - startTime)) seconds")
                }
                 
                /// Calculates the optimal layout for the mosaic based on the original aspect ratio and estimated thumbnail count.
                func calculateOptimalMosaicLayout(originalAspectRatio: CGFloat,
                                                  estimatedThumbnailCount: Int,
                                                  mosaicWidth: Int) -> MosaicLayout {
                    var count = estimatedThumbnailCount
                    let state = signposter.beginInterval("calculateOptimalMosaicLayout", id: signpostID)
                    defer {
                        signposter.endInterval("calculateOptimalMosaicLayout", state)
                    }
                    let mosaicAspectRatio: CGFloat = 16.0 / 9.0
                    let mosaicHeight = Int(CGFloat(mosaicWidth) / mosaicAspectRatio)
                    
                    func calculateLayout(rows: Int) -> MosaicLayout {
                        let cols = Int(ceil(Double(count) / Double(rows)))
                        
                        let thumbnailWidth = CGFloat(mosaicWidth) / CGFloat(cols)
                        let thumbnailHeight = thumbnailWidth / originalAspectRatio
                        
                        let adjustedRows = min(rows, Int(ceil(CGFloat(mosaicHeight) / thumbnailHeight)))
                        
                        var positions: [(x: Int, y: Int)] = []
                        for row in 0..<adjustedRows {
                            for col in 0..<cols {
                                if positions.count < count {
                                    positions.append((x: col, y: row))
                                } else {
                                    break
                                }
                            }
                        }
                        return MosaicLayout(
                            rows: adjustedRows,
                            cols: cols,
                            thumbnailSize: CGSize(width: thumbnailWidth, height: thumbnailHeight),
                            positions: positions,
                            thumbCount: count
                        )
                    }
                    
                    var bestLayout = calculateLayout(rows: Int(sqrt(Double(estimatedThumbnailCount))))
                    var bestScore = Double.infinity
                    
                    for rows in 1...estimatedThumbnailCount {
                        let layout = calculateLayout(rows: rows)
                        
                        let fillRatio = (CGFloat(layout.rows) * layout.thumbnailSize.height) / CGFloat(mosaicHeight)
                        let thumbnailCount = layout.positions.count
                        let countDifference = abs(thumbnailCount - estimatedThumbnailCount)
                        
                        let score = (1 - fillRatio) + Double(countDifference) / Double(estimatedThumbnailCount)
                        
                        if score < bestScore {
                            bestScore = score
                            bestLayout = layout
                        }
                        
                        if CGFloat(layout.rows) * layout.thumbnailSize.height > CGFloat(mosaicHeight) {
                                        break
                                    }
                                }
                                count = bestLayout.rows * bestLayout.cols
                                
                                logger.log(level: .debug, "Optimal mosaic layout calculated: rows=\(bestLayout.rows), cols=\(bestLayout.cols), totalThumbnails=\(count)")
                                return calculateLayout(rows: bestLayout.rows)
                            }

                            @available(macOS 13, *)
                            func extractThumbnailsWithTimestamps2(from file: URL, count: Int, asset: AVAsset, thSize: CGSize, preview: Bool, accurate: Bool) async throws -> [(image: CGImage, timestamp: String)] {
                                let state = signposter.beginInterval("extractThumbnailsWithTimestamps2", id: signpostID)
                                defer {
                                    signposter.endInterval("extractThumbnailsWithTimestamps2", state)
                                }
                                
                                logger.log(level: .debug, "Starting thumbnail extraction for \(file.lastPathComponent): count=\(count), preview=\(preview), accurate=\(accurate)")
                                
                                let startTime = CFAbsoluteTimeGetCurrent()
                                let duration = try await asset.load(.duration).seconds
                                let generator = AVAssetImageGenerator(asset: asset)
                                generator.appliesPreferredTrackTransform = true
                                if (accurate) {
                                    generator.requestedTimeToleranceBefore = CMTime(seconds: 0, preferredTimescale: 600)
                                    generator.requestedTimeToleranceAfter = CMTime(seconds: 0, preferredTimescale: 600)
                                } else {
                                    generator.requestedTimeToleranceBefore = CMTime(seconds: 2, preferredTimescale: 600)
                                    generator.requestedTimeToleranceAfter = CMTime(seconds: 2, preferredTimescale: 600)
                                }
                                if !preview {
                                    generator.maximumSize = thSize
                                }
                                let step = duration / Double(count)
                                let times = stride(from: 0, to: duration, by: step).map {
                                    CMTime(seconds: $0, preferredTimescale: 600)
                                }
                                var thumbnailsWithTimestamps: [(Int, CGImage, String)] = []
                                var index = 0
                                var failedCount = 0

                                for await result in generator.images(for: times) {
                                    switch result {
                                    case .success(requestedTime: _, image: let image, actualTime: let actual):
                                        signposter.emitEvent("Image extracted")
                                        thumbnailsWithTimestamps.append((index, image, self.formatTimestamp(seconds: actual.seconds)))
                                        index += 1
                                    case .failure(requestedTime: _, error: let error):
                                        self.logger.error("Thumbnail extraction failed for \(file.lastPathComponent): \(error.localizedDescription)")
                                        failedCount += 1
                                    }
                                }
                                    
                                if failedCount > 0 {
                                    self.logger.warning("Partial failure in thumbnail extraction: \(thumbnailsWithTimestamps.count) successful, \(failedCount) failed")
                                    if thumbnailsWithTimestamps.isEmpty {
                                        throw ThumbnailExtractionError.partialFailure(successfulCount: thumbnailsWithTimestamps.count, failedCount: failedCount)
                                    }
                                }

                                let endTime = CFAbsoluteTimeGetCurrent()
                                let elapsedTime = endTime - startTime
                                logger.log(level: .debug, "Thumbnail extraction completed for \(file.lastPathComponent): extracted=\(thumbnailsWithTimestamps.count), failed=\(failedCount), time=\(elapsedTime) seconds")
                                
                                return thumbnailsWithTimestamps
                                        .sorted { $0.0 < $1.0 }
                                        .map { ($0.1, $0.2) }
                            }

                            /// Formats a timestamp in seconds to a string representation.
                            private func formatTimestamp(seconds: Double) -> String {
                                let hours = Int(seconds) / 3600
                                let minutes = (Int(seconds) % 3600) / 60
                                let seconds = Int(seconds) % 60
                                return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
                            }
                            
                            /// Generates the mosaic image from the extracted thumbnails.
                            private func generateOptMosaicImagebatch(thumbnailsWithTimestamps: [(image: CGImage, timestamp: String)],
                                                                     layout: MosaicLayout,
                                                                     outputSize: CGSize,
                                                                     metadata: VideoMetadata) throws -> CGImage {
                                let state = signposter.beginInterval("generateOptMosaicImagebatch", id: signpostID)
                                defer {
                                    signposter.endInterval("generateOptMosaicImagebatch", state)
                                }
                                
                                let width = Int(outputSize.width)
                                let height = Int(outputSize.height)
                                let thumbnailWidth = Int(layout.thumbnailSize.width)
                                let thumbnailHeight = Int(layout.thumbnailSize.height)
                                
                                guard let context = CGContext(data: nil,
                                                              width: width,
                                                              height: height,
                                                              bitsPerComponent: 8,
                                                              bytesPerRow: 0,
                                                              space: CGColorSpaceCreateDeviceRGB(),
                                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                                    logger.error("Unable to create CGContext for mosaic generation")
                                    throw MosaicError.unableToCreateContext
                                }
                                
                                // Fill background
                                context.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0))
                                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                                
                                // Draw thumbnails
                                for (index, (thumbnail, timestamp)) in thumbnailsWithTimestamps.enumerated() {
                                    guard index < layout.positions.count else { break }
                                    
                                    let position = layout.positions[index]
                                    let x = Int(CGFloat(position.x) * layout.thumbnailSize.width)
                                    let y = height - Int(CGFloat(position.y + 1) * layout.thumbnailSize.height)
                                    context.draw(thumbnail, in: CGRect(x: x, y: y, width: thumbnailWidth, height: thumbnailHeight))
                                    
                                    if self.time {
                                        drawTimestamp(context: context, timestamp: timestamp, x: x, y: y, width: thumbnailWidth, height: thumbnailHeight)
                                    }
                                }
                                
                                // Draw metadata
                                drawMetadata(context: context, metadata: metadata, width: width, height: height)
                                
                                guard let outputImage = context.makeImage() else {
                                    logger.error("Unable to generate mosaic image")
                                    throw MosaicError.unableToGenerateMosaic
                                }
                                
                                logger.log(level: .debug, "Mosaic image generated successfully")
                                return outputImage
                            }

                            /// Draws a timestamp on a thumbnail.
                            private func drawTimestamp(context: CGContext, timestamp: String, x: Int, y: Int, width: Int, height: Int) {
                                let fontSize = CGFloat(height) / 6 / 1.618
                                let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
                                
                                let attributes: [NSAttributedString.Key: Any] = [
                                    .font: font,
                                    .foregroundColor: NSColor.white.cgColor
                                ]
                                
                                let attributedTimestamp = CFAttributedStringCreate(nil, timestamp as CFString, attributes as CFDictionary)
                                let line = CTLineCreateWithAttributedString(attributedTimestamp!)
                                
                                context.saveGState()
                                context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.5))
                                let textRect = CGRect(x: x, y: y, width: width, height: Int(CGFloat(height) / 6))
                                context.fill(textRect)
                                
                                let textWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
                                let textPosition = CGPoint(x: x + width - Int(textWidth) - 5, y: y + 5)
                                
                                context.textPosition = textPosition
                                CTLineDraw(line, context)
                                context.restoreGState()
                            }

                            /// Draws metadata on the mosaic image.
                            private func drawMetadata(context: CGContext, metadata: VideoMetadata, width: Int, height: Int) {
                                let metadataHeight = Int(round(Double(height) * 0.1))
                                let lineHeight = metadataHeight / 4
                                let fontSize = round(Double(lineHeight) / 1.618)
                                let duree = formatTimestamp(seconds: metadata.duration)
                                context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 0.2))
                                context.fill(CGRect(x: 0, y: height - metadataHeight, width: width, height: metadataHeight))
                                
                                let metadataText = """
                                File: \(metadata.file.standardizedFileURL.standardizedFileURL)
                                Codec: \(metadata.codec)
                                Resolution: \(Int(metadata.resolution.width))x\(Int(metadata.resolution.height))
                                Duration: \(duree)
                                """
                                let attributes: [NSAttributedString.Key: Any] = [
                                    .font: CTFontCreateWithName("Helvetica" as CFString, fontSize, nil),
                                    .foregroundColor: NSColor.white.cgColor
                                ]
                                
                                let attributedString = NSAttributedString(string: metadataText, attributes: attributes)
                                let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
                                
                                let rect = CGRect(x: 10, y: height - metadataHeight + 10, width: width - 20, height: metadataHeight - 20)
                                let path = CGPath(rect: rect, transform: nil)
                                
                                let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
                                
                                context.saveGState()
                                CTFrameDraw(frame, context)
                                context.restoreGState()
                            }

                            /// Generates an output file name for the mosaic image.
                            private func getOutputFileName(for videoFile: URL, in directory: URL, format: String, overwrite: Bool, density: String) throws -> String {
                                let baseName = videoFile.deletingPathExtension().lastPathComponent
                                let fileExtension = format.lowercased()
                                var version = 1
                                var fileName = "\(baseName)-\(density).\(fileExtension)"
                                
                                while FileManager.default.fileExists(atPath: directory.appendingPathComponent(fileName).path) {
                                    if overwrite {
                                        try FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
                                        break
                                    }
                                    version += 1
                                    fileName = "\(baseName)_v\(version).\(fileExtension)"
                                }
                                return fileName
                            }

                            public func findTargetFileName(for videoFile: URL, in directory: URL, format: String, density: String) throws -> URL {
                                let baseName = videoFile.deletingPathExtension().lastPathComponent
                                let fileExtension = format.lowercased()
                                var version = 1
                                var fileName = "\(baseName)-\(density).\(fileExtension)"
                                if FileManager.default.fileExists(atPath: directory.appendingPathComponent(fileName).path) {
                                   return directory.appendingPathComponent(fileName)
                                }
                                else {
                                    version += 1
                                    fileName = "\(baseName)_v\(version).\(fileExtension)"
                                    while !FileManager.default.fileExists(atPath: directory.appendingPathComponent(fileName).path) {
                                        version += 1
                                        fileName = "\(baseName)_v\(version).\(fileExtension)"
                                    }
                                    return directory.appendingPathComponent(fileName)
                                }
                            }
                            
                            /// Saves the generated mosaic image to disk.
                            private func saveMosaic(mosaic: CGImage, for videoFile: URL, in outputDirectory: URL, format: String, overwrite: Bool, width: Int, density: String) async throws -> URL {
                                let state = signposter.beginInterval("saveMosaic", id: signpostID)
                                defer {
                                    signposter.endInterval("saveMosaic", state)
                                }
                                
                                // Ensure output directory exists
                                try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true, attributes: nil)
                                
                                // Get the file name for the output image
                                let fileName = try getOutputFileName(for: videoFile, in: outputDirectory, format: format, overwrite: overwrite, density: density)
                                let outputURL = outputDirectory.appendingPathComponent(fileName)
                                
                                // Handle saving the image as HEIC if the format is HEIC
                                if format.lowercased() == "heic" {
                                    try await saveMosaicAsHEIC(mosaic, to: outputURL)
                                } else {
                                    // Use existing image saving logic for other formats
                                    try await saveMosaicImage(mosaic, to: outputURL, format: format)
                                }
                                logger.log(level: .info, "Mosaic saved: \(outputURL.path)")
                                return outputURL
                            }
                            
                            /// Saves the mosaic image in HEIC format.
                            private func saveMosaicAsHEIC(_ mosaic: CGImage, to outputURL: URL) async throws {
                                guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, AVFileType.heic as CFString, 1, nil) else {
                                    throw NSError(domain: "HEICError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create HEIC destination"])
                                }

                                // Create the compression options
                                let options: [String: Any] = [
                                    kCGImageDestinationLossyCompressionQuality as String: 0.2 // Compression quality (0.0 to 1.0)
                                ]

                                // Add the mosaic image to the destination and finalize the save
                                CGImageDestinationAddImage(destination, mosaic, options as CFDictionary?)
                                if !CGImageDestinationFinalize(destination) {
                                    throw NSError(domain: "HEICError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize HEIC image save"])
                                }
                            }

                            /// Saves the mosaic image to a file with the specified format.
                            private func saveMosaicImage(_ image: CGImage, to url: URL, format: String) async throws {
                                let data: Data
                                switch format.lowercased() {
                                case "jpeg", "jpg":
                                    guard let imageData = image.jpegData(compressionQuality: 0.4) else {
                                        throw MosaicError.unableToSaveMosaic
                                    }
                                    data = imageData
                                case "png":
                                    guard let imageData = image.pngData() else {
                                        throw MosaicError.unableToSaveMosaic
                                    }
                                    data = imageData
                                default:
                                    throw MosaicError.unsupportedOutputFormat
                                }
                                
                                try data.write(to: url)
                            }

                            // MARK: - Metal Functions
                            
                            private func generateOptMosaicImageMetal(thumbnails: [(image: CGImage, timestamp: String)],
                                                                     layout: MosaicLayout,
                                                                     outputSize: CGSize,
                                                                     metadata: VideoMetadata) -> MTLTexture {
                                let state = signposter.beginInterval("generateOptMosaicImageMetal", id: signpostID)
                                        defer { signposter.endInterval("generateOptMosaicImageMetal", state) }
                                        
                                        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                                                                  width: Int(outputSize.width),
                                                                                                  height: Int(outputSize.height),
                                                                                                  mipmapped: false)
                                        descriptor.usage = [.renderTarget, .shaderRead]
                                        
                                        guard let mosaicTexture = metalDevice.makeTexture(descriptor: descriptor),
                                              let commandBuffer = commandQueue.makeCommandBuffer(),
                                              let renderPassDescriptor = self.makeRenderPassDescriptor(texture: mosaicTexture) else {
                                            logger.error("Failed to create Metal texture or command buffer")
                                            fatalError("Failed to create Metal texture or command buffer")
                                        }

                                        let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
                                        commandEncoder.setRenderPipelineState(pipelineState!)
                                        
                                        let vertices: [Float] = [
                                            -1.0, -1.0, 0.0, 1.0,
                                             1.0, -1.0, 1.0, 1.0,
                                            -1.0,  1.0, 0.0, 0.0,
                                             1.0,  1.0, 1.0, 0.0
                                        ]
                                        let vertexBuffer = metalDevice.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<Float>.stride, options: [])
                                        commandEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
                                        
                                        // Draw background
                                        var backgroundUniforms = Uniforms(position: SIMD2<Float>(0, 0), size: SIMD2<Float>(1, 1), renderType: 0, padding: 0)
                                        commandEncoder.setVertexBytes(&backgroundUniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                                        commandEncoder.setFragmentBytes(&backgroundUniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                                        var backgroundColor = SIMD4<Float>(0.1, 0.1, 0.1, 1.0) // Dark gray background
                                        commandEncoder.setFragmentBytes(&backgroundColor, length: MemoryLayout<SIMD4<Float>>.stride, index: 2)
                                        commandEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                                        
                                        // Draw thumbnails
                                        for (index, thumbnail) in thumbnails.enumerated().reversed() {
                                            guard index < layout.positions.count else { break }
                                            let position = layout.positions[index]
                                            let thumbnailTexture = cgImageToTexture(image: thumbnail.image)!
                                            
                                            let x = Float(position.x) * Float(layout.thumbnailSize.width) / Float(outputSize.width) * 2 - 1
                                            let y = 1 - (Float(position.y + 1) * Float(layout.thumbnailSize.height) / Float(outputSize.height) * 2)
                                            let width = Float(layout.thumbnailSize.width) / Float(outputSize.width)
                                            let height = Float(layout.thumbnailSize.height) / Float(outputSize.height)
                                            
                                            var uniforms = Uniforms(position: SIMD2<Float>(x, y), size: SIMD2<Float>(width, height), renderType: 1, padding: 0)
                                            commandEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                                            commandEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                                            commandEncoder.setFragmentTexture(thumbnailTexture, index: 0)
                                            commandEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                                            
                                            if self.time {
                                                drawTimestamp(commandEncoder: commandEncoder, timestamp: thumbnail.timestamp, x: x, y: y, width: width, height: height)
                                            }
                                        }
                                        
                                        // Draw metadata
                                        let metadataHeight = Float(round(Double(outputSize.height) * 0.1))
                                        let metadataY = 1 - (metadataHeight / Float(outputSize.height)) * 2
                                        var metadataUniforms = Uniforms(position: SIMD2<Float>(-1, metadataY),
                                                                        size: SIMD2<Float>(2, (metadataHeight / Float(outputSize.height)) * 2),
                                                                        renderType: 2,
                                                                        padding: 0)
                                        commandEncoder.setVertexBytes(&metadataUniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                                        commandEncoder.setFragmentBytes(&metadataUniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                                        
                                        if let metadataTexture = createMetadataTexture(metadata: metadata, width: Int(outputSize.width), height: Int(metadataHeight)) {
                                            commandEncoder.setFragmentTexture(metadataTexture, index: 0)
                                            commandEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                                        } else {
                                            logger.warning("Failed to create metadata texture, skipping metadata rendering")
                                        }

                                        commandEncoder.endEncoding()
                                        commandBuffer.commit()
                                        commandBuffer.waitUntilCompleted()

                                        return mosaicTexture
                                    }

                                    private func drawTimestamp(commandEncoder: MTLRenderCommandEncoder, timestamp: String, x: Float, y: Float, width: Float, height: Float) {
                                        // Implementation for drawing timestamp using Metal
                                        // This might involve creating a texture from the timestamp text and rendering it
                                        // For simplicity, we'll skip the actual implementation here
                                        logger.log(level: .debug, "Drawing timestamp: \(timestamp) at position: (\(x), \(y))")
                                    }

                                    private func createMetadataTexture(metadata: VideoMetadata, width: Int, height: Int) -> MTLTexture? {
                                        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
                                        let bytesPerPixel = 4
                                        let bytesPerRow = width * bytesPerPixel
                                        
                                        guard let context = CGContext(data: nil,
                                                                      width: width,
                                                                      height: height,
                                                                      bitsPerComponent: 8,
                                                                      bytesPerRow: bytesPerRow,
                                                                      space: CGColorSpaceCreateDeviceRGB(),
                                                                      bitmapInfo: bitmapInfo.rawValue) else {
                                            logger.error("Failed to create CGContext for metadata texture")
                                            return createFallbackTexture(width: width, height: height)
                                        }
                                        
                                        // Fill background
                                        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 0.2))
                                        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                                        
                                        // Prepare text attributes
                                        let font = NSFont.systemFont(ofSize: CGFloat(height) / 6 / 1.618)
                                        let paragraphStyle = NSMutableParagraphStyle()
                                        paragraphStyle.alignment = .left
                                        let attributes: [NSAttributedString.Key: Any] = [
                                            .font: font,
                                            .foregroundColor: NSColor.black,
                                            .paragraphStyle: paragraphStyle
                                        ]
                                        
                                        // Format metadata text
                                        let duree = formatTimestamp(seconds: metadata.duration)
                                        let metadataText = """
                                        File: \(metadata.file.standardizedFileURL.lastPathComponent)
                                        Codec: \(metadata.codec)
                                        Resolution: \(Int(metadata.resolution.width))x\(Int(metadata.resolution.height))
                                        Duration: \(duree)
                                        """
                                        
                                        // Draw text
                                        let textRect = CGRect(x: 10, y: 10, width: width - 20, height: height - 20)
                                        metadataText.draw(in: textRect, withAttributes: attributes)
                                        
                                        // Get the raw bitmap data
                                        guard let bitmapData = context.data else {
                                            logger.error("Failed to get bitmap data for metadata texture")
                                            return createFallbackTexture(width: width, height: height)
                                        }
                                        
                                        // Create the texture descriptor
                                        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                                            pixelFormat: .bgra8Unorm,
                                            width: width,
                                            height: height,
                                            mipmapped: false
                                        )
                                        textureDescriptor.usage = [.shaderRead]
                                        
                                        // Create the texture
                                        guard let texture = metalDevice.makeTexture(descriptor: textureDescriptor) else {
                                            logger.error("Failed to create metadata texture")
                                            return createFallbackTexture(width: width, height: height)
                                        }
                                        
                                        // Copy the bitmap data to the texture
                                        let region = MTLRegionMake2D(0, 0, width, height)
                                        texture.replace(region: region, mipmapLevel: 0, withBytes: bitmapData, bytesPerRow: bytesPerRow)
                                        
                                        logger.log(level: .debug, "Metadata texture created successfully")
                                        return texture
                                    }

                                    private func createFallbackTexture(width: Int, height: Int) -> MTLTexture? {
                                        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                                                                  width: width,
                                                                                                  height: height,
                                                                                                  mipmapped: false)
                                        descriptor.usage = [.shaderRead, .renderTarget]
                                        
                                        guard let texture = metalDevice.makeTexture(descriptor: descriptor) else {
                                            logger.error("Failed to create fallback texture")
                                            return nil
                                        }
                                        
                                        let region = MTLRegionMake2D(0, 0, width, height)
                                        let color: [UInt8] = [0, 0, 255, 51] // BGRA: semi-transparent blue
                                        let rowBytes = 4 * width
                                        
                                        texture.replace(region: region, mipmapLevel: 0, withBytes: color, bytesPerRow: rowBytes)
                                        
                                        logger.log(level: .debug, "Fallback texture created successfully")
                                        return texture
                                    }

                                    private func makeRenderPassDescriptor(texture: MTLTexture) -> MTLRenderPassDescriptor? {
                                        let renderPassDescriptor = MTLRenderPassDescriptor()
                                        renderPassDescriptor.colorAttachments[0].texture = texture
                                        renderPassDescriptor.colorAttachments[0].loadAction = .clear
                                        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
                                        renderPassDescriptor.colorAttachments[0].storeAction = .store
                                        return renderPassDescriptor
                                    }

                                    func textureToImage(texture: MTLTexture) -> CGImage? {
                                        let width = texture.width
                                        let height = texture.height
                                        let rowBytes = width * 4
                                        
                                        var imageBytes = [UInt8](repeating: 0, count: rowBytes * height)
                                        let region = MTLRegionMake2D(0, 0, width, height)
                                        
                                        texture.getBytes(&imageBytes, bytesPerRow: rowBytes, from: region, mipmapLevel: 0)
                                        
                                        let provider = CGDataProvider(data: NSData(bytes: &imageBytes, length: imageBytes.count))
                                        let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue))
                                        let colorSpace = CGColorSpaceCreateDeviceRGB()
                                        
                                        guard let cgImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes, space: colorSpace, bitmapInfo: bitmapInfo, provider: provider!, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
                                            logger.error("Failed to convert texture to CGImage")
                                            return nil
                                        }
                                        
                                        logger.log(level: .debug, "Texture successfully converted to CGImage")
                                        return cgImage
                                    }
    public func createSummaryVideo(from returnedFiles: [(video: URL, preview: URL)], outputFolder: URL) async throws -> URL {
        defer {
            self.progressG.completedUnitCount += 1
            updateProgressG()
        }
        let startTime = CFAbsoluteTimeGetCurrent()
        defer {
            let endTime = CFAbsoluteTimeGetCurrent()
            logger.log(level: .info, "createSummaryVideo \(String(format: "%.2f", endTime - startTime)) sec")
        }
        let dateFormatter = DateFormatter()
           dateFormatter.dateFormat = "yyyyMMddHHmm"
           let timestamp = dateFormatter.string(from: Date())
           let outputURL = outputFolder.appendingPathComponent("\(timestamp)-amprv.mp4")
           
           let fps: Float = 1.0
           let frameInterval = CMTime(seconds: 1.0 / Double(fps), preferredTimescale: 600)
           
           // Set up the video writer
           let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
               AVVideoWidthKey: 1920,
               AVVideoHeightKey: 1080
           ]
           
           guard let assetWriter = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
               throw NSError(domain: "VideoCreationError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unable to create asset writer."])
           }
           
           let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
           let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerInput, sourcePixelBufferAttributes: nil)
           
           assetWriter.add(writerInput)
           
           guard assetWriter.startWriting() else {
               throw NSError(domain: "VideoCreationError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to start writing."])
           }
           
           assetWriter.startSession(atSourceTime: .zero)
           
           var frameCount = 0
           
           for (_, previewURL) in returnedFiles {
               guard let image = CIImage(contentsOf: previewURL) else { continue }
               
               let scaledImage = image.transformed(by: CGAffineTransform(scaleX: 1920 / image.extent.width, y: 1080 / image.extent.height))
               
               guard let pixelBuffer = try? await createPixelBuffer(from: scaledImage) else { continue }
               
               while !writerInput.isReadyForMoreMediaData {
                   await Task.sleep(10_000_000) // 10 milliseconds
               }
               
               let frameTime = CMTime(value: CMTimeValue(frameCount), timescale: CMTimeScale(fps))
               adaptor.append(pixelBuffer, withPresentationTime: frameTime)
               
               frameCount += 1
           }
           
           writerInput.markAsFinished()
           await assetWriter.finishWriting()
           
           logger.info("Summary video created at: \(outputURL.path)")
           return outputURL
       }
       
       private func createPixelBuffer(from ciImage: CIImage) async throws -> CVPixelBuffer {
           let attributes: [String: Any] = [
               kCVPixelBufferCGImageCompatibilityKey as String: true,
               kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
           ]
           var pixelBuffer: CVPixelBuffer?
           let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                            Int(ciImage.extent.width),
                                            Int(ciImage.extent.height),
                                            kCVPixelFormatType_32ARGB,
                                            attributes as CFDictionary,
                                            &pixelBuffer)
           
           guard status == kCVReturnSuccess, let unwrappedPixelBuffer = pixelBuffer else {
               throw NSError(domain: "PixelBufferError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unable to create pixel buffer."])
           }
           
           let context = CIContext()
           try await context.render(ciImage, to: unwrappedPixelBuffer)
           
           return unwrappedPixelBuffer
       }
}

