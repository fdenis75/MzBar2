import Foundation
import SwiftUI
import UniformTypeIdentifiers

class MosaicViewModel: ObservableObject {
    // MARK: - Published Properties
    
    // Mode Selection
    @Published var selectedMode: ProcessingMode = .mosaic
    
    // Input Management
    @Published var inputPaths: [String] = []
    @Published var inputType: InputType = .folder
    
    // Processing Settings
    @Published var selectedSize = 5120
    @Published var selectedduration = 0
    @Published var selectedDensity = "M"
    @Published var selectedFormat = "heic"
    @Published var previewDuration: Double = 60.0
    
    // Processing Options
    @Published var overwrite = false
    @Published var saveAtRoot = false
    @Published var seperate = false
    @Published var summary = false
    @Published var customLayout = true
    @Published var addFullPath = false
    
    // State
    @Published var isProcessing = false
    @Published var progressG: Double = 0
    
    // Status Messages
    @Published var statusMessage1: String = ""
    @Published var statusMessage2: String = ""
    @Published var statusMessage3: String = ""
    @Published var statusMessage4: String = ""
    
    // Progress Details
    @Published private(set) var currentFile: String = ""
    @Published private(set) var processedFiles: Int = 0
    @Published private(set) var totalFiles: Int = 0
    @Published private(set) var skippedFiles: Int = 0
    @Published private(set) var errorFiles: Int = 0
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var estimatedTimeRemaining: TimeInterval = 0
    
    // MARK: - Constants
    let sizes = [2000, 4000, 5120, 8000, 10000]
    let densities = ["XXS", "XS", "S", "M", "L", "XL", "XXL"]
    let formats = ["heic", "jpeg"]
    let durations = [0, 10, 30, 60, 120, 300, 600]
    
    // MARK: - Private Properties
    private let pipeline: ProcessingPipeline
    
    // MARK: - Initialization
    init() {
        let config = ProcessingConfiguration(
            width: 5120,
            density: "M",
            format: "heic",
            duration: 0,
            previewDuration: 60,
            overwrite: false,
            saveAtRoot: false,
            separateFolders: true,
            summary: false,
            customLayout: true,
            addFullPath: false,
            generatorConfig: .default
        )
        
        self.pipeline = ProcessingPipeline(config: config)
        setupPipeline()
    }
    
    // MARK: - Public Methods
    
    func processInput() {
        guard !inputPaths.isEmpty else {
            statusMessage1 = "Please select input first."
            return
        }
        
        isProcessing = true
        statusMessage1 = "Starting processing..."
        
        Task {
            do {
                let files = try await getInputFiles()
                let config = getCurrentConfig()
                
                if selectedMode == .preview {
                    try await pipeline.generatePreviews(
                        for: files,
                        config: config
                    )
                } else {
                    try await pipeline.generateMosaics(
                        for: files,
                        config: config
                    )
                }
                
                await MainActor.run {
                    completeProcessing(success: true)
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                }
            }
        }
    }
    
    func generateMosaictoday() {
        isProcessing = true
        statusMessage1 = "Starting today's mosaic generation..."
        
        Task {
            do {
                let files = try await pipeline.getTodayFiles(width: selectedSize)
                let config = getCurrentConfig()
                
                try await pipeline.generateMosaics(
                    for: files,
                    config: config
                )
                
                await MainActor.run {
                    completeProcessing(success: true)
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                }
            }
        }
    }
    
    func generatePlaylist(_ path: String) {
        isProcessing = true
        statusMessage1 = "Starting playlist generation..."
        
        Task {
            do {
                try await pipeline.createPlaylist(from: path)
                await MainActor.run {
                    completeProcessing(success: true, message: "Playlist generation completed")
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                }
            }
        }
    }
    
    func cancelGeneration() {
        pipeline.cancel()
        statusMessage1 = "Cancelling generation..."
    }
    
    // MARK: - Private Methods
    
    private func setupPipeline() {
        pipeline.progressHandler = { [weak self] info in
            Task { @MainActor in
                self?.updateProgress(with: info)
            }
        }
    }
    
    private func getCurrentConfig() -> ProcessingConfiguration {
        ProcessingConfiguration(
            width: selectedSize,
            density: selectedDensity,
            format: selectedFormat,
            duration: selectedduration,
            previewDuration: Int(previewDuration),
            overwrite: overwrite,
            saveAtRoot: saveAtRoot,
            separateFolders: seperate,
            summary: summary,
            customLayout: customLayout,
            addFullPath: addFullPath,
            generatorConfig: .default
        )
    }
    
    private func updateProgress(with info: ProgressInfo) {
        progressG = info.progress
        currentFile = info.currentFile
        processedFiles = info.processedFiles
        totalFiles = info.totalFiles
        skippedFiles = info.skippedFiles
        errorFiles = info.errorFiles
        elapsedTime = info.elapsedTime
        estimatedTimeRemaining = info.estimatedTimeRemaining
        isProcessing = info.isRunning
        
        updateStatusMessages(stage: info.currentStage)
    }
    
    private func updateStatusMessages(stage: String) {
        statusMessage1 = "Processing: \(currentFile)"
        statusMessage2 = "Progress: \(processedFiles)/\(totalFiles) files (skipped: \(skippedFiles), Error: \(errorFiles))"
        statusMessage3 = "Stage: \(stage)"
        statusMessage4 = "Estimated Time Remaining: \(estimatedTimeRemaining.format(2)) s"
    }
    
    
    private func getInputFiles() async throws -> [(URL, URL)] {
        switch inputType {
        case .folder:
            return try await pipeline.getFiles(from: inputPaths[0], width: selectedSize)
        case .m3u8:
            return try await pipeline.getFiles(from: inputPaths[0], width: selectedSize)
        case .files:
            // Create an array to hold all the results
            var allFiles: [(URL, URL)] = []
            
            // Process each path sequentially
            for path in inputPaths {
                let files = try await pipeline.getFiles(from: path, width: selectedSize)
                allFiles.append(contentsOf: files)
            }
            
            return allFiles
        }
    }
    
    private func completeProcessing(success: Bool, message: String? = nil) {
        statusMessage1 = message ?? (success ? "Processing completed successfully!" : "Processing completed with errors")
        if !isProcessing {
            statusMessage2 = ""
            statusMessage3 = ""
            statusMessage4 = ""
        }
        
        let notification = NSUserNotification()
        notification.title = success ? "Processing Complete" : "Processing Failed"
        NSUserNotificationCenter.default.deliver(notification)
        
        isProcessing = false
    }
    
    private func handleError(_ error: Error) {
        isProcessing = false
        if error is CancellationError {
            statusMessage1 = "Processing was cancelled"
        } else {
            statusMessage1 = "Error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Type Definitions
extension MosaicViewModel {
    enum InputType {
        case folder
        case m3u8
        case files
    }
}

// MARK: - Theme Support
extension MosaicViewModel {
    var currentTheme: AppTheme {
        switch selectedMode {
        case .mosaic: return .mosaic
        case .preview: return .preview
        case .playlist: return .playlist
        }
    }
}
