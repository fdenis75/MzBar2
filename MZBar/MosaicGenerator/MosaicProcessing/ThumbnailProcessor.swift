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
import Vision

struct Frame {
    /// The timestamp of the frame.
    let time: CMTime
    /// The score of the frame.
    let score: Float
    /// The feature-print observation of the frame.
    let observation: FeaturePrintObservation
}

class Thumbnail: Identifiable {
    /// The image that captures from the video frame.
    let image: CGImage


    /// The frame that the thumbnail represents.
    let frame: Frame
    init(image: CGImage, frame: Frame) {
        self.image = image
        self.frame = frame
    }

    // ...
}


/// Handles thumbnail extraction and timestamp generation
public final class ThumbnailProcessor: ThumbnailExtraction {
    private let logger = Logger(subsystem: "com.mosaic.processing", category: "ThumbnailProcessor")
    private let config: MosaicGeneratorConfig
    private let signposter = OSSignposter(logHandle: .mosaic)

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
    /// Extract thumbnails from video with timestamps
    /// - Parameters:
    ///   - file: Video file URL
    ///   - layout: Layout information for the mosaic
    ///   - asset: Video asset to extract thumbnails from
    ///   - preview: Whether generating preview thumbnails
    ///   - accurate: Whether to use accurate timestamp extraction
    /// - Returns: Array of tuples containing thumbnail images and their timestamps. If thumbnail extraction fails for any frame, 
    ///           a blank image will be used as a fallback.
    public func extractThumbnails(
        from file: URL,
        layout: MosaicLayout,
        asset: AVAsset,
        preview: Bool,
        accurate: Bool
    ) async throws -> [(image: CGImage, timestamp: String)] {
        logger.info("Starting thumbnail extraction: \(file.lastPathComponent)")
        let state = signposter.beginInterval("etxract Thumbs")
        defer{
            signposter.endInterval("etxract Thumbs", state)
        }
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
                // Create a blank image to replace the failed thumbnail
                if let blankImage = createBlankImage(size: layout.thumbnailSize) {
                    thumbnails.append((thumbnails.count, blankImage, "00:00:00"))
                }
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
     
       public func processVideo(for videoURL: URL,  layout: MosaicLayout,
                          asset: AVAsset,
                          preview: Bool,
                          accurate: Bool ) async throws -> [(image: CGImage, timestamp: String)]  {
            /// The instance of the `VideoProcessor` with the local path to the video file.
            let videoProcessor = Vision.VideoProcessor(videoURL)
            
            /// The request to calculate the aesthetics score for each frame.
            let aestheticsScoresRequest = CalculateImageAestheticsScoresRequest()
            
            /// The request to generate feature prints from an image.
            let imageFeaturePrintRequest = GenerateImageFeaturePrintRequest()
            
            /// The array to store information for the frames with the highest scores.
            var topFrames: [Frame] = []
            
            /// The asset that represents video at a local URL to process the video.
            let asset = AVURLAsset(url: videoURL)
            var times: [CMTime] = []
            
            do {
                /// The total duration of the video in seconds.
                let totalDuration = try await asset.load(.duration).seconds
                
                /// The number of frames to evaluate.
                let framesToEval: Double = Double(layout.thumbCount) * 2.0
                
                /// The preferred timescale for the interval.
                let timeScale: CMTimeScale = 600
                
                /// The time interval for the video-processing cadence.
                let interval = CMTime(
                    seconds: totalDuration / framesToEval,
                    preferredTimescale: timeScale
                )
                
                /// The video-processing cadence to process only 100 frames.
                let cadence = Vision.VideoProcessor.Cadence.timeInterval(interval)
                
                /// The stream that adds the aesthetics scores request to the video processor.
                let aestheticsScoreStream = try await videoProcessor.addRequest(aestheticsScoresRequest, cadence: cadence)
                /// The stream that adds the image feature-print request to the video processor.
                let featurePrintStream = try await videoProcessor.addRequest(imageFeaturePrintRequest, cadence: cadence)
                
                // Start to analyze the video.
                videoProcessor.startAnalysis()
                
                /// The dictionary to store the timestamp and the aesthetics score.
                var aestheticsResults: [CMTime: Float] = [:]
                
                /// The dictionary to store the timestamp and the feature-print observation.
                var featurePrintResults: [CMTime: FeaturePrintObservation] = [:]
                
                var count = 0
                
                // Go through the video stream to fill in `aestheticsResults`.
                for try await observation in aestheticsScoreStream {
                    if let timeRange = observation.timeRange {
                        aestheticsResults[timeRange.start] = observation.overallScore
                        
                        count += 1
                        print("finding aesthetics results \(count)")
                        // Update progress with the current time and total duration.
                     //   progression = Float(timeRange.start.seconds / totalDuration)
                    }
                }
                
                print("\(count)")
                
                // Go through the video stream to fill in `featurePrintResults`.
                for try await observation in featurePrintStream {
                    if let timeRange = observation.timeRange {
                        featurePrintResults[timeRange.start] = observation
                    }
                }
                let maxTopFrames = layout.thumbCount
                // Solve for the top-rated frames.
                var topFrames: [Frame] = []
                /// The threshold for counting the image distance as similar.
                let similarityThreshold = 0.3
                for (time, score) in aestheticsResults {
                    /// The `FeaturePrintObservation` for the timestamp.
                    guard let featurePrint = featurePrintResults[time] else { continue }

                    /// The new frame at that timestamp.
                    let newFrame = Frame(time: time, score: score, observation: featurePrint)
                    print("Time, score : \(newFrame.time), \(newFrame.score)")

                    /// The variable that tracks whether to add the image based on image similarity.
                    var isSimilar = false

                    /// The variable to track the index to insert the new frame.
                    var insertionIndex = topFrames.count

                    // Iterate through the current top-rated frames to check whether any of them
                    // are similar to the new frame and find the insertion index.
                    for (index, frame) in topFrames.enumerated() {
                        if let distance = try? featurePrint.distance(to: frame.observation), distance < similarityThreshold {
                            // Replace the frame if the new frame has a higher score.
                            if newFrame.score > frame.score {
                                topFrames[index] = newFrame
                            }
                            isSimilar = true
                            break
                        }

                        // Comparing the scores to find the insertion index.
                        if newFrame.score > frame.score {
                            insertionIndex = index
                            break
                        }
                    }
                    // Insert the new frame if it's not similar and
                    // has an insertion index within the number of frames to store.
                    if !isSimilar && insertionIndex < maxTopFrames {
                        topFrames.insert(newFrame, at: insertionIndex)
                        
                        if topFrames.count > maxTopFrames {
                            topFrames.removeLast()
                        }
                    }
                }
                for (offset, frame) in topFrames.enumerated(){
                    times.append(frame.time)
                   // print("adding a frame at \(frame.time)")
                }
            } catch {
                fatalError("Error processing video: \(error.localizedDescription)")
            }
           
           
           
            var thumbnails: [(Int, CGImage, String)] = []
            var failedCount = 0
            let generator = configureGenerator(for: asset, accurate: accurate, preview: preview, layout: layout)
            
            for await result in generator.images(for: times) {
                switch result {
                case .success(requestedTime: _, image: let image, actualTime: let actual):
                    thumbnails.append((thumbnails.count, image, formatTimestamp(seconds: actual.seconds)))
                case .failure(requestedTime: _, error: let error):
                    logger.error("Thumbnail extraction failed: \(error.localizedDescription)")
                    failedCount += 1
                    // Create a blank image to replace the failed thumbnail
                    if let blankImage = createBlankImage(size: layout.thumbnailSize) {
                        thumbnails.append((thumbnails.count, blankImage, "00:00:00"))
                    }
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

    private func createBlankImage(size: CGSize) -> CGImage? {
        // Create a blank image with the specified size
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.setFillColor(CGColor(gray: 0.0, alpha: 0.0))
        context?.fill(CGRect(origin: .zero, size: size))
        return context?.makeImage()
    }
}
