//
//  LiquidGlassNotchBackground.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import Defaults
import SwiftUI

/// Defaults and bounds for the surface parameters, shared by the renderer and the
/// Appearance pane so a slider can never describe a value the surface cannot take.
enum LiquidGlassParameters {
    static let refractionRange: ClosedRange<Double> = 0...100
    static let blurRange: ClosedRange<Double> = 0...30
    static let dispersionRange: ClosedRange<Double> = 0...15
    static let lensHeightRange: ClosedRange<Double> = 10...60
    static let coreHeightRange: ClosedRange<Double> = 20...80
    static let fadeSoftnessRange: ClosedRange<Double> = 10...100
    static let floorTransparencyRange: ClosedRange<Double> = 0...0.50
}

/// The notch surface: a refraction backdrop with a black scrim on top of it.
///
/// The scrim is what keeps the camera housing concealed, so the backdrop can stay
/// mounted across the open/close morph instead of crossfading — while the notch is
/// short the scrim is fully opaque and the result is plain black.
struct LiquidGlassNotchBackground: View {
    let shape: NotchShape
    let topRadius: CGFloat
    let bottomRadius: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Default(.enableLiquidGlass) var enableLiquidGlass
    @Default(.glassRefraction) var refraction
    @Default(.glassBlur) var blur
    @Default(.glassDispersion) var dispersion
    @Default(.glassLensHeight) var lensHeight
    @Default(.glassCoreHeight) var coreHeight
    @Default(.glassFadeSoftness) var fadeSoftness
    @Default(.glassFloorTransparency) var floorTransparency

    var body: some View {
        if enableLiquidGlass && !reduceTransparency && LiquidGlassAvailability.isSupported {
            ZStack {
                LiquidGlassBackdropRepresentable(
                    refraction: refraction,
                    lensHeight: lensHeight,
                    blur: blur,
                    aberration: dispersion,
                    topRadius: topRadius,
                    bottomRadius: bottomRadius
                )
                .clipShape(shape)

                NotchBlackFadeScrim(
                    shape: shape,
                    // shortcut: a core shorter than the closed notch lets the glass
                    // show while closed; clamp to the closed height if that matters.
                    coreHeight: coreHeight,
                    fadeSoftness: fadeSoftness,
                    floorTransparency: floorTransparency
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
