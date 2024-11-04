//
//  DensityConfig.swift
//  MZBar
//
//  Created by Francois on 04/11/2024.
//


import Foundation

/// Configuration for frame extraction density
public struct DensityConfig {
    /// Factor to adjust extraction density
    public let factor: Double
    
    /// Multiplier for number of extracts
    public let extractsMultiplier: Double
    
    /// Creates density configuration from a string identifier
    /// - Parameter density: Density identifier (XXS, XS, S, M, L, XL, XXL)
    public static func from(_ density: String) -> DensityConfig {
        switch density.lowercased() {
        case "xxl": return DensityConfig(factor: 4.0, extractsMultiplier: 0.25)
        case "xl":  return DensityConfig(factor: 3.0, extractsMultiplier: 0.5)
        case "l":   return DensityConfig(factor: 2.0, extractsMultiplier: 0.75)
        case "m":   return DensityConfig(factor: 1.0, extractsMultiplier: 1.0)
        case "s":   return DensityConfig(factor: 0.75, extractsMultiplier: 1.5)
        case "xs":  return DensityConfig(factor: 0.5, extractsMultiplier: 2.0)
        case "xxs": return DensityConfig(factor: 0.25, extractsMultiplier: 3.0)
        default:    return DensityConfig(factor: 1.0, extractsMultiplier: 1.0)
        }
    }
    
    /// Available density options
    public static let availableDensities = ["XXS", "XS", "S", "M", "L", "XL", "XXL"]
    
    /// Initialize with custom values
    /// - Parameters:
    ///   - factor: Factor to adjust extraction density
    ///   - extractsMultiplier: Multiplier for number of extracts
    public init(factor: Double, extractsMultiplier: Double) {
        self.factor = factor
        self.extractsMultiplier = extractsMultiplier
    }
}

// MARK: - Helper Extensions
extension DensityConfig {
    /// Validates if a density string is valid
    /// - Parameter density: Density string to validate
    /// - Returns: Boolean indicating if density is valid
    public static func isValid(_ density: String) -> Bool {
        return availableDensities.contains(density.uppercased())
    }
    
    /// Default density configuration (Medium)
    public static let `default` = DensityConfig.from("M")
}

extension DensityConfig {
    /// Raw string value of the density
    public var rawValue: String {
        if factor == 4.0 { return "XXL" }
        if factor == 3.0 { return "XL" }
        if factor == 2.0 { return "L" }
        if factor == 1.0 { return "M" }
        if factor == 0.75 { return "S" }
        if factor == 0.5 { return "XS" }
        if factor == 0.25 { return "XXS" }
        return "M"
    }
}

