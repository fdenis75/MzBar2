//
//  AppTheme.swift
//  MZBar
//
//  Created by Francois on 01/11/2024.
//
import SwiftUI

struct ThemeColors {
    let primary: Color
    let accent: Color
    let background: Color
    let cardBackground: Color
    let surfaceBackground: Color
    let text: Color
    let secondaryText: Color
}

struct AppTheme {
    let colors: ThemeColors
    
    static let mosaic = AppTheme(colors: ThemeColors(
        primary: Color(hex: "73A5F5"),     // Bright blue from icon
        accent: Color(hex: "C3C4F5"),      // Purple accent from icon
        background: Color(.darkGray).opacity(0.9),
        cardBackground: Color(hex: "ECE8F5").opacity(0.9),
        surfaceBackground: Color(hex: "ECE8F5").opacity(0.9),
        text: .white,
        secondaryText: .accentColor
    ))
    
    static let preview = AppTheme(colors: ThemeColors(
        primary: Color(hex: "BA8EF6"),     // Lighter blue from icon
        accent: Color(hex: "DAB6F6"),      // Blue-purple blend
        background: Color(.darkGray).opacity(0.9),
        cardBackground: Color(hex: "F3E2F6").opacity(0.9),
        surfaceBackground: Color(hex: "F3E2F6").opacity(0.9),
        text: .white,
        secondaryText: .accentColor
    ))
    
    static let playlist = AppTheme(colors: ThemeColors(
        primary: Color(hex: "F28EAF"),     // Blue-purple from icon
        accent: Color(hex: "F8B6B3"),      // Pink-purple accent
        background: Color(.darkGray).opacity(0.9),
        cardBackground: Color(hex: "FEE2B5").opacity(0.9),
        surfaceBackground: Color(hex: "FEE2B5").opacity(0.9),
        text: .white,
        secondaryText: .accentColor
    ))
    
    init(colors: ThemeColors) {
        self.colors = colors
    }
    
    init(from mode: TabSelection) {
        switch mode {
        case .mosaic:
            self = .mosaic
        case .preview:
            self = .preview
        case .playlist:
            self = .playlist
        case .settings:
            self = .mosaic
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 1)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
