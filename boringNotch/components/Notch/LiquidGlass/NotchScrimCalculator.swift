//
//  NotchScrimCalculator.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation
import SwiftUI

struct NotchScrimCalculator {
    /// Gradient stops for the scrim that hides the physical camera housing: solid
    /// black through `coreHeight`, then a quadratic ease-out into the glass.
    ///
    /// - Parameters:
    ///   - totalHeight: Height of the notch surface right now, animating or static.
    ///   - coreHeight: Top region that stays fully opaque, in points.
    ///   - fadeSoftness: Downward transition range into glass, in points.
    ///   - floorTransparency: Bottom opacity floor, so the lowest band keeps a
    ///     black wash under the content instead of going fully clear.
    static func hardwareScrimStops(
        totalHeight: CGFloat,
        coreHeight: CGFloat,
        fadeSoftness: CGFloat,
        floorTransparency: CGFloat
    ) -> [Gradient.Stop] {
        // At or below the camera core the whole surface sits over the hardware
        // cutout, so it is solid black — this is also the closed notch.
        guard totalHeight > coreHeight else {
            return [
                .init(color: .black, location: 0.0),
                .init(color: .black, location: 1.0)
            ]
        }

        let coreLoc = coreHeight / totalHeight
        let fadeEndLoc = min(coreLoc + (fadeSoftness / totalHeight), 1.0)
        let floor = Double(min(max(floorTransparency, 0.0), 0.50))

        let mid1 = coreLoc + (fadeEndLoc - coreLoc) * 0.35
        let mid2 = coreLoc + (fadeEndLoc - coreLoc) * 0.70

        return [
            .init(color: .black, location: 0.0),
            .init(color: .black, location: coreLoc),
            .init(color: .black.opacity(0.65), location: mid1),
            .init(color: .black.opacity(0.18), location: mid2),
            .init(color: .black.opacity(floor), location: fadeEndLoc),
            .init(color: .black.opacity(floor), location: 1.00)
        ]
    }
}
