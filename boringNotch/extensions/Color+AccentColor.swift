//
//  Color+AccentColor.swift
//  boringNotch
//
//  Created by Alexander on 2025-10-24.
//

import SwiftUI
import Defaults

/// Decodes the user's custom accent color, if custom accents are enabled.
private var customAccentNSColor: NSColor? {
    guard Defaults[.useCustomAccentColor],
          let colorData = Defaults[.customAccentColorData],
          let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData)
    else { return nil }
    return nsColor
}

extension Color {
    static var effectiveAccent: Color {
        if let nsColor = customAccentNSColor {
            return Color(nsColor: nsColor)
        }
        return .accentColor
    }

    /// Returns a darker version of the accent color suitable for backgrounds
    static var effectiveAccentBackground: Color {
        if let nsColor = customAccentNSColor {
            return Color(nsColor: nsColor.withSystemEffect(.disabled))
        }
        return Color.effectiveAccent.opacity(0.25)
    }
}

extension NSColor {
    static var effectiveAccent: NSColor {
        customAccentNSColor ?? NSColor.controlAccentColor
    }

    /// Returns a darker version of the accent color as NSColor suitable for backgrounds
    static var effectiveAccentBackground: NSColor {
        if let nsColor = customAccentNSColor {
            return nsColor.withSystemEffect(.disabled)
        }
        return NSColor.controlAccentColor.withAlphaComponent(0.25)
    }
}
