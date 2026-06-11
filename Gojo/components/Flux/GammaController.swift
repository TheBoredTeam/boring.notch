//
//  GammaController.swift
//  Gojo
//
//  Applies Flux white-point scaling to all active displays. Each display's
//  ColorSync-calibrated gamma ramp is captured before it is first modified,
//  and the flux scale is multiplied into that ramp — so the user's display
//  calibration is preserved while flux is active. WindowServer reverts these
//  settings automatically when the process exits, but we restore explicitly.
//

import CoreGraphics
import Foundation

final class GammaController {
    private(set) var isModified = false

    private struct GammaTable {
        var red: [CGGammaValue]
        var green: [CGGammaValue]
        var blue: [CGGammaValue]
    }

    /// Calibrated ramps captured per display before we first touch them.
    /// Only cleared on restore(), so a display we have already modified is
    /// never re-captured (which would bake our tint into the "original").
    private var originalTables: [CGDirectDisplayID: GammaTable] = [:]

    func apply(_ rgb: FluxRGB) {
        var displayCount: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetActiveDisplayList(UInt32(displays.count), &displays, &displayCount) == .success,
              displayCount > 0
        else { return }

        for display in displays.prefix(Int(displayCount)) {
            guard let table = originalTable(for: display) else { continue }
            var red = table.red.map { $0 * CGGammaValue(rgb.red) }
            var green = table.green.map { $0 * CGGammaValue(rgb.green) }
            var blue = table.blue.map { $0 * CGGammaValue(rgb.blue) }
            CGSetDisplayTransferByTable(display, UInt32(red.count), &red, &green, &blue)
        }
        isModified = true
    }

    func restore() {
        guard isModified else { return }
        CGDisplayRestoreColorSyncSettings()
        originalTables.removeAll()
        isModified = false
    }

    private func originalTable(for display: CGDirectDisplayID) -> GammaTable? {
        if let cached = originalTables[display] { return cached }

        let capacity = CGDisplayGammaTableCapacity(display)
        guard capacity > 0 else { return nil }

        var red = [CGGammaValue](repeating: 0, count: Int(capacity))
        var green = [CGGammaValue](repeating: 0, count: Int(capacity))
        var blue = [CGGammaValue](repeating: 0, count: Int(capacity))
        var sampleCount: UInt32 = 0
        guard CGGetDisplayTransferByTable(display, capacity, &red, &green, &blue, &sampleCount) == .success,
              sampleCount > 0
        else { return nil }

        let table = GammaTable(
            red: Array(red.prefix(Int(sampleCount))),
            green: Array(green.prefix(Int(sampleCount))),
            blue: Array(blue.prefix(Int(sampleCount)))
        )
        originalTables[display] = table
        return table
    }
}
