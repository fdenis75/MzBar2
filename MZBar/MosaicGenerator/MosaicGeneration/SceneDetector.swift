//
//  SceneDetector.swift
//  MZBar
//
//  Created by Francois on 11/11/2024.
//

/*
import Vision
import AVFoundation
import VideoToolbox

class SceneDetector {
    private let videoURL: URL
    private var sceneTimings: [CMTime] = []
    private let minimumSceneDuration: CMTime
    private let queue = DispatchQueue(label: "com.mosaic.scenedetection", qos: .userInitiated)
    
    // VNVideoProcessor for hardware-accelerated processing
    private var videoProcessor: VNVideoProcessor?
    
    init(videoURL: URL, minimumSceneDuration: Double = 0.5) {
        self.videoURL = videoURL
        self.minimumSceneDuration = CMTime(seconds: minimumSceneDuration, preferredTimescale: 600)
    }
    
    func detectScenes() async throws -> [CMTime] {
        let asset = AVURLAsset(url: videoURL)
        
        // Create video processor
        self.videoProcessor = try VNVideoProcessor(url: videoURL)
        
        // Configure scene analysis request
        let request = VNDetectSceneClassificationRequest { [weak self] request, error in
            guard let results = request.results as? [VNClassificationObservation],
                  let timing = request.frameAnalysisTime else { return }
            
            // Process scene changes
            self?.processSceneChange(results: results, at: timing)
        }
        
        // Configure processing
        let analysisSpecs = VNVideoProcessorRequestAnalysisSpecs(
            frameInterval: 1,    // Analyze every frame
            timeRange: CMTimeRange(start: .zero, duration: try await asset.load(.duration))
        )
        
        // Perform hardware-accelerated analysis
        try await videoProcessor?.perform(
            [request],
            analysisSpecs: analysisSpecs,
            qosClass: .userInitiated
        )
        
        return sceneTimings
    }
    
    private func processSceneChange(results: [VNClassificationObservation], at time: CMTime) {
        guard let topResult = results.first else { return }
        
        // Check for significant scene changes
        if topResult.confidence > 0.7 {
            if let lastScene = sceneTimings.last {
                let duration = time - lastScene
                if duration >= minimumSceneDuration {
                    sceneTimings.append(time)
                }
            } else {
                sceneTimings.append(time)
            }
        }
    }
}
*/
