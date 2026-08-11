//
//  NotchShape.swift
//  boringNotch
//
// Created by Kai Azim on 2023-08-24.
// Original source: https://github.com/MrKai77/DynamicNotchKit
// Modified by Alexander on 2025-05-18.

import SwiftUI

struct NotchShape: Shape {
    private var topCornerRadius: CGFloat
    private var bottomCornerRadius: CGFloat

    init(
        topCornerRadius: CGFloat? = nil,
        bottomCornerRadius: CGFloat? = nil
    ) {
        self.topCornerRadius = topCornerRadius ?? 6
        self.bottomCornerRadius = bottomCornerRadius ?? 14
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get {
            .init(
                topCornerRadius,
                bottomCornerRadius
            )
        }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tcr = topCornerRadius
        let bcr = bottomCornerRadius
        // How far the cubic control points reach along each tangent. ~0.55 gives
        // a near-circular arc; nudging it makes the flare ease in/out more
        // gradually so the bottom corners read as smooth, continuous curvature
        // rather than a tight quarter-circle.
        let k: CGFloat = 0.62

        // Top-left start.
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Top-left inner corner (small).
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + tcr, y: rect.minY + tcr),
            control: CGPoint(x: rect.minX + tcr, y: rect.minY)
        )

        // Left edge down.
        path.addLine(to: CGPoint(x: rect.minX + tcr, y: rect.maxY - bcr))

        // Bottom-left flare — cubic for smooth, continuous curvature.
        path.addCurve(
            to: CGPoint(x: rect.minX + tcr + bcr, y: rect.maxY),
            control1: CGPoint(x: rect.minX + tcr, y: rect.maxY - bcr * (1 - k)),
            control2: CGPoint(x: rect.minX + tcr + bcr * (1 - k), y: rect.maxY)
        )

        // Bottom edge.
        path.addLine(to: CGPoint(x: rect.maxX - tcr - bcr, y: rect.maxY))

        // Bottom-right flare — cubic.
        path.addCurve(
            to: CGPoint(x: rect.maxX - tcr, y: rect.maxY - bcr),
            control1: CGPoint(x: rect.maxX - tcr - bcr * (1 - k), y: rect.maxY),
            control2: CGPoint(x: rect.maxX - tcr, y: rect.maxY - bcr * (1 - k))
        )

        // Right edge up.
        path.addLine(to: CGPoint(x: rect.maxX - tcr, y: rect.minY + tcr))

        // Top-right inner corner.
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - tcr, y: rect.minY)
        )

        // Top edge back to start.
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))

        return path
    }
}

#Preview {
    NotchShape(topCornerRadius: 6, bottomCornerRadius: 14)
        .frame(width: 200, height: 32)
        .padding(10)
}
