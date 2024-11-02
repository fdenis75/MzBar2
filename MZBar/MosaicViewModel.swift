//
//  MosaicViewModel.swift
//  MZBar
//
//  Created by Francois on 01/11/2024.
//
import Foundation
import UniformTypeIdentifiers
import SwiftUI


class MosaicViewModel: ObservableObject {
    @Published var selectedMode: ProcessingMode = .mosaic
    @Published var inputPath: String = ""
    @Published var progressG: Double = 0
    @Published var progressT: Double = 0
    @Published var progressM: Double = 0
    @Published var statusMessage1: String = ""
    @Published var statusMessage2: String = ""
    @Published var statusMessage3: String = ""
    @Published var statusMessage4: String = ""
    
    @Published var selectedSize = 5120
    @Published var selectedduration = 0
    @Published var previewDuration:Double = 60.0
    
    @Published var selectedDensity = "M"
    @Published var selectedFormat = "heic"
    @Published var isProcessing: Bool = false
    @Published var overwrite: Bool = false
    @Published var saveAtRoot: Bool = false
    @Published var seperate: Bool = false
    @Published var summary: Bool = false
    @Published var customLayout: Bool = true
    @Published var preview: Bool = false
    @Published var addFullPath: Bool = false
    
    
    @Published var currentFile: String = ""
    @Published var processedFiles: Int = 0
    @Published var totalFiles: Int = 0
    @Published var currentStage: String = ""
    @Published var skippedFiles: Int = 0
    @Published var errorFiles: Int = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var estimatedTimeRemaining: TimeInterval = 0
    @Published var inputPaths: [String] = []
    @Published var inputType: InputType = .folder
    enum InputType {
        case folder
        case m3u8
        case files
    }
    
    
    
    var appDelegate: AppDelegate? {
        return NSApplication.shared.delegate as? AppDelegate
    }
    
    private var generator: MosaicGenerator?
    let sizes = [2000, 4000, 5120, 8000, 10000]
    let densities = ["XXS", "XS", "S", "M", "L", "XL", "XXL"]
    
    let formats = ["heic", "jpeg"]
    let durations = [0, 10,30,60,120,300,600]
    private func updateStatusMessage1() {
        //let elapsedTimeFormatted = formatDuration(elapsedTime)
        // print("\(estimatedTimeRemaining.debugDescription)")
        // let estimatedTimeRemainingFormatted = formatDuration(estimatedTimeRemaining)
        
        // let final = Double(est)
        statusMessage1 = "Processing: \(currentFile)"
        //  Estimated Time Remaining: \(estimatedTimeRemainingFormatted)
    }
    private func updateStatusMessage2() {
        let est = estimatedTimeRemaining.description
        var final: Double
        if est == "inf"
        {
            final = 0.0
        }
        else
        {
            final = Double(est)!
        }
        // let final = Double(est)
        statusMessage2 = """
          Progress: \(processedFiles)/\(totalFiles) files (skipped : \(skippedFiles),Error : \(errorFiles) )
          """
    }
    private func updateStatusMessage3() {
        //let elapsedTimeFormatted = formatDuration(elapsedTime)
        // print("\(estimatedTimeRemaining.debugDescription)")
        // let estimatedTimeRemainingFormatted = formatDuration(estimatedTimeRemaining)
        
        // let final = Double(est)
        statusMessage3 = """
          Stage: \(currentStage)
          """
        
        //  Estimated Time Remaining: \(estimatedTimeRemainingFormatted)
    }
    private func updateStatusMessage4() {
        //let elapsedTimeFormatted = formatDuration(elapsedTime)
        // print("\(estimatedTimeRemaining.debugDescription)")
        // let estimatedTimeRemainingFormatted = formatDuration(estimatedTimeRemaining)
        let est = estimatedTimeRemaining.description
        var final: Double
        if est == "inf"
        {
            final = 0.0
        }
        else
        {
            final = Double(est)!
        }
        // let final = Double(est)
        statusMessage4 = """
          Estimated Time Remaining: \(final.format(2)) s
          """
        
        //  Estimated Time Remaining: \(estimatedTimeRemainingFormatted)
    }
    func processInput() {
        guard !inputPaths.isEmpty else {
            statusMessage1 = "Please select input first."
            return
        }
        
        isProcessing = true
        statusMessage1 = "Starting processing..."
        generator = MosaicGenerator(debug: false, renderingMode: .auto, maxConcurrentOperations: 20, saveAtRoot: saveAtRoot, separate: seperate, summary: summary, custom: customLayout)
        
        generator?.setProgressHandlerG { [weak self] progressInfo in
            DispatchQueue.main.async {
                self?.progressG = progressInfo.progress
                self?.currentFile = progressInfo.currentFile
                self?.processedFiles = progressInfo.processedFiles
                self?.totalFiles = progressInfo.totalFiles
                self?.currentStage = progressInfo.currentStage
                self?.elapsedTime = progressInfo.elapsedTime
                self?.estimatedTimeRemaining = progressInfo.estimatedTimeRemaining
                self?.skippedFiles = progressInfo.skippedFiles
                self?.errorFiles = progressInfo.errorFiles
                
                self?.updateStatusMessage1()
                self?.updateStatusMessage2()
                self?.updateStatusMessage3()
                self?.updateStatusMessage4()
                
            }
        }
        
        Task {
            do {
                switch inputType {
                case .folder:
                    try await processFolder(inputPaths[0])
                case .m3u8:
                    try await processM3U8(inputPaths[0])
                case .files:
                    try await processFiles(inputPaths)
                }
                
                DispatchQueue.main.async {
                    self.statusMessage1 = "Mosaic generation completed successfully!"
                    let notification = NSUserNotification()
                    notification.title = "Processing Complete"
                    NSUserNotificationCenter.default.deliver(notification)
                    self.isProcessing = false
                }
            } catch is CancellationError {
                DispatchQueue.main.async {
                    self.statusMessage1 = "Processing was cancelled."
                    self.isProcessing = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.statusMessage1 = "Error during processing: \(error.localizedDescription)"
                    self.isProcessing = false
                }
            }
        }
    }
    
    
    
    private func processFolder(_ folderPath: String) async throws {
        guard !folderPath.isEmpty else {
            statusMessage1 = "Please select a folder first."
            return
        }
        func formatDuration(_ duration: Double) -> String {
            let duration = Int(duration)
            let seconds = Double(duration % 60)
            let minutes = Double((duration / 60) % 60)
            let hours = Double(duration / 3600)
            return "\(hours.format(0, minimumIntegerPartLength: 2)):\(minutes.format(0, minimumIntegerPartLength: 2)):\(seconds.format(0, minimumIntegerPartLength: 2))"
        }
        isProcessing = true
        statusMessage1 = "Starting mosaic generation..."
        generator = MosaicGenerator(debug: false, renderingMode: .auto, maxConcurrentOperations: 20, saveAtRoot: saveAtRoot,separate: seperate, summary: summary, custom: customLayout)
        let startTime = CFAbsoluteTimeGetCurrent()
        var TotalCount:Double = 0.0
        var text:String = ""
        generator?.setProgressHandlerG { [weak self] progressInfo in
            DispatchQueue.main.async {
                self?.progressG = progressInfo.progress
                self?.currentFile = progressInfo.currentFile
                self?.processedFiles = progressInfo.processedFiles
                self?.totalFiles = progressInfo.totalFiles
                self?.currentStage = progressInfo.currentStage
                self?.elapsedTime = progressInfo.elapsedTime
                self?.estimatedTimeRemaining = progressInfo.estimatedTimeRemaining
                self?.skippedFiles = progressInfo.skippedFiles
                self?.errorFiles = progressInfo.errorFiles
                self?.updateStatusMessage1()
                self?.updateStatusMessage2()
                self?.updateStatusMessage3()
                self?.updateStatusMessage4()
                
            }
        }
        
        Task {
            do {
                //statusMessage = "Collecting Files..."
                
                try await generator?.getFiles(input: folderPath, width: selectedSize)
                //statusMessage = "Starting generation"
                try await generator?.GenerateMosaics(
                    input: folderPath,
                    width: selectedSize,
                    density: selectedDensity,
                    format: selectedFormat,
                    overwrite: overwrite,
                    preview: preview,
                    summary: summary,
                    duration: selectedduration,
                    addpath: addFullPath,
                    previewDuration: Int(previewDuration)


                )
                DispatchQueue.main.async {
                    self.statusMessage1 = "Mosaic generation completed successfully!"
                    self.statusMessage2 = ""
                    self.statusMessage3 = ""
                    self.statusMessage4 = ""
                    //self.progressG = 0.0
                    let notification = NSUserNotification()
                    notification.title = "Mosaic Generation Complete"
                    NSUserNotificationCenter.default.deliver(notification)
                    self.isProcessing = false
                }
            }catch is CancellationError {
                DispatchQueue.main.async {
                    self.statusMessage1 = "Mosaic generation was cancelled."
                    self.isProcessing = false
                }
            }
            catch {
                DispatchQueue.main.async {
                    self.statusMessage1 = "Error generating mosaic: \(error.localizedDescription)"
                    self.isProcessing = false
                }
            }
        }
    }
    
    private func processM3U8(_ m3u8Path: String) async throws {
        guard !m3u8Path.isEmpty else {
            statusMessage1 = "Please select a folder first."
            return
        }
        func formatDuration(_ duration: Double) -> String {
            let duration = Int(duration)
            let seconds = Double(duration % 60)
            let minutes = Double((duration / 60) % 60)
            let hours = Double(duration / 3600)
            return "\(hours.format(0, minimumIntegerPartLength: 2)):\(minutes.format(0, minimumIntegerPartLength: 2)):\(seconds.format(0, minimumIntegerPartLength: 2))"
        }
        isProcessing = true
        statusMessage1 = "Starting mosaic generation..."
        generator = MosaicGenerator(debug: false, renderingMode: .auto, maxConcurrentOperations: 20, saveAtRoot: saveAtRoot,separate: seperate, summary: summary, custom: customLayout)
        let startTime = CFAbsoluteTimeGetCurrent()
        var TotalCount:Double = 0.0
        var text:String = ""
        generator?.setProgressHandlerG { [weak self] progressInfo in
            DispatchQueue.main.async {
                
                
                self?.progressG = progressInfo.progress
                self?.currentFile = progressInfo.currentFile
                self?.processedFiles = progressInfo.processedFiles
                self?.totalFiles = progressInfo.totalFiles
                self?.currentStage = progressInfo.currentStage
                self?.elapsedTime = progressInfo.elapsedTime
                self?.estimatedTimeRemaining = progressInfo.estimatedTimeRemaining
                self?.skippedFiles = progressInfo.skippedFiles
                self?.errorFiles = progressInfo.errorFiles
                self?.updateStatusMessage1()
                self?.updateStatusMessage2()
                self?.updateStatusMessage3()
                self?.updateStatusMessage4()
            }
        }
        
        
        Task {
            do {
                
                
                try await generator?.getFiles(input: m3u8Path, width: selectedSize)
                //statusMessage = "Starting generation"
                try await generator?.GenerateMosaics(
                    input: m3u8Path,
                    width: selectedSize,
                    density: selectedDensity,
                    format: selectedFormat,
                    overwrite: overwrite,
                    preview: preview,
                    summary: summary,
                    duration: selectedduration,
                    addpath: addFullPath,
                    previewDuration: Int(previewDuration)

                )
                
            }catch is CancellationError {
                DispatchQueue.main.async {
                    self.statusMessage1 = "Mosaic generation was cancelled."
                    self.isProcessing = false
                }
            }
            catch {
                DispatchQueue.main.async {
                    self.statusMessage1 = "Error generating mosaic: \(error.localizedDescription)"
                    self.isProcessing = false
                }
            }
        }
    }
    
    
    private func processFiles(_ filePaths: [String]) async throws {
        guard !filePaths.isEmpty else {
            statusMessage1 = "Please select a folder first."
            return
        }
        func formatDuration(_ duration: Double) -> String {
            let duration = Int(duration)
            let seconds = Double(duration % 60)
            let minutes = Double((duration / 60) % 60)
            let hours = Double(duration / 3600)
            return "\(hours.format(0, minimumIntegerPartLength: 2)):\(minutes.format(0, minimumIntegerPartLength: 2)):\(seconds.format(0, minimumIntegerPartLength: 2))"
        }
        isProcessing = true
        statusMessage1 = "Starting mosaic generation..."
        generator = MosaicGenerator(debug: false, renderingMode: .auto, maxConcurrentOperations: 20, saveAtRoot: saveAtRoot,separate: seperate, summary: summary, custom: customLayout)
        let startTime = CFAbsoluteTimeGetCurrent()
        var TotalCount:Double = 0.0
        var text:String = ""
        generator?.setProgressHandlerG { [weak self] progressInfo in
            DispatchQueue.main.async {
                self?.progressG = progressInfo.progress
                self?.currentFile = progressInfo.currentFile
                self?.processedFiles = progressInfo.processedFiles
                self?.totalFiles = progressInfo.totalFiles
                self?.currentStage = progressInfo.currentStage
                self?.elapsedTime = progressInfo.elapsedTime
                self?.estimatedTimeRemaining = progressInfo.estimatedTimeRemaining
                self?.skippedFiles = progressInfo.skippedFiles
                self?.errorFiles = progressInfo.errorFiles
                self?.updateStatusMessage1()
                self?.updateStatusMessage2()
                self?.updateStatusMessage3()
                self?.updateStatusMessage4()
                
            }
        }
        
        Task {
            do {
                //statusMessage = "Collecting Files..."
                for filePath in filePaths {
                    try await generator?.getFiles(input: filePath, width: selectedSize)
                    try await generator?.GenerateMosaics(
                        input: filePath,
                        width: selectedSize,
                        density: selectedDensity,
                        format: selectedFormat,
                        overwrite: overwrite,
                        preview: preview,
                        summary: summary,
                        duration: selectedduration,addpath: addFullPath,
                        previewDuration: Int(previewDuration)
)
                    DispatchQueue.main.async {
                        self.statusMessage1 = "Mosaic generation completed successfully!"
                        //self.progressG = 0.0
                        let notification = NSUserNotification()
                        notification.title = "Mosaic Generation Complete"
                        NSUserNotificationCenter.default.deliver(notification)
                        self.isProcessing = false
                    }
                }
            }catch is CancellationError {
                DispatchQueue.main.async {
                    self.statusMessage1 = "Mosaic generation was cancelled."
                    self.isProcessing = false
                }
            }
            catch {
                DispatchQueue.main.async {
                    self.statusMessage1 = "Error generating mosaic: \(error.localizedDescription)"
                    self.isProcessing = false
                }
            }
        }
        
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        //let text = duration.debugDescription
        print("\(duration.debugDescription)")
        return formatter.string(from: duration) ?? ""
    }
    
    
    func generateMosaictoday() {
        
        func formatDuration(_ duration: Double) -> String {
            let duration = Int(duration)
            let seconds = Double(duration % 60)
            let minutes = Double((duration / 60) % 60)
            let hours = Double(duration / 3600)
            return "\(hours.format(0, minimumIntegerPartLength: 2)):\(minutes.format(0, minimumIntegerPartLength: 2)):\(seconds.format(0, minimumIntegerPartLength: 2))"
        }
        isProcessing = true
        statusMessage1 = "Starting mosaic generation..."
        generator = MosaicGenerator(debug: false, renderingMode: .auto, maxConcurrentOperations: 20, saveAtRoot: saveAtRoot,separate: seperate, summary: summary, custom: customLayout)
        let startTime = CFAbsoluteTimeGetCurrent()
        var TotalCount:Double = 0.0
        var text:String = ""
        generator?.setProgressHandlerG { [weak self] progressInfo in
            DispatchQueue.main.async {
                self?.progressG = progressInfo.progress
                self?.currentFile = progressInfo.currentFile
                self?.processedFiles = progressInfo.processedFiles
                self?.totalFiles = progressInfo.totalFiles
                self?.currentStage = progressInfo.currentStage
                self?.elapsedTime = progressInfo.elapsedTime
                self?.estimatedTimeRemaining = progressInfo.estimatedTimeRemaining
                self?.skippedFiles = progressInfo.skippedFiles
                self?.errorFiles = progressInfo.errorFiles
                self?.updateStatusMessage1()
                self?.updateStatusMessage2()
                self?.updateStatusMessage3()
                self?.updateStatusMessage4()
                
            }
        }
        
        Task {
            do {
                //statusMessage = "Collecting Files..."
                
                try await generator?.getFilestoday(width: String(selectedSize))
                //statusMessage = "Starting generation"
                try await generator?.GenerateMosaics(
                    width: selectedSize,
                    density: selectedDensity,
                    format: selectedFormat,
                    overwrite: overwrite,
                    preview: false,
                    summary: summary,
                    duration: selectedduration,
                    addpath: true,
                    previewDuration: Int(previewDuration)

                )
                DispatchQueue.main.async {
                    self.statusMessage1 = "Mosaic generation completed successfully!"
                    //self.progressG = 0.0
                    let notification = NSUserNotification()
                    notification.title = "Mosaic Generation Complete"
                    NSUserNotificationCenter.default.deliver(notification)
                    self.isProcessing = false
                }
            }catch is CancellationError {
                DispatchQueue.main.async {
                    self.statusMessage1 = "Mosaic generation was cancelled."
                    self.isProcessing = false
                }
            }
            catch {
                DispatchQueue.main.async {
                    self.statusMessage1 = "Error generating mosaic: \(error.localizedDescription)"
                    self.isProcessing = false
                }
            }
        }
    }
    
    func cancelGeneration() {
        generator?.cancelProcessing()
        statusMessage1 = "Cancelling mosaic generation..."
    }
    func generatePlaylist(_ path: String)
    {
        generator = MosaicGenerator(debug: false, renderingMode: .auto, maxConcurrentOperations: 20, saveAtRoot: saveAtRoot,separate: seperate, summary: summary)
        isProcessing = true
        statusMessage1 = "Starting playlist generation..."
        var TotalCount: Double = 0.0
        let startTime = CFAbsoluteTimeGetCurrent()
        generator?.setProgressHandlerG { [weak self] progress in
            DispatchQueue.main.async {
                TotalCount = self?.generator?.getProgressSize() ?? 0.0
                
                //self?.progressG = progress
                let duration = CFAbsoluteTimeGetCurrent() - startTime
                var itemsPerSecond = 0.0
                var estimatedTimeRemaining = 0.0
                
                
                var text = "Processing creating PL"
                self?.statusMessage1 = text
                
            }
        }
        Task {
            do {
                try await generator?.createM3U8Playlist(from: path)
            }
            DispatchQueue.main.async {
                self.statusMessage1 = "playlist generation completed successfully!"
                self.progressG = 0.0
                let notification = NSUserNotification()
                notification.title = "playlist Generation Complete"
                NSUserNotificationCenter.default.deliver(notification)
                self.isProcessing = false
            }
        }
    }
    func generatePlaylistDiff(_ path: String)
    {
        generator = MosaicGenerator(debug: false, renderingMode: .auto, maxConcurrentOperations: 20, saveAtRoot: saveAtRoot,separate: seperate, summary: summary)
        isProcessing = true
        statusMessage1 = "Starting playlist generation..."
        var TotalCount: Double = 0.0
        let startTime = CFAbsoluteTimeGetCurrent()
        generator?.setProgressHandlerG { [weak self] progress in
            DispatchQueue.main.async {
                TotalCount = self?.generator?.getProgressSize() ?? 0.0
                
                //self?.progressG = progress
                let duration = CFAbsoluteTimeGetCurrent() - startTime
                var itemsPerSecond = 0.0
                var estimatedTimeRemaining = 0.0
                
                
                var text = "Processing creating PL"
                self?.statusMessage1 = text
                
            }
        }
        Task {
            do {
                try await generator?.createM3U8PlaylistDiff(from: path)
            }
            DispatchQueue.main.async {
                self.statusMessage1 = "playlist generation completed successfully!"
                self.progressG = 0.0
                let notification = NSUserNotification()
                notification.title = "playlist Generation Complete"
                NSUserNotificationCenter.default.deliver(notification)
                self.isProcessing = false
            }
        }
    }
}








extension MosaicViewModel {
    var currentTheme: AppTheme {
        switch selectedMode {
        case .mosaic: return .mosaic
        case .preview: return .preview
        case .playlist: return .playlist
        }
    }
}
