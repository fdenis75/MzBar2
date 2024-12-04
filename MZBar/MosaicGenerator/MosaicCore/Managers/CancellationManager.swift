import Foundation

public final class CancellationManager {
    private var cancelledFiles: Set<String> = []
    private var isGlobalCancellation: Bool = false
    private let lock = NSLock()
    
    public static let shared = CancellationManager()
    
    private init() {}
    
    public func cancelFile(_ filename: String) {
        lock.lock()
        defer { lock.unlock() }
        cancelledFiles.insert(filename)
    }
    
    public func cancelAll() {
        lock.lock()
        defer { lock.unlock() }
        isGlobalCancellation = true
    }
    
    public func isFileCancelled(_ filename: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isGlobalCancellation || cancelledFiles.contains(filename)
    }
    
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        cancelledFiles.removeAll()
        isGlobalCancellation = false
    }
} 