//
//  AppTheme.swift
//  MZBar
//
//  Created by Francois on 01/11/2024.
//
import SwiftUI


enum AppTheme {
    struct ThemeColors {
        let primary: Color
        let background: Color
        let accent: Color
        let surfaceBackground: Color
    }
    
    case mosaic
    case preview
    case playlist
    
    var colors: ThemeColors {
        switch self {
        case .mosaic:
            return ThemeColors(
                // Soft blue-lavender
                primary: Color(.sRGB, red: 0.545, green: 0.624, blue: 0.910, opacity: 1.0),
                // Very light lavender
                background: Color(.sRGB, red: 0.941, green: 0.949, blue: 0.980, opacity: 1.0),
                // Deeper blue-lavender
                accent: Color(.sRGB, red: 0.420, green: 0.510, blue: 0.820, opacity: 1.0),
                // Light lavender surface
                surfaceBackground: Color(.sRGB, red: 0.902, green: 0.918, blue: 0.969, opacity: 1.0)
            )
            
        case .preview:
            return ThemeColors(
                // Soft sage green
                primary: Color(.sRGB, red: 0.573, green: 0.725, blue: 0.659, opacity: 1.0),
                // Very light mint
                background: Color(.sRGB, red: 0.941, green: 0.969, blue: 0.957, opacity: 1.0),
                // Deeper sage
                accent: Color(.sRGB, red: 0.451, green: 0.612, blue: 0.537, opacity: 1.0),
                // Light mint surface
                surfaceBackground: Color(.sRGB, red: 0.902, green: 0.949, blue: 0.925, opacity: 1.0)
            )
            
        case .playlist:
            return ThemeColors(
                // Soft coral
                primary: Color(.sRGB, red: 0.910, green: 0.627, blue: 0.545, opacity: 1.0),
                // Very light peach
                background: Color(.sRGB, red: 0.980, green: 0.949, blue: 0.941, opacity: 1.0),
                // Deeper coral
                accent: Color(.sRGB, red: 0.820, green: 0.498, blue: 0.420, opacity: 1.0),
                // Light peach surface
                surfaceBackground: Color(.sRGB, red: 0.969, green: 0.902, blue: 0.902, opacity: 1.0)
            )
        }
    }
    
}
