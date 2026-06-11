//
//  FluxColorMath.swift
//  Gojo
//
//  Pure color math for the Flux night shift feature.
//  No AppKit/Defaults imports so it can be compiled standalone by tests.
//

import Foundation

struct FluxRGB: Equatable {
    var red: Double
    var green: Double
    var blue: Double
}

enum FluxColorMath {
    static let minKelvin: Double = 1000
    static let maxKelvin: Double = 6500

    /// f.lux-style human-readable name for a color temperature,
    /// e.g. "3400K (Halogen)" or "Normal (Daylight)" at the top of the range.
    static func descriptor(kelvin: Double) -> String {
        let k = min(max(kelvin, minKelvin), maxKelvin)
        if k >= 6450 { return "Normal (Daylight)" }
        let name: String
        switch k {
        case ..<2100: name = "Candle"
        case ..<2500: name = "Dim Incandescent"
        case ..<3000: name = "Incandescent"
        case ..<3800: name = "Halogen"
        case ..<4600: name = "Fluorescent"
        case ..<5700: name = "Sunlight"
        default: name = "Daylight"
        }
        return "\(Int(k.rounded()))K (\(name))"
    }

    /// Per-channel gamma scale factors (0...1) for a blackbody color temperature.
    /// Uses the Tanner Helland blackbody approximation, normalized so the
    /// brightest channel stays at 1 — gamma should only attenuate, never boost.
    static func whitePoint(kelvin: Double) -> FluxRGB {
        let clamped = min(max(kelvin, minKelvin), maxKelvin)
        let t = clamped / 100

        let red: Double
        if t <= 66 {
            red = 255
        } else {
            red = 329.698727446 * pow(t - 60, -0.1332047592)
        }

        let green: Double
        if t <= 66 {
            green = 99.4708025861 * log(t) - 161.1195681661
        } else {
            green = 288.1221695283 * pow(t - 60, -0.0755148492)
        }

        let blue: Double
        if t >= 66 {
            blue = 255
        } else if t <= 19 {
            blue = 0
        } else {
            blue = 138.5177312231 * log(t - 10) - 305.0447927307
        }

        let r = min(max(red, 0), 255)
        let g = min(max(green, 0), 255)
        let b = min(max(blue, 0), 255)
        let brightest = max(r, max(g, b))
        guard brightest > 0 else { return FluxRGB(red: 1, green: 1, blue: 1) }

        return FluxRGB(red: r / brightest, green: g / brightest, blue: b / brightest)
    }
}
