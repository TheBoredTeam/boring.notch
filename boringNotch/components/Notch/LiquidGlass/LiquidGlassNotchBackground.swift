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
    /// The scrim controls are capped at the open panel's height: past that the
    /// scrim covers the whole surface, so a larger value would change nothing.
    private static let scrimHeightCeiling = Double(openNotchSize.height)

    static let refractionRange: ClosedRange<Double> = 0...100
    static let blurRange: ClosedRange<Double> = 0...30
    static let dispersionRange: ClosedRange<Double> = 0...15
    static let lensHeightRange: ClosedRange<Double> = 10...60
    static let fadeStartRange: ClosedRange<Double> = 20...scrimHeightCeiling
    static let fadeEndOpacityRange: ClosedRange<Double> = 0...0.80
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
    /// Height of the closed notch surface, which the scrim always keeps opaque.
    let closedNotchHeight: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Default(.enableLiquidGlass) var enableLiquidGlass
    @Default(.glassRefraction) var refraction
    @Default(.glassBlur) var blur
    @Default(.glassDispersion) var dispersion
    @Default(.glassLensHeight) var lensHeight
    @Default(.glassFadeStart) var fadeStart
    @Default(.glassFadeEndOpacity) var fadeEndOpacity

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
                    fadeStart: fadeStart,
                    solidBlackHeight: closedNotchHeight,
                    fadeEndOpacity: fadeEndOpacity
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
    let fadeStart: CGFloat
    let solidBlackHeight: CGFloat
    let fadeEndOpacity: CGFloat

    var body: some View {
        GeometryReader { geo in
            let stops = NotchScrimCalculator.hardwareScrimStops(
                totalHeight: geo.size.height,
                fadeStart: fadeStart,
                solidBlackHeight: solidBlackHeight,
                fadeEndOpacity: fadeEndOpacity
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
