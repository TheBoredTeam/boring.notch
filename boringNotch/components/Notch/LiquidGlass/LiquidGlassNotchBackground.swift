//
//  LiquidGlassNotchBackground.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import Defaults
import SwiftUI

/// The notch surface: a refraction backdrop with a black scrim on top of it.
///
/// The scrim is what keeps the camera housing concealed, so the backdrop can stay
/// mounted across the open/close morph instead of crossfading — while the notch is
/// short the scrim is fully opaque and the result is plain black.
struct LiquidGlassNotchBackground: View {
    let shape: NotchShape
    let topRadius: CGFloat
    let bottomRadius: CGFloat

    @Default(.enableLiquidGlass) var enableLiquidGlass

    private static let coreHeight: CGFloat = 80
    private static let fadeSoftness: CGFloat = 100
    private static let floorTransparency: CGFloat = 0.23

    private static let refraction: Double = 24
    private static let blur: Double = 0
    private static let dispersion: Double = 4
    private static let lensHeight: Double = 23

    var body: some View {
        if enableLiquidGlass && LiquidGlassAvailability.isSupported {
            ZStack {
                LiquidGlassBackdropRepresentable(
                    refraction: Self.refraction,
                    lensHeight: Self.lensHeight,
                    blur: Self.blur,
                    aberration: Self.dispersion,
                    topRadius: topRadius,
                    bottomRadius: bottomRadius
                )
                .clipShape(shape)

                NotchBlackFadeScrim(
                    shape: shape,
                    coreHeight: Self.coreHeight,
                    fadeSoftness: Self.fadeSoftness,
                    floorTransparency: Self.floorTransparency
                )
            }
        } else {
            Color.black
        }
    }
}

// MARK: - Scrim

struct NotchBlackFadeScrim: View {
    let shape: NotchShape
    let coreHeight: CGFloat
    let fadeSoftness: CGFloat
    let floorTransparency: CGFloat

    var body: some View {
        GeometryReader { geo in
            let stops = NotchScrimCalculator.hardwareScrimStops(
                totalHeight: geo.size.height,
                coreHeight: coreHeight,
                fadeSoftness: fadeSoftness,
                floorTransparency: floorTransparency
            )

            LinearGradient(
                stops: stops,
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(shape)
        }
    }
}
