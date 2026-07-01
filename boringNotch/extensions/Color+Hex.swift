//
//  Color+Hex.swift
//  boringNotch
//
//  Hex <-> Color conversion used by the Screen Time widget (category colors are stored
//  as "#RRGGBB" strings so the underlying model stays free of SwiftUI types).
//

import SwiftUI

extension Color {
    /// Initialize from a "#RRGGBB" (or "RRGGBB") string. Falls back to gray on bad input.
    init(stHex hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else {
            self = .gray
            return
        }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }

    /// Serialize to "#RRGGBB" (sRGB). Returns "#888888" if components can't be read.
    func stHexString() -> String {
        guard let rgb = NSColor(self).usingColorSpace(.sRGB) else { return "#888888" }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
