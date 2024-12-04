//
//  PlaylistGenerator.swift
//  MZBar
//
//  Created by Francois on 02/11/2024.
//




@preconcurrency import Foundation
import AVFoundation
import os.log
public typealias FileDiscoveryProgress = (Int) -> Void


/// Responsible for generating various types of playlists from video collections
public final class PlaylistGenerator {
    private let logger = Logger(subsystem: "com.mosaic.generation", category: "PlaylistGenerator")
        // Add property to store progress handler
    private var discoveryProgress: FileDiscoveryProgress?
    private var currentQuery: NSMetadataQuery?
    private var isCancelled = false
    
    // Add method to set progress handler
    public func setDiscoveryProgress(_ handler: @escaping FileDiscoveryProgress) {
        self.discoveryProgress = handler
    }

    public func cancelDiscovery() {
        isCancelled = true
        currentQuery?.stop()
        currentQuery = nil
    }

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
    
    private let videoTypes = [
        "public.mpeg-4",
        "public.movie",
        "public.avi",
        "public.mp4",
        "com.apple.quicktime-movie"
    ]
    
    private func findVideoFilesFallback(in directory: URL) throws -> [URL] {
        let fileManager = FileManager.default
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .typeIdentifierKey]
        
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        ) else {
            throw NSError(domain: "com.mosaic.generation", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to create directory enumerator"
            ])
        }
        
        var videos: [URL] = []
        
        for case let fileURL as URL in enumerator {
            guard !isCancelled else { break }
            
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: Set(resourceKeys))
                guard resourceValues.isRegularFile == true,
                      let typeIdentifier = resourceValues.typeIdentifier else { continue }
                
                if videoTypes.contains(typeIdentifier) && 
                   !fileURL.lastPathComponent.lowercased().contains("amprv") {
                    videos.append(fileURL)
                    discoveryProgress?(videos.count)
                }
            } catch {
                logger.error("Error reading file attributes: \(error.localizedDescription)")
                continue
            }
        }
        
        return videos
    }
    
    public func findVideoFiles(in directory: URL) async throws -> [URL] {
        isCancelled = false
        let query = NSMetadataQuery()
        currentQuery = query
        
        let typePredicates = videoTypes.map { type in
            NSPredicate(format: "kMDItemContentTypeTree == %@", type)
        }
        
        let typePredicate = NSCompoundPredicate(orPredicateWithSubpredicates: typePredicates)
        query.predicate = typePredicate
        query.searchScopes = [directory]
        query.sortDescriptors = [NSSortDescriptor(key: "kMDItemContentCreationDate", ascending: true)]

        return try await withCheckedThrowingContinuation { @Sendable (continuation) in
            var updateObserver: NSObjectProtocol?
            var completionObserver: NSObjectProtocol?
            
            // Add timeout handler
            let timeoutWork = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                query.stop()
                if let updateObserver = updateObserver {
                    NotificationCenter.default.removeObserver(updateObserver)
                }
                if let completionObserver = completionObserver {
                    NotificationCenter.default.removeObserver(completionObserver)
                }
                
                // Use fallback method
                logger.warning("NSMetadataQuery timed out, using fallback method")
                do {
                    let fallbackResults = try self.findVideoFilesFallback(in: directory)
                    continuation.resume(returning: fallbackResults)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            
            updateObserver = NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryGatheringProgress,
                object: query,
                queue: .main
            ) { [weak self] _ in
                guard let self = self else { return }
                if self.isCancelled {
                    query.stop()
                    if let updateObserver = updateObserver {
                        NotificationCenter.default.removeObserver(updateObserver)
                    }
                    if let completionObserver = completionObserver {
                        NotificationCenter.default.removeObserver(completionObserver)
                    }
                    continuation.resume(returning: [])
                    return
                }
                let count = query.results.count
                self.discoveryProgress?(count)
            }
            
            completionObserver = NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: query,
                queue: .main
            ) { [weak self] _ in
                timeoutWork.cancel()  // Cancel timeout if query completes successfully
                guard let self = self, !self.isCancelled else {
                    if let updateObserver = updateObserver {
                        NotificationCenter.default.removeObserver(updateObserver)
                    }
                    if let completionObserver = completionObserver {
                        NotificationCenter.default.removeObserver(completionObserver)
                    }
                    continuation.resume(returning: [])
                    return
                }
                
                let videos = (query.results as! [NSMetadataItem]).compactMap { item -> URL? in
                    guard let path = item.value(forAttribute: "kMDItemPath") as? String else {
                        return nil
                    }
                    let url = URL(fileURLWithPath: path)
                    return url.lastPathComponent.lowercased().contains("amprv") ? nil : url
                }
                
                if let updateObserver = updateObserver {
                    NotificationCenter.default.removeObserver(updateObserver)
                }
                if let completionObserver = completionObserver {
                    NotificationCenter.default.removeObserver(completionObserver)
                }
                
                continuation.resume(returning: videos)
                query.stop()
                self.currentQuery = nil
            }
            
            DispatchQueue.main.async {
                query.start()
                // Set 5 second timeout
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: timeoutWork)
            }
        }
    }
    
    /// Generate playlist for videos between specified dates
    /// - Parameters:
    ///   - startDate: Start date
    ///   - endDate: End date
    ///   - outputDirectory: Directory for playlist output
    /// - Returns: URL of generated playlist
    public func generateDateRangePlaylist(
        from startDate: Date,
        to endDate: Date,
        outputDirectory: URL
    ) async throws -> URL {
        logger.debug("Generating playlist for videos between \(startDate) and \(endDate)")
        
        let query = NSMetadataQuery()
        let datePredicate = NSPredicate(
            format: "kMDItemContentCreationDate >= %@ AND kMDItemContentCreationDate < %@",
            startDate as NSDate,
            endDate as NSDate
        )
        
        let typePredicates = videoTypes.map { type in
            NSPredicate(format: "kMDItemContentTypeTree == %@", type)
        }
        
        let typePredicate = NSCompoundPredicate(orPredicateWithSubpredicates: typePredicates)
        query.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, typePredicate])
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        query.sortDescriptors = [.init(key: "kMDItemContentCreationDate", ascending: true)]

        let videos = try await withCheckedThrowingContinuation { @Sendable (continuation) in
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
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let playlistName = "\(dateFormatter.string(from: startDate))-\(dateFormatter.string(from: endDate)).m3u8"
        
        let playlistURL = outputDirectory
            .appendingPathComponent("daterange", isDirectory: true)
            .appendingPathComponent(playlistName)
        
        let content = try await generatePlaylistContent(from: videos)
        try await createDirectory(at: playlistURL.deletingLastPathComponent())
        try await savePlaylist(content: content, to: playlistURL)
        
        return playlistURL
    }

    /// Generate duration-based playlists for videos between specified dates
    /// - Parameters:
    ///   - startDate: Start date
    ///   - endDate: End date
    ///   - outputDirectory: Directory for playlist output
    /// - Returns: Dictionary mapping duration categories to playlist URLs
    public func generateDateRangeDurationPlaylists(
        from startDate: Date,
        to endDate: Date,
        outputDirectory: URL
    ) async throws -> [DurationCategory: URL] {
        logger.debug("Generating duration-based playlists for videos between \(startDate) and \(endDate)")
        
        // Find videos in date range
        let query = NSMetadataQuery()
        let datePredicate = NSPredicate(
            format: "kMDItemContentCreationDate >= %@ AND kMDItemContentCreationDate < %@",
            startDate as NSDate,
            endDate as NSDate
        )
        
        let typePredicates = videoTypes.map { type in
            NSPredicate(format: "kMDItemContentTypeTree == %@", type)
        }
        
        let typePredicate = NSCompoundPredicate(orPredicateWithSubpredicates: typePredicates)
        query.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, typePredicate])
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        query.sortDescriptors = [.init(key: "kMDItemContentCreationDate", ascending: true)]
        
        let videos = try await withCheckedThrowingContinuation { @Sendable (continuation) in
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
        
        // Categorize videos by duration
        var categorizedVideos: [DurationCategory: [URL]] = [:]
        
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
        
        // Generate playlists for each category
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateRange = "\(dateFormatter.string(from: startDate))-\(dateFormatter.string(from: endDate))"
        
        var results: [DurationCategory: URL] = [:]
        
        for (category, videos) in categorizedVideos {
            let playlistName = "daterange-\(dateRange)-\(category.rawValue).m3u8"
            let playlistURL = outputDirectory
                .appendingPathComponent("daterange", isDirectory: true)
                .appendingPathComponent(playlistName)
            
            let content = try await generatePlaylistContent(from: videos)
            try await createDirectory(at: playlistURL.deletingLastPathComponent())
            try await savePlaylist(content: content, to: playlistURL)
            
            results[category] = playlistURL
        }
        
        return results
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
        query.sortDescriptors = [.init(key: "kMDItemContentCreationDate", ascending: true)]

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
            let content = try String(contentsOf: inputURL, encoding: .utf8).removingPercentEncoding!
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


