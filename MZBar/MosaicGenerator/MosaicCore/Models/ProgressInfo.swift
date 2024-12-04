//
//  ProgressInfo.swift
//  MZBar
//
//  Created by Francois on 04/11/2024.
//


import Foundation
public struct FileProgress: Identifiable, Hashable {
    public let id: UUID
    let filename: String
    var progress: Double
    var stage: String
    var isComplete: Bool
    var isCancelled: Bool
    var outputURL: URL?
    
    init(filename: String) {
        self.id = UUID()
        self.filename = filename
        self.progress = 0.0
        self.stage = "Pending"
        self.isComplete = false
        self.isCancelled = false
        self.outputURL = nil
    }
    public static func == (lhs: FileProgress, rhs: FileProgress) -> Bool {
           lhs.id == rhs.id
       }
       
       public func hash(into hasher: inout Hasher) {
           hasher.combine(id)
       }
}


/// Information about processing progress
public struct ProgressInfo {
    public let progressType: ProgressType
    
    /// Current progress (0.0 - 1.0)
    public let progress: Double
    
    /// Currently processing file
    public let currentFile: String
    
    /// Number of processed files
    public let processedFiles: Int
    
    /// Total number of files to process
    public let totalFiles: Int
    
    /// Current processing stage
    public let currentStage: String
    
    /// Time elapsed since start
    public let elapsedTime: TimeInterval
    
    /// Estimated time remaining
    public let estimatedTimeRemaining: TimeInterval
    
    /// Number of skipped files
    public let skippedFiles: Int
    
    /// Number of files with errors
    public let errorFiles: Int
    
    /// Whether processing is currently running
    public let isRunning: Bool

     public let fileProgress: Double?
    
    public let fps: Double?
    
    /// Initialize progress information
    public init(
        progressType: ProgressType,
        progress: Double,
        currentFile: String,
        processedFiles: Int,
        totalFiles: Int,
        currentStage: String,
        elapsedTime: TimeInterval,
        estimatedTimeRemaining: TimeInterval,
        skippedFiles: Int,
        errorFiles: Int,
        isRunning: Bool, 
        fileProgress: Double?
    ) {
        self.progressType = progressType
        self.progress = progress
        self.currentFile = currentFile
        self.processedFiles = processedFiles
        self.totalFiles = totalFiles
        self.currentStage = currentStage
        self.elapsedTime = elapsedTime
        self.estimatedTimeRemaining = estimatedTimeRemaining
        self.skippedFiles = skippedFiles
        self.errorFiles = errorFiles
        self.isRunning = isRunning
        self.fileProgress = fileProgress
        self.fps = Double(processedFiles) / elapsedTime
    }
}

