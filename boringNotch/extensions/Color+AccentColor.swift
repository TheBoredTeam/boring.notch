//
//  Color+AccentColor.swift
//  boringNotch
//
//  Created by Alexander on 2025-10-24.
//

import SwiftUI
import Defaults

extension Color {
    static var effectiveAccent: Color {
        if Defaults[.useCustomAccentColor],
           let colorData = Defaults[.customAccentColorData],
           let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
            return Color(nsColor: nsColor)
        }
        return .accentColor
    }
    
    /// Returns a darker version of the accent color suitable for backgrounds
    static var effectiveAccentBackground: Color {
        if Defaults[.useCustomAccentColor],
           let colorData = Defaults[.customAccentColorData],
           let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
            return Color(nsColor: nsColor.withSystemEffect(.disabled))
        }
        return Color.effectiveAccent.opacity(0.25)
    }
    
    static func interpolate(
        from: Color,
        to: Color,
        percent t: Double,
        in env: EnvironmentValues
    ) -> Color {
        let t = max(0, min(t, 1))  // clamp

        let c1 = from.resolve(in: env)
        let c2 = to.resolve(in: env)

        let r = c1.red   + (c2.red   - c1.red)   * Float(t)
        let g = c1.green + (c2.green - c1.green) * Float(t)
        let b = c1.blue  + (c2.blue  - c1.blue)  * Float(t)
        let a = c1.opacity + (c2.opacity - c1.opacity) * Float(t)

        return Color(red: Double(r), green: Double(g), blue: Double(b), opacity: Double(a))
    }
}

extension NSColor {
    static var effectiveAccent: NSColor {
        if Defaults[.useCustomAccentColor],
           let colorData = Defaults[.customAccentColorData],
           let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
            return nsColor
        }
        return NSColor.controlAccentColor
    }
    
    /// Returns a darker version of the accent color as NSColor suitable for backgrounds
    static var effectiveAccentBackground: NSColor {
        if Defaults[.useCustomAccentColor],
           let colorData = Defaults[.customAccentColorData],
           let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
            return nsColor.withSystemEffect(.disabled)
        }
        return NSColor.controlAccentColor.withAlphaComponent(0.25)
    }
}
