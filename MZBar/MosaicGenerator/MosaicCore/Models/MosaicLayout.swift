import Foundation
import CoreGraphics

/// Represents the layout of thumbnails in a mosaic
public struct MosaicLayout {
    /// Number of rows in the mosaic
    public let rows: Int
    
    /// Number of columns in the mosaic
    public let cols: Int
    
    /// Base size for thumbnails
    public let thumbnailSize: CGSize
    
    /// Positions for each thumbnail in the mosaic
    public let positions: [(x: Int, y: Int)]
    
    /// Total number of thumbnails
    public let thumbCount: Int
    
    /// Individual sizes for each thumbnail
    public let thumbnailSizes: [CGSize]
    
    /// Overall size of the mosaic
    public let mosaicSize: CGSize
    
    /// Initialize a new mosaic layout
    /// - Parameters:
    ///   - rows: Number of rows
    ///   - cols: Number of columns
    ///   - thumbnailSize: Base size for thumbnails
    ///   - positions: Array of positions for each thumbnail
    ///   - thumbCount: Total number of thumbnails
    ///   - thumbnailSizes: Array of individual thumbnail sizes
    ///   - mosaicSize: Overall mosaic size
    public init(
        rows: Int,
        cols: Int,
        thumbnailSize: CGSize,
        positions: [(x: Int, y: Int)],
        thumbCount: Int,
        thumbnailSizes: [CGSize],
        mosaicSize: CGSize
    ) {
        self.rows = rows
        self.cols = cols
        self.thumbnailSize = thumbnailSize
        self.positions = positions
        self.thumbCount = thumbCount
        self.thumbnailSizes = thumbnailSizes
        self.mosaicSize = mosaicSize
    }
}

// MARK: - Helper Methods
extension MosaicLayout {
    /// Calculates the position in the mosaic for a given index
    /// - Parameter index: Thumbnail index
    /// - Returns: Position in the mosaic
    public func position(for index: Int) -> (x: Int, y: Int)? {
        guard index < positions.count else { return nil }
        return positions[index]
    }
    
    /// Gets the size for a specific thumbnail
    /// - Parameter index: Thumbnail index
    /// - Returns: Size of the thumbnail
    public func thumbnailSize(at index: Int) -> CGSize? {
        guard index < thumbnailSizes.count else { return nil }
        return thumbnailSizes[index]
    }
}

// MARK: - Equatable
extension MosaicLayout: Equatable {
    public static func == (lhs: MosaicLayout, rhs: MosaicLayout) -> Bool {
        guard lhs.rows == rhs.rows,
              lhs.cols == rhs.cols,
              lhs.thumbnailSize == rhs.thumbnailSize,
              lhs.thumbCount == rhs.thumbCount,
              lhs.mosaicSize == rhs.mosaicSize,
              lhs.positions.count == rhs.positions.count,
              lhs.thumbnailSizes.count == rhs.thumbnailSizes.count else {
            return false
        }
        
        // Compare positions array elements
        for i in 0..<lhs.positions.count {
            if lhs.positions[i].x != rhs.positions[i].x ||
               lhs.positions[i].y != rhs.positions[i].y {
                return false
            }
        }
        
        // Compare thumbnailSizes array elements
        for i in 0..<lhs.thumbnailSizes.count {
            if lhs.thumbnailSizes[i] != rhs.thumbnailSizes[i] {
                return false
            }
        }
        
        return true
    }
}


// MARK: - Custom Debug String
extension MosaicLayout: CustomDebugStringConvertible {
    public var debugDescription: String {
        return """
        MosaicLayout:
        - Rows: \(rows)
        - Columns: \(cols)
        - Thumbnail Count: \(thumbCount)
        - Base Thumbnail Size: \(thumbnailSize)
        - Mosaic Size: \(mosaicSize)
        """
    }
}


