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

    /// Tangent-handle length as a fraction of the corner radius. The old corners used a
    /// single quadratic (parabolic) control at the corner vertex, whose curvature jumps
    /// at the tangents — the eye reads a faint hard "corner" and the clipped edge looks
    /// squared/jagged against bright content. Replacing each quad with a cubic whose
    /// control handles run *along* the straight edges (the circle constant ≈ 0.5523)
    /// yields a clean, even-curvature arc that flows out of the straights — the smooth,
    /// continuous look macOS uses for its own notch and rounded rects.
    private static let controlRatio: CGFloat = 0.5523

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let k = Self.controlRatio
        let topR = topCornerRadius
        let botR = bottomCornerRadius

        // top edge → left vertical (top-left corner)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.minX + topR, y: rect.minY + topR),
            control1: CGPoint(x: rect.minX + k * topR, y: rect.minY),
            control2: CGPoint(x: rect.minX + topR, y: rect.minY + topR - k * topR)
        )

        // left vertical
        path.addLine(to: CGPoint(x: rect.minX + topR, y: rect.maxY - botR))

        // left vertical → bottom edge (bottom-left chin)
        path.addCurve(
            to: CGPoint(x: rect.minX + topR + botR, y: rect.maxY),
            control1: CGPoint(x: rect.minX + topR, y: rect.maxY - botR + k * botR),
            control2: CGPoint(x: rect.minX + topR + botR - k * botR, y: rect.maxY)
        )

        // bottom edge
        path.addLine(to: CGPoint(x: rect.maxX - topR - botR, y: rect.maxY))

        // bottom edge → right vertical (bottom-right chin)
        path.addCurve(
            to: CGPoint(x: rect.maxX - topR, y: rect.maxY - botR),
            control1: CGPoint(x: rect.maxX - topR - botR + k * botR, y: rect.maxY),
            control2: CGPoint(x: rect.maxX - topR, y: rect.maxY - botR + k * botR)
        )

        // right vertical
        path.addLine(to: CGPoint(x: rect.maxX - topR, y: rect.minY + topR))

        // right vertical → top edge (top-right corner)
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control1: CGPoint(x: rect.maxX - topR, y: rect.minY + topR - k * topR),
            control2: CGPoint(x: rect.maxX - k * topR, y: rect.minY)
        )

        // top edge back to start
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))

        return path
    }
}

#Preview {
    NotchShape(topCornerRadius: 6, bottomCornerRadius: 14)
        .frame(width: 200, height: 32)
        .padding(10)
}
