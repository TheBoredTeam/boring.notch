//
//  NotchShape.swift
//  boringNotch
//
// Created by Kai Azim on 2023-08-24.
// Original source: https://github.com/MrKai77/DynamicNotchKit
// Modified by Alexander Greco on 2025-05-18.

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

        path.move(
            to: CGPoint(
                x: rect.minX,
                y: rect.minY
            )
        )

        path.addQuadCurve(
            to: CGPoint(
                x: rect.minX + topCornerRadius,
                y: rect.minY + topCornerRadius
            ),
            control: CGPoint(
                x: rect.minX + topCornerRadius,
                y: rect.minY
            )
        )

        path.addLine(
            to: CGPoint(
                x: rect.minX + topCornerRadius,
                y: rect.maxY - bottomCornerRadius
            )
        )

        path.addQuadCurve(
            to: CGPoint(
                x: rect.minX + topCornerRadius + bottomCornerRadius,
                y: rect.maxY
            ),
            control: CGPoint(
                x: rect.minX + topCornerRadius,
                y: rect.maxY
            )
        )

        path.addLine(
            to: CGPoint(
                x: rect.maxX - topCornerRadius - bottomCornerRadius,
                y: rect.maxY
            )
        )

        path.addQuadCurve(
            to: CGPoint(
                x: rect.maxX - topCornerRadius,
                y: rect.maxY - bottomCornerRadius
            ),
            control: CGPoint(
                x: rect.maxX - topCornerRadius,
                y: rect.maxY
            )
        )

        path.addLine(
            to: CGPoint(
                x: rect.maxX - topCornerRadius,
                y: rect.minY + topCornerRadius
            )
        )

        path.addQuadCurve(
            to: CGPoint(
                x: rect.maxX,
                y: rect.minY
            ),
            control: CGPoint(
                x: rect.maxX - topCornerRadius,
                y: rect.minY
            )
        )

        path.addLine(
            to: CGPoint(
                x: rect.minX,
                y: rect.minY
            )
        )

        return path
    }
}

#Preview {
    NotchShape(topCornerRadius: 6, bottomCornerRadius: 14)
        .frame(width: 200, height: 32)
        .padding(10)
}
