//
//  Signposted.swift
//  MZBar
//
//  Created by Francois on 08/11/2024.
//


import os.signpost
import Foundation

// MARK: - Signpost Property Wrapper
@propertyWrapper
struct Signposted<T> {
    private let name: StaticString
    private let log: OSLog
    private var value: T
    
    init(wrappedValue: T, name: StaticString, log: OSLog = .default) {
        self.value = wrappedValue
        self.name = name
        self.log = log
    }
    
    var wrappedValue: T {
        get { value }
        set {
            let signposter = OSSignposter(logHandle: log)
            let state = signposter.beginInterval(name)
            value = newValue
            signposter.endInterval(name, state)
        }
    }
}

// MARK: - Function Performance Tracking
@propertyWrapper
struct SignpostTracked {
    private let name: StaticString
    private let log: OSLog
    private let signposter: OSSignposter
    private var value: Any
    
    init<T>(wrappedValue: @escaping () async throws -> T, name: StaticString, log: OSLog = .default) {
        self.value = wrappedValue
        self.name = name
        self.log = log
        self.signposter = OSSignposter(logHandle: log)
    }
    
    var wrappedValue: Any {
        get { value }
        set { value = newValue }
    }
    
    var projectedValue: Any {
        get { value }
        set { value = newValue }
    }
}

// MARK: - Function Wrapper
func measurePerformance<T>(
    name: StaticString,
    log: OSLog = .default,
    operation: () async throws -> T
) async throws -> T {
    let signposter = OSSignposter(logHandle: log)
    let state = signposter.beginInterval(name)
    defer { signposter.endInterval(name, state) }
    return try await operation()
}

// MARK: - Convenient Logging Categories
extension OSLog {
    static let mosaic = OSLog(subsystem: "com.mosaic.generation", category: "MosaicGeneration")
    static let preview = OSLog(subsystem: "com.mosaic.generation", category: "PreviewGeneration")
    static let processing = OSLog(subsystem: "com.mosaic.generation", category: "Processing")
    static let layout = OSLog(subsystem: "com.mosaic.generation", category: "Layout")
}

// MARK: - Performance Metrics Protocol
protocol PerformanceTracking {
    var signposter: OSSignposter { get }
    func trackPerformance<T>(of operation: StaticString, operation: () async throws -> T) async throws -> T
}

extension PerformanceTracking {
    func trackPerformance<T>(
        of Operation: StaticString,
        operation: () async throws -> T
    ) async throws -> T {
        let state = signposter.beginInterval(Operation)
        defer { signposter.endInterval(Operation, state) }
        return try await operation()
    }
}
