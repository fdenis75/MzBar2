import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

class MosaicViewModel: ObservableObject {
    // MARK: - Published Properties
    
    // Mode Selection
   

    // Input Management
    @Published var inputPaths: [(String,Int)] = []
    @Published var inputType: InputType = .folder
    
    // Processing Settings
    @Published var selectedSize = 5120
    @Published var selectedduration = 0
    @Published var selectedDensity = 4.0
    @Published var previewDensity = 4.0
    @Published var selectedFormat = "heic"
    @Published var previewDuration: Double = 60.0
    @Published var concurrentOps = 8
    @Published var codec: String = "AVAssetExportPresetHEVC1920x1080"
    // Processing Options
    @Published var overwrite = false
    @Published var saveAtRoot = false
    @Published var seperate = false
    @Published var summary = false
    @Published var customLayout = true
    @Published var addFullPath = false
    @Published var layoutName = "Focus"
    @Published var selectedPlaylistType = 0
    @Published var previewEngine = PreviewEngine.avFoundation
    @Published var startDate: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @Published var endDate: Date = Date()
    
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
    
    @Published private(set) var queuedFiles: [FileProgress] = []
    @Published private(set) var currentlyProcessingFile: URL?
    @Published private(set) var failedFiles: Set<URL> = []
    @Published private(set) var completedFiles: [FileProgress] = []
@Published var compressionQuality: Float = 0.6 {
    didSet {
        config.compressionQuality = compressionQuality
        updateConfig()
    }
}
    // MARK: - Constants
    let sizes = [2000, 4000, 5120, 8000, 10000]
    let densities = ["XXS", "XS", "S", "M", "L", "XL", "XXL"]
    let formats = ["heic", "jpeg"]
    let durations = [0, 10, 30, 60, 120, 300, 600]
    let layouts = ["Classic", "Focus"]
    let concurrent = [1,2,4,8,16,24,32]
    
    // MARK: - Private Properties
    private let pipeline: ProcessingPipeline
    @Published var selectedMode: TabSelection = .mosaic {
            didSet {
                // Notify views to apply the new theme when mode changes
                currentTheme = AppTheme(from: selectedMode)
            }
        }
        
        @Published var currentTheme: AppTheme = .mosaic

    // MARK: - Initialization
    init() {
        self.config = .default
     //   self.compressionQuality = self.config.compressionQuality
        
        var Pconfig = ProcessingConfiguration(
            width: 5120,
            density: "M",
            format: "heic",
            duration: 0,
            previewDuration: 60,
            previewDensity: "M",
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
        loadSavedOutputFolder()
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
                await MainActor.run {
                    queuedFiles = files.map { file in
                        FileProgress(filename: file.0.path)
                    }
                }
                
                
                try await pipeline.generateMosaics(
                    for: files,
                    config: config
                ) { result in
                    if case let .success((input, outputURL)) = result {
                        Task { @MainActor in
                            self.completeFileProgress(input.path, outputURL: outputURL)
                        }
                    }
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
                await MainActor.run {
                    queuedFiles = files.map { file in
                        FileProgress(filename: file.0.path)
                    }
                }
                
                
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
    func updateCodec() {
        pipeline.updateCodec(codec)
    }
    
    func generateMosaictoday() {
        isProcessing = true
        statusMessage1 = "Starting today's mosaic generation..."
        
        Task {
            do {
                
                let files = try await pipeline.getTodayFiles(width: selectedSize)
                try await pipeline.createPlaylisttoday()
                let config = getCurrentConfig()
                await MainActor.run {
                    queuedFiles = files.map { file in
                        FileProgress(filename: file.0.path)
                    }
                }
                try await pipeline.generateMosaics(
                    for: files,
                    config: config
                ) { result in
                    if case let .success((input, outputURL)) = result {
                        Task { @MainActor in
                            self.completeFileProgress(input.path, outputURL: outputURL)
                        }
                    }
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
    
    func generatePlaylist(_ path: String) {
        isProcessing = true
        statusMessage1 = "Starting playlist generation..."
        
        Task {
            do {
                let playlistURL = try await pipeline.createPlaylist(
                    from: path, 
                    playlistype: selectedPlaylistType,
                    outputFolder: playlistOutputFolder
                )
                await MainActor.run {
                    self.lastGeneratedPlaylistURL = playlistURL
                    completeProcessing(success: true, message: "Playlist generation completed")
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                }
            }
        }
    }


    
    func generateDateRangePlaylist() {
        isProcessing = true
        statusMessage1 = "Starting date range playlist generation..."
        
        Task {
            do {
                let playlistURL = try await pipeline.createDateRangePlaylist(
                    from: startDate,
                    to: endDate,
                    playlistype: selectedPlaylistType,
                    outputFolder: playlistOutputFolder
                )
                await MainActor.run {
                    self.lastGeneratedPlaylistURL = playlistURL
                    completeProcessing(success: true, message: "Date range playlist generation completed")
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
                let playlistURL = try await pipeline.createPlaylisttoday(
                    outputFolder: playlistOutputFolder
                )
                await MainActor.run {
                    self.lastGeneratedPlaylistURL = playlistURL
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
        
        // Update UI state
        queuedFiles.forEach { file in
            if let index = queuedFiles.firstIndex(where: { $0.id == file.id }) {
                queuedFiles[index].isCancelled = true
                queuedFiles[index].stage = "Cancelled"
            }
        }
        
        isProcessing = false
        
        // Reset messages
        statusMessage2 = ""
        statusMessage3 = ""
        statusMessage4 = ""
        
        // Show notification
        showCancellationNotification()
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
        else { customLayout = false }
        
        // Update the generator config with current compression quality
        if let preset = QualityPreset(rawValue: selectedQualityPreset) {
            config.compressionQuality = preset.compressionQuality
        }
        config.videoExportPreset = codec
        
        return ProcessingConfiguration(
            width: selectedSize,
            density: DensityConfig.densityFrom(selectedDensity),
            format: selectedFormat,
            duration: selectedduration,
            previewDuration: Int(previewDuration),
            previewDensity:  DensityConfig.extractsFrom(previewDensity),
            overwrite: overwrite,
            saveAtRoot: saveAtRoot,
            separateFolders: seperate,
            summary: summary,
            customLayout: customLayout,
            addFullPath: addFullPath,
            addBorder: addBorder,
            addShadow: addShadow,
            borderColor: NSColor(borderColor).cgColor,
            borderWidth: CGFloat(borderWidth),
            generatorConfig: config
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
        if let index = queuedFiles.firstIndex(where: { $0.filename == filename }) {
            queuedFiles[index].progress = progress
            queuedFiles[index].stage = stage
        } else {
            return
        }
    }
    /*
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
    }*/
    
    private func completeFileProgress(_ filename: String, outputURL: URL? = nil) {
        if let index = queuedFiles.firstIndex(where: { $0.filename == filename }) {
            queuedFiles[index].progress = 1.0
            queuedFiles[index].stage = "Complete"
            queuedFiles[index].isComplete = true
            queuedFiles[index].outputURL = outputURL
            
            // Move to completed files
            let completedFile = queuedFiles[index]
            DispatchQueue.main.async {
                self.completedFiles.append(completedFile)
                if !self.queuedFiles.isEmpty {
                    self.queuedFiles.remove(at: index)
                }
               
            }
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
        if let index = queuedFiles.firstIndex(where: { $0.id == fileId }) {
            let filename = queuedFiles[index].filename
            
            // Update UI state
            queuedFiles[index].isCancelled = true
            queuedFiles[index].stage = "Cancelled"
            
            // Cancel in pipeline
            pipeline.cancelFile(filename)
            
            // Update status if this was the current file
            if statusMessage1.contains(filename) {
                statusMessage1 = "Cancelled: \(filename)"
            }
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
    
    func retryPreview(for fileId: UUID) {
        Task {
            guard let index = queuedFiles.firstIndex(where: { $0.id == fileId }),
                  queuedFiles[index].stage.contains("Exporting") else { return }
            
            let file = queuedFiles[index]
            
            await MainActor.run {
                queuedFiles[index].progress = 0
                queuedFiles[index].stage = "Retrying preview generation"
            }
            
            pipeline.cancelFile(file.filename)
            
            do {
                let config = getCurrentConfig()
                let files = try await pipeline.getSingleFile(from: file.filename, width: selectedSize)
                try await pipeline.generatePreviews(for: files, config: config)
            } catch {
                await MainActor.run {
                    handleError(error)
                }
            }
        }
    }
    
    @Published var selectedQualityPreset: Int = 0 {
        didSet {
            if let preset = QualityPreset(rawValue: selectedQualityPreset) {
                config.compressionQuality = preset.compressionQuality
                updateConfig()
            }
        }
    }
    
    
    
   
    
    func fileStatus(for file: URL) -> FileStatus {
        if failedFiles.contains(file) {
            return .failed
        } else if completedFiles.contains(where: { $0.filename == file.path }) {
            return .completed
        } else if currentlyProcessingFile == file {
            return .processing
        } else {
            return .queued
        }
    }
    /*
    func cancelFile(_ file: FileProgress) {
        Task {
            await pipeline.cancelFile(file.filename)
            DispatchQueue.main.async {
                self.queuedFiles.removeAll { $0.path == file.filename }
            }
        }
    }*/
    
   /* func retryFile(_ file: FileProgress) {
        DispatchQueue.main.async {
            self.failedFiles.remove(URL(fileURLWithPath: file.filename))
            // Add to beginning of queue for immediate processing
            self.queuedFiles.insert(URL(fileURLWithPath: file.filename), at: 0)
        }
    }*/
    
   
    
    func updateCurrentFile(_ file: URL?) {
        DispatchQueue.main.async {
            self.currentlyProcessingFile = file
        }
    }
    
    func markFileAsFailed(_ file: URL) {
        DispatchQueue.main.async {
            self.failedFiles.insert(file)
        }
    }
    
    func markFileAsCompleted(_ file: URL) {
        DispatchQueue.main.async {
            self.completedFiles.append(FileProgress(filename: file.path))
        }
    }
    
    private func showCancellationNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Processing Cancelled"
        content.body = "Mosaic generation has been cancelled"
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    @Published var lastGeneratedPlaylistURL: URL? = nil
    
    @Published var playlistOutputFolder: URL? = nil
    
    func setPlaylistOutputFolder(_ url: URL) {
        playlistOutputFolder = url
        // Optionally save to UserDefaults for persistence
        if let bookmarkData = try? url.bookmarkData() {
            UserDefaults.standard.set(bookmarkData, forKey: "PlaylistOutputFolder")
        }
    }
    
    func resetPlaylistOutputFolder() {
        playlistOutputFolder = nil
        UserDefaults.standard.removeObject(forKey: "PlaylistOutputFolder")
    }
    
    private func loadSavedOutputFolder() {
        if let bookmarkData = UserDefaults.standard.data(forKey: "PlaylistOutputFolder") {
            var isStale = false
            do {
                let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                if !isStale {
                    playlistOutputFolder = url
                }
            } catch {
                print("Failed to resolve bookmark: \(error)")
            }
        }
    }
    
    @Published var isFileDiscoveryCancelled = false
    
    func cancelFileDiscovery() {
        isFileDiscoveryCancelled = true
    }
    
    @Published var selectedAspectRatio: MosaicAspectRatio = .landscape {
        didSet {
            updateAspectRatio()
        }
    }
    
    private func updateAspectRatio() {
        pipeline.updateAspectRatio(selectedAspectRatio.ratio)
    }

    // Add new published properties
    @Published var addBorder = false
    @Published var addShadow = false
    @Published var borderColor = Color.white
    @Published var borderWidth: Double = 2
    
}

// MARK: - Type Definitions
extension MosaicViewModel {
    enum InputType {
        case folder
        case m3u8
        case files
    }
    
    enum MosaicAspectRatio: String, CaseIterable {
        case landscape = "16:9"
        case square = "1:1"
        case portrait = "9:16"
        
        var ratio: CGFloat {
            switch self {
            case .landscape: return 16.0 / 9.0
            case .square: return 1.0
            case .portrait: return 9.0 / 16.0
            }
        }
    }
}

// MARK: - Theme Support
