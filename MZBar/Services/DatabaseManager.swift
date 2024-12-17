import SQLite
import Foundation
class DatabaseManager {
    static let shared = DatabaseManager()
    private var db: Connection = try! Connection()

    private init() {
        initializeDatabase()
    }

    private func initializeDatabase() {
        do {
            // Set up the database connection
            let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
            db = try Connection("\(path)/mosaic_metadata.sqlite3")

            // Create the mosaics table if it doesn't exist
            let mosaics = Table("mosaics")
            let mosaicId = SQLite.Expression<Int64>("mosaic_id")
            let movieFilePath = SQLite.Expression<String>("movie_file_path")
            let mosaicFilePath = SQLite.Expression<String>("mosaic_file_path")
            let size = SQLite.Expression<String>("size")
            let density = SQLite.Expression<String>("density")
            let folderHierarchy = SQLite.Expression<String>("folder_hierarchy")
            let hash = SQLite.Expression<String>("hash")
            // New metadata columns
            let duration = SQLite.Expression<Double>("duration")
            let resolutionWidth = SQLite.Expression<Double>("resolution_width")
            let resolutionHeight = SQLite.Expression<Double>("resolution_height")
            let codec = SQLite.Expression<String>("codec")
            let videoType = SQLite.Expression<String>("video_type")
            let creationDate = SQLite.Expression<String>("creation_date")
  
            try db.run(mosaics.create(ifNotExists: true) { t in
                t.column(mosaicId, primaryKey: .autoincrement)
                t.column(movieFilePath)
                t.column(mosaicFilePath)
                t.column(size)
                t.column(density)
                t.column(folderHierarchy)
                t.column(hash, unique: true)
                t.column(duration)
                t.column(resolutionWidth)
                t.column(resolutionHeight)
                t.column(codec)
                t.column(videoType)
                t.column(creationDate)
            })
        } catch {
            print("Failed to initialize database: \(error)")
        }
    }

    func insertMosaicMetadata(
        movieFilePath: String,
        mosaicFilePath: String,
        size: String,
        density: String,
        folderHierarchy: String,
        hash: String,
        metadata: VideoMetadata
    ) {
        do {
            let mosaics = Table("mosaics")
            let movieFilePathExp = SQLite.Expression<String>("movie_file_path")
            let mosaicFilePathExp = SQLite.Expression<String>("mosaic_file_path")
            let sizeExp = SQLite.Expression<String>("size")
            let densityExp = SQLite.Expression<String>("density")
            let folderHierarchyExp = SQLite.Expression<String>("folder_hierarchy")
            let hashExp = SQLite.Expression<String>("hash")
            let durationExp = SQLite.Expression<Double>("duration")
            let resolutionWidthExp = SQLite.Expression<Double>("resolution_width")
            let resolutionHeightExp = SQLite.Expression<Double>("resolution_height")
            let codecExp = SQLite.Expression<String>("codec")
            let videoTypeExp = SQLite.Expression<String>("video_type")
            let creationDateExp = SQLite.Expression<String>("creation_date")

            let insert = mosaics.insert(
                movieFilePathExp <- movieFilePath,
                mosaicFilePathExp <- mosaicFilePath,
                sizeExp <- size,
                densityExp <- density,
                folderHierarchyExp <- folderHierarchy,
                hashExp <- hash,
                durationExp <- metadata.duration,
                resolutionWidthExp <- Double(metadata.resolution.width),
                resolutionHeightExp <- Double(metadata.resolution.height),
                codecExp <- metadata.codec,
                videoTypeExp <- metadata.type,
                creationDateExp <- (metadata.creationDate ?? "Unknown")
            )
            try db.run(insert)
        } catch {
            print("Failed to insert mosaic metadata: \(error)")
        }
    }

    func isDuplicateMosaic(hash: String) -> Bool {
        do {
            let mosaics = Table("mosaics")
            let hashExp = SQLite.Expression<String>("hash")

            let query = mosaics.filter(hashExp == hash)
            let count = try db.scalar(query.count) ?? 0

            return count > 0
        } catch {
            print("Failed to check for duplicate mosaic: \(error)")
            return false
        }
    }

    func cleanDatabase() {
        do {
            let mosaics = Table("mosaics")
            let filePathExp = SQLite.Expression<String>("movie_file_path")

            for mosaic in try db.prepare(mosaics) {
                if let filePath = mosaic[filePathExp] as? String {
                    if !FileManager.default.fileExists(atPath: filePath) {
                        try db.run(mosaics.filter(filePathExp == filePath).delete())
                        print("Removed non-existent file entry: \(filePath)")
                    }
                }
            }
        } catch {
            print("Failed to clean database: \(error)")
        }
    }

    func fetchMosaicEntries() -> [MosaicEntry] {
        var entries: [MosaicEntry] = []
        do {
            let mosaics = Table("mosaics")
            let idExp = SQLite.Expression<Int64>("mosaic_id")
            let movieFilePathExp = SQLite.Expression<String>("movie_file_path")
            let mosaicFilePathExp = SQLite.Expression<String>("mosaic_file_path")
            let sizeExp = SQLite.Expression<String>("size")
            let densityExp = SQLite.Expression<String>("density")
            let folderHierarchyExp = SQLite.Expression<String>("folder_hierarchy")
            let hashExp = SQLite.Expression<String>("hash")
            let durationExp = SQLite.Expression<Double>("duration")
            let resolutionWidthExp = SQLite.Expression<Double>("resolution_width")
            let resolutionHeightExp = SQLite.Expression<Double>("resolution_height")
            let codecExp = SQLite.Expression<String>("codec")
            let videoTypeExp = SQLite.Expression<String>("video_type")
            let creationDateExp = SQLite.Expression<String>("creation_date")

            for mosaic in try db.prepare(mosaics) {
                let entry = MosaicEntry(
                    id: mosaic[idExp],
                    movieFilePath: mosaic[movieFilePathExp],
                    mosaicFilePath: mosaic[mosaicFilePathExp],
                    size: mosaic[sizeExp],
                    density: mosaic[densityExp],
                    folderHierarchy: mosaic[folderHierarchyExp],
                    hash: mosaic[hashExp],
                    duration: mosaic[durationExp],
                    resolutionWidth: mosaic[resolutionWidthExp],
                    resolutionHeight: mosaic[resolutionHeightExp],
                    codec: mosaic[codecExp],
                    videoType: mosaic[videoTypeExp],
                    creationDate: mosaic[creationDateExp]
                )
                entries.append(entry)
            }
        } catch {
            print("Failed to fetch mosaic entries: \(error)")
        }
        return entries
    }

    func fetchAlternativeVersions(for mosaic: MosaicEntry) -> [MosaicEntry] {
        var entries: [MosaicEntry] = []
        do {
            let mosaics = Table("mosaics")
            let movieFilePathExp = SQLite.Expression<String>("movie_file_path")
            
            // Fetch all entries with the same movie file path but different size/density
            let query = mosaics.filter(movieFilePathExp == mosaic.movieFilePath)
            
            for entry in try db.prepare(query) {
                let alternativeEntry = MosaicEntry(
                    id: entry[SQLite.Expression<Int64>("mosaic_id")],
                    movieFilePath: entry[movieFilePathExp],
                    mosaicFilePath: entry[SQLite.Expression<String>("mosaic_file_path")],
                    size: entry[SQLite.Expression<String>("size")],
                    density: entry[SQLite.Expression<String>("density")],
                    folderHierarchy: entry[SQLite.Expression<String>("folder_hierarchy")],
                    hash: entry[SQLite.Expression<String>("hash")],
                    duration: entry[SQLite.Expression<Double>("duration")],
                    resolutionWidth: entry[SQLite.Expression<Double>("resolution_width")],
                    resolutionHeight: entry[SQLite.Expression<Double>("resolution_height")],
                    codec: entry[SQLite.Expression<String>("codec")],
                    videoType: entry[SQLite.Expression<String>("video_type")],
                    creationDate: entry[SQLite.Expression<String>("creation_date")]
                )
                
                // Don't include the current version
                if alternativeEntry.id != mosaic.id {
                    entries.append(alternativeEntry)
                }
            }
        } catch {
            print("Failed to fetch alternative versions: \(error)")
        }
        return entries
    }
} 
