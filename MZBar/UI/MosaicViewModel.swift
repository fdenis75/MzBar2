import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

class MosaicViewModel: ObservableObject {
    // MARK: - Published Properties
    
    // Mode Selection
    @Published var selectedMode: ProcessingMode = .mosaic
    
    // Input Management
    @Published var inputPaths: [(String,Int)] = []
    @Published var inputType: InputType = .folder
    
    // Processing Settings
    @Published var selectedSize = 5120
    @Published var selectedduration = 0
    @Published var selectedDensity = "M"
    @Published var selectedFormat = "heic"
    @Published var previewDuration: Double = 60.0
    @Published var concurrentOps = 8
    // Processing Options
    @Published var overwrite = false
    @Published var saveAtRoot = false
    @Published var seperate = false
    @Published var summary = false
    @Published var customLayout = true
    @Published var addFullPath = false
    @Published var layoutName = "Focus"
    
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
    @Published private(set) var fps: Double = 0
     @Published private(set) var activeFiles: [FileProgress] = []
    private let maxConcurrentFiles = 24 // Match with your generator config
    @Published var autoProcessDroppedFiles: Bool = false
    
    @Published var config: MosaicGeneratorConfig
    
    // MARK: - Constants
    let sizes = [2000, 4000, 5120, 8000, 10000]
    let densities = ["XXS", "XS", "S", "M", "L", "XL", "XXL"]
    let formats = ["heic", "jpeg"]
    let durations = [0, 10, 30, 60, 120, 300, 600]
    let layouts = ["Classic", "Focus"]
    let concurrent = [1,2,4,8,16,24,32]
    
    // MARK: - Private Properties
    private let pipeline: ProcessingPipeline
    
    // MARK: - Initialization
    init() {
        self.config = .default
        
        var Pconfig = ProcessingConfiguration(
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
        
        self.pipeline = ProcessingPipeline(config: Pconfig)
        setupPipeline()
    }
    
    // MARK: - Public Methods
    func processMosaics() {
        guard !inputPaths.isEmpty else {
            statusMessage1 = "Please select input first."
            return
        }
        
        isProcessing = true
        statusMessage1 = "Starting processing..."
        
        Task {
            do {
                let config = getCurrentConfig()
                let files = try await getInputFiles(Pconfig: config)
                
                
               
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
    func processPreviews() {
        guard !inputPaths.isEmpty else {
            statusMessage1 = "Please select input first."
            return
        }
        
        isProcessing = true
        statusMessage1 = "Starting processing..."
        
        Task {
            do {
                let config = getCurrentConfig()
                let files = try await getInputFiles(Pconfig: config)
                
                
               
                    try await pipeline.generatePreviews(
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
    func updateMaxConcurrentTasks() {
        pipeline.updateMaxConcurrentTasks(concurrentOps)
    }
    
    func generateMosaictoday() {
        isProcessing = true
        statusMessage1 = "Starting today's mosaic generation..."
        
        Task {
            do {
                
                let files = try await pipeline.getTodayFiles(width: selectedSize)
                try await pipeline.createPlaylisttoday()
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
    func generatePlaylisttoday() {
        isProcessing = true
        statusMessage1 = "Starting playlist today generation..."
        
        Task {
            do {
                try await pipeline.createPlaylisttoday()
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
    /*func handleDroppedFiles(_ urls: [URL]) {
        inputPaths = urls[0].map { $0.path}
            
            if urls.count == 1 {
                let url = urls[0]
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false {
                    inputType = .folder
                } else if url.pathExtension.lowercased() == "m3u8" {
                    inputType = .m3u8
                } else {
                    inputType = .files
                }
            } else {
                inputType = .files
            }
            
            if autoProcessDroppedFiles {
               // processInput()
            }
        }*/
    
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
        if layoutName == "Focus" { customLayout = true }
        else
        {
            customLayout = false
        }
        return ProcessingConfiguration(
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
        // Since this might be called from a background thread, ensure we're on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if (info.progressType == .global) {
                self.progressG = info.progress.isNaN ? 0.0 : info.progress
                self.processedFiles = info.processedFiles
                self.totalFiles = info.totalFiles
                self.skippedFiles = info.skippedFiles
                self.errorFiles = info.errorFiles
                self.elapsedTime = info.elapsedTime
                self.estimatedTimeRemaining = info.estimatedTimeRemaining
                self.updateStatusMessages(stage: info.currentStage)
                self.fps = info.fps ?? 0.0
            } else {
                self.currentFile = info.currentFile
                self.updateFileProgress(info.currentFile, progress: info.fileProgress ?? 0.0, stage: info.currentStage)
                if info.fileProgress == 1.0 {
                    self.completeFileProgress(info.currentFile)
                }
            }
            
            self.isProcessing = info.isRunning
        }
    }
    
    private func updateStatusMessages(stage: String) {
        statusMessage1 = "Processing: \(currentFile.substringWithRange(0,end: 30))..."
        statusMessage2 = "Progress: \(processedFiles)/\(totalFiles) files (skipped: \(skippedFiles), Error: \(errorFiles))"
        statusMessage3 = "Stage: \(stage)"
        statusMessage4 = "Estimated Time Remaining: \(estimatedTimeRemaining.format(2))s (current speed : \(fps.format(2)) files/s)"
    }
 
    private func updateFileProgress(_ filename: String, progress: Double, stage: String) {
        // Since we're already on the main thread from updateProgress, we don't need another dispatch
        if let index = activeFiles.firstIndex(where: { $0.filename == filename }) {
            activeFiles[index].progress = progress
            activeFiles[index].stage = stage
        } else {
            addFileProgress(filename)
        }
    }

    private func addFileProgress(_ filename: String) {
        // Since we're already on the main thread from updateProgress, we don't need another dispatch
        if activeFiles.count >= maxConcurrentFiles {
            if let completeIndex = activeFiles.firstIndex(where: { $0.isComplete }) {
                activeFiles.remove(at: completeIndex)
            }
        }
        
        if activeFiles.count < maxConcurrentFiles {
            activeFiles.append(FileProgress(filename: filename))
        }
    }

    private func completeFileProgress(_ filename: String) {
        // Since we're already on the main thread from updateProgress, we don't need another dispatch
        if let index = activeFiles.firstIndex(where: { $0.filename == filename }) {
            activeFiles.remove(at: index)
        }
    }
        

    private func getInputFiles(Pconfig: ProcessingConfiguration) async throws -> [(URL, URL)] {
        switch inputType {
        case .folder:
            return try await pipeline.getFiles(from: inputPaths[0].0, width: selectedSize, config: Pconfig)
        case .m3u8:
            return try await pipeline.getFiles(from: inputPaths[0].0, width: selectedSize, config: Pconfig )
        case .files:
            // Create an array to hold all the results
            var allFiles: [(URL, URL)] = []
            
            // Process each path sequentially
            for (path, count ) in inputPaths {
                let files = try await pipeline.getSingleFile(from: path, width: selectedSize)
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
        
        let content = UNMutableNotificationContent()
        content.title = success ? "Processing Complete" : "Processing Failed"
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
        
        isProcessing = false
    }

    func cancelFile(_ fileId: UUID) {
    if let index = activeFiles.firstIndex(where: { $0.id == fileId }) {
        activeFiles[index].isCancelled = true
        pipeline.cancelFile(activeFiles[index].filename)
        completeFileProgress(activeFiles[index].filename)
        }
    }

    private func handleError(_ error: Error) {
        isProcessing = false
        if error is CancellationError {
            statusMessage1 = "Processing was cancelled"
        } else {
            statusMessage1 = "Error: \(error.localizedDescription)"
        }
    }

    func updateConfig() {
        // Update the config in GenerationCoordinator
        pipeline.updateConfig(config)
    }
   /* private func removeItem(_ path: String) {
        withAnimation {
            inputPaths.removeAll { $0 == path }
            if inputPaths.isEmpty {
                isTargeted = false
            }
        }
    }*/

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
        case .settings: return .preview
        }
    }
}
