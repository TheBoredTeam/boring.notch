//
//  LoftNotchShape.swift
//  Zenith Loft (LoftOS)
//
//  Clean-room notch silhouette with independent top/bottom radii.
//  Animatable, suitable for masking a HUD "pill" near the camera cutout.
//

import SwiftUI

public struct LoftNotchShape: Shape {
    private var topCornerRadius: CGFloat
    private var bottomCornerRadius: CGFloat
    /// Optional horizontal inset to shave the left/right edges (useful in tight layouts).
    private var horizontalInset: CGFloat

    public init(
        topCornerRadius: CGFloat = 6,
        bottomCornerRadius: CGFloat = 14,
        horizontalInset: CGFloat = 0
    ) {
        self.topCornerRadius = max(0, topCornerRadius)
        self.bottomCornerRadius = max(0, bottomCornerRadius)
        self.horizontalInset = max(0, horizontalInset)
    }

    /// Uniform radius convenience.
    public init(
        uniformRadius: CGFloat,
        horizontalInset: CGFloat = 0
    ) {
        let r = max(0, uniformRadius)
        self.init(topCornerRadius: r, bottomCornerRadius: r, horizontalInset: horizontalInset)
    }

    /// Full pill convenience (corner radius becomes half the height at render time).
    public static func pill(inset: CGFloat = 0) -> LoftNotchShape {
        LoftNotchShape(topCornerRadius: .zero, bottomCornerRadius: .zero, horizontalInset: inset)
    }

    // MARK: Animatable
    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    // MARK: Path
    public func path(in rect: CGRect) -> Path {
        // Apply optional horizontal inset safely
        let insetRect = rect.insetBy(dx: min(horizontalInset, rect.width / 2), dy: 0)

        // Clamp radii to available geometry
        let topR = min(topCornerRadius, min(insetRect.width, insetRect.height) / 2)
        let bottomR = min(bottomCornerRadius, min(insetRect.width, insetRect.height) / 2)

        var path = Path()

        // Start at top-left edge
        path.move(to: CGPoint(x: insetRect.minX, y: insetRect.minY))

        // Top-left curve
        path.addQuadCurve(
            to: CGPoint(x: insetRect.minX + topR, y: insetRect.minY + topR),
            control: CGPoint(x: insetRect.minX + topR, y: insetRect.minY)
        )

        // Left edge down
        path.addLine(to: CGPoint(x: insetRect.minX + topR, y: insetRect.maxY - bottomR))

        // Bottom-left curve
        path.addQuadCurve(
            to: CGPoint(x: insetRect.minX + topR + bottomR, y: insetRect.maxY),
            control: CGPoint(x: insetRect.minX + topR, y: insetRect.maxY)
        )

        // Bottom edge
        path.addLine(to: CGPoint(x: insetRect.maxX - topR - bottomR, y: insetRect.maxY))

        // Bottom-right curve
        path.addQuadCurve(
            to: CGPoint(x: insetRect.maxX - topR, y: insetRect.maxY - bottomR),
            control: CGPoint(x: insetRect.maxX - topR, y: insetRect.maxY)
        )

        // Right edge up
        path.addLine(to: CGPoint(x: insetRect.maxX - topR, y: insetRect.minY + topR))

        // Top-right curve
        path.addQuadCurve(
            to: CGPoint(x: insetRect.maxX, y: insetRect.minY),
            control: CGPoint(x: insetRect.maxX - topR, y: insetRect.minY)
        )

        // Close along top
        path.addLine(to: CGPoint(x: insetRect.minX, y: insetRect.minY))

        return path
    }
}

// MARK: - Backwards-compat alias (so existing code using `NotchShape` keeps compiling)
public typealias NotchShape = LoftNotchShape

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        Text("LoftNotchShape (top: 6, bottom: 14)")
            .foregroundStyle(.white)
        LoftNotchShape(topCornerRadius: 6, bottomCornerRadius: 14)
            .fill(.black)
            .frame(width: 240, height: 32)

        Text("Uniform 12")
            .foregroundStyle(.white)
        LoftNotchShape(uniformRadius: 12)
            .stroke(.white.opacity(0.6), lineWidth: 1)
            .background(LoftNotchShape(uniformRadius: 12).fill(.black))
            .frame(width: 240, height: 32)

        Text("Pill (auto)")
            .foregroundStyle(.white)
        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(.gray.opacity(0.2))
            LoftNotchShape.pill()
                .fill(.black)
                .padding(.horizontal, 20)
        }
        .frame(width: 260, height: 40)
    }
    .padding()
    .background(Color(red: 0.1, green: 0.1, blue: 0.12))
}
