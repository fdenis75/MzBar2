//
//  PlaylistGenerator.swift
//  MZBar
//
//  Created by Francois on 02/11/2024.
//




@preconcurrency import Foundation
import AVFoundation
import os.log

/// Responsible for generating various types of playlists from video collections
public final class PlaylistGenerator {
    private let logger = Logger(subsystem: "com.mosaic.generation", category: "PlaylistGenerator")
    
    /// Duration categories for video classification
    public enum DurationCategory: String {
        case extraShort = "XS"  // 0-60s
        case short = "S"        // 60-300s
        case medium = "M"       // 300-900s
        case long = "L"        // 900-1800s
        case extraLong = "XL"   // 1800s+
        case unknown = "U"
        
        static func categorize(duration: Double) -> DurationCategory {
            switch duration {
            case -1.0:         return .unknown
            case 0..<60:     return .extraShort
            case 60..<300:   return .short
            case 300..<900:  return .medium
            case 900..<1800: return .long
            default:         return .extraLong
            }
        }
    }
    
    /// Generate a standard M3U8 playlist
    /// - Parameters:
    ///   - directory: Directory containing videos
    ///   - outputDirectory: Directory for playlist output
    /// - Returns: URL of generated playlist
    public func generateStandardPlaylist(
        from directory: URL,
        outputDirectory: URL
    ) async throws -> URL {
        logger.debug("Generating standard playlist from: \(directory.path)")
        
        let videos = try await findVideoFiles(in: directory)
        let content = try await generatePlaylistContent(from: videos)
        let playlistURL = outputDirectory
            .appendingPathComponent("0th",  isDirectory: true)
            .appendingPathComponent("playlists", isDirectory: true)
            .appendingPathComponent("\(directory.lastPathComponent).m3u8")
        try await createDirectory(at: playlistURL.deletingLastPathComponent())
        try await savePlaylist(content: content, to: playlistURL)
        return playlistURL
    }
    
    /// Generate duration-based playlists
    /// - Parameters:
    ///   - directory: Directory containing videos
    ///   - outputDirectory: Directory for playlist output
    /// - Returns: Dictionary of category and playlist URL
    public func generateDurationBasedPlaylists(
        from directory: URL,
        outputDirectory: URL
    ) async throws -> [DurationCategory: URL] {
        logger.debug("Generating duration-based playlists from: \(directory.path)")
        
        let videos = try await findVideoFiles(in: directory)
        var categorizedVideos: [DurationCategory: [URL]] = [:]
        
        // Categorize videos by duration
        for video in videos {
            let asset = AVURLAsset(url: video)
            var duration = 0.0
            if try await !asset.load(.isPlayable) {
                    duration = -1
                logger.error("Failed to load asset: \(video.path)")
            }
            else
            { duration = try await asset.load(.duration).seconds }
            let category = DurationCategory.categorize(duration: duration)
            categorizedVideos[category, default: []].append(video)
        }
        
        // Generate playlist for each category
        var playlists: [DurationCategory: URL] = [:]
        for (category, videos) in categorizedVideos {
            let content = try await generatePlaylistContent(from: videos)
            let playlistURL = outputDirectory
                .appendingPathComponent("0th",  isDirectory: true)
                .appendingPathComponent("playlists", isDirectory: true)
                .appendingPathComponent("\(category.rawValue)-\(directory.lastPathComponent).m3u8")
            
            try await createDirectory(at: playlistURL.deletingLastPathComponent())
            try await savePlaylist(content: content, to: playlistURL)
            playlists[category] = playlistURL
        }
        
        return playlists
    }
    
    /// Generate today's playlist
    /// - Parameter outputDirectory: Directory for playlist output
    /// - Returns: URL of generated playlist
    public func generateTodayPlaylist(
        outputDirectory: URL
    ) async throws -> URL {
        logger.debug("Generating playlist for today's videos")
        
        let videos = try await findTodayVideos()
        let content = try await generatePlaylistContent(from: videos)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateFolderName = dateFormatter.string(from: Date())
        
        let playlistURL = outputDirectory
            .appendingPathComponent(dateFolderName)
            .appendingPathComponent("\(dateFolderName).m3u8")
        
        try await createDirectory(at: playlistURL.deletingLastPathComponent())
        try await savePlaylist(content: content, to: playlistURL)
        
        return playlistURL
    }
    
    // MARK: - Private Methods
    
    public func findVideoFiles(in directory: URL) async throws -> [URL] {
      /* let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        
        var videos: [URL] = []
        while let fileURL = enumerator?.nextObject() as? URL {
            let fileExtension = fileURL.pathExtension.lowercased()
            let isVideo = ["mp4", "mov", "avi", "mkv", "m4v", "webm", "ts"].contains(fileExtension)
            if isVideo && !fileURL.lastPathComponent.lowercased().contains("amprv") {
                videos.append(fileURL)
            }
        }*/
       let query = NSMetadataQuery()
       let calendar = Calendar.current
       let today = calendar.startOfDay(for: Date())
       let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
       
        let type = videoTypes
       
     
       
       let typePredicates = videoTypes.map { type in
           NSPredicate(format: "kMDItemContentTypeTree == %@", type)
       }
       
       let typePredicate = NSCompoundPredicate(orPredicateWithSubpredicates: typePredicates)
       query.predicate = typePredicate
        query.searchScopes = [directory]
       
       return try await withCheckedThrowingContinuation { @Sendable (continuation) in
           NotificationCenter.default.addObserver(
               forName: .NSMetadataQueryDidFinishGathering,
               object: query,
               queue: .main
           ) { _ in
               let videos = (query.results as! [NSMetadataItem]).compactMap { item -> URL? in
                   guard let path = item.value(forAttribute: "kMDItemPath") as? String else {
                       return nil
                   }
                   let url = URL(fileURLWithPath: path)
                   return url.lastPathComponent.lowercased().contains("amprv") ? nil : url
               }
               continuation.resume(returning: videos)
               query.stop()
           }
           
           DispatchQueue.main.async {
               query.start()
           }
       }
        
    }
    
    public func findTodayVideos() async throws -> [URL] {
        let query = NSMetadataQuery()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        
        let datePredicate = NSPredicate(
            format: "kMDItemContentCreationDate >= %@ AND kMDItemContentCreationDate < %@",
            today as NSDate,
            tomorrow as NSDate
        )
        
        let type = videoTypes

        
        let typePredicates = videoTypes.map { type in
            NSPredicate(format: "kMDItemContentTypeTree == %@", type)
        }
        
        let typePredicate = NSCompoundPredicate(orPredicateWithSubpredicates: typePredicates)
        query.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, typePredicate])
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        
        return try await withCheckedThrowingContinuation { @Sendable (continuation) in
            NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: query,
                queue: .main
            ) { _ in
                let videos = (query.results as! [NSMetadataItem]).compactMap { item -> URL? in
                    guard let path = item.value(forAttribute: "kMDItemPath") as? String else {
                        return nil
                    }
                    let url = URL(fileURLWithPath: path)
                    return (url.lastPathComponent.lowercased().contains("amprv") || url.pathExtension.lowercased().contains("rmvb")) ? nil : url
                }
                continuation.resume(returning: videos)
                query.stop()
            }
            
            DispatchQueue.main.async {
                query.start()
            }
        }
    }
    
    private func generatePlaylistContent(from videos: [URL]) async throws -> String {
        var content = "#EXTM3U\n"
        for video in videos {
            content += "#EXTINF:-1,\(video.lastPathComponent)\n"
            content += "\(video.path)\n"
        }
        return content
    }
    
    private func savePlaylist(content: String, to url: URL) async throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try content.write(to: url, atomically: true, encoding: .utf8)
        logger.info("Saved playlist: \(url.path)")
    }
    
    private func createDirectory(at url: URL) async throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }
}
extension PlaylistGenerator {
    /// Gets files from a specified path
    /// - Parameters:
    ///   - path: Input path to process
    /// - Returns: Array of video files
    public func getFiles(from path: String) async throws -> [(URL, URL)] {
        let inputURL = URL(fileURLWithPath: path)
        
        if path.lowercased().hasSuffix("m3u8") {
            // Handle M3U8 playlist files
            let content = try String(contentsOf: inputURL, encoding: .utf8)
            let urls = content.components(separatedBy: .newlines)
                .filter { !$0.hasPrefix("#") && !$0.isEmpty }
                .map { URL(fileURLWithPath: $0) }
            
            return urls.map { videoURL in
                let outputDir = videoURL.deletingLastPathComponent()
                    .appendingPathComponent(ThDir, isDirectory: true)
                return (videoURL, outputDir)
            }
        } else {
            // Handle directories
            let videos = try await findVideoFiles(in: inputURL)
            return videos.map { videoURL in
                let outputDir = videoURL.deletingLastPathComponent()
                    .appendingPathComponent(ThDir, isDirectory: true)
                return (videoURL, outputDir)
            }
        }
    }
}

