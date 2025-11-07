//
//  LoftMarqueeText.swift
//  Zenith Loft (LoftOS)
//
//  Clean marquee text for macOS notch HUDs.
//  - Works with a binding or a constant string
//  - Adjustable speed & gap
//  - Pause on hover
//  - Optional edge fades
//  - Respects Reduce Motion
//

import SwiftUI
import AppKit

// MARK: - Internals (namespaced to avoid collisions)

private struct LoftSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

private struct LoftMeasureSizeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            GeometryReader { geo in
                Color.clear.preference(key: LoftSizePreferenceKey.self, value: geo.size)
            }
        )
    }
}

public enum LoftMarqueeDirection {
    case leftToRight, rightToLeft, automatic
}

// MARK: - New primary marquee

public struct LoftMarqueeText: View {
    // Content
    @Binding var text: String

    // Styling
    public var font: Font = .body
    public var nsFont: NSFont.TextStyle = .body
    public var textColor: Color = .primary
    public var backgroundColor: Color = .clear

    // Layout & behavior
    public var frameWidth: CGFloat = 200
    public var gap: CGFloat = 20
    public var speed: CGFloat = 30        // points per second
    public var minDelay: Double = 0.3     // delay before first scroll
    public var direction: LoftMarqueeDirection = .automatic
    public var pauseOnHover: Bool = true
    public var fadeEdges: Bool = false
    public var fadeWidth: CGFloat = 20

    // State
    @State private var contentSize: CGSize = .zero   // size of a single label
    @State private var offset: CGFloat = 0
    @State private var running: Bool = false
    @State private var hovering: Bool = false

    public init(_ text: Binding<String>,
                font: Font = .body,
                nsFont: NSFont.TextStyle = .body,
                textColor: Color = .primary,
                backgroundColor: Color = .clear,
                frameWidth: CGFloat = 200,
                gap: CGFloat = 20,
                speed: CGFloat = 30,
                minDelay: Double = 0.3,
                direction: LoftMarqueeDirection = .automatic,
                pauseOnHover: Bool = true,
                fadeEdges: Bool = false,
                fadeWidth: CGFloat = 20) {
        self._text = text
        self.font = font
        self.nsFont = nsFont
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.frameWidth = frameWidth
        self.gap = gap
        self.speed = speed
        self.minDelay = minDelay
        self.direction = direction
        self.pauseOnHover = pauseOnHover
        self.fadeEdges = fadeEdges
        self.fadeWidth = fadeWidth
    }

    private var needsScroll: Bool { contentSize.width > frameWidth }

    private var resolvedDirection: LoftMarqueeDirection {
        switch direction {
        case .automatic: return .rightToLeft  // typical ticker behavior
        default: return direction
        }
    }

    private var duration: Double {
        // distance to travel: width + gap
        let distance = contentSize.width + gap
        return max(0.01, Double(distance / max(1, speed)))
    }

    public var body: some View {
        ZStack {
            // content (duplicated for seamless loop)
            HStack(spacing: gap) {
                label
                label.opacity(needsScroll ? 1 : 0)
            }
            .id(text) // reset animation when text changes
            .offset(x: running ? animatedOffset : 0)
            .modifier(LoftMeasureSizeModifier())
            .onPreferenceChange(LoftSizePreferenceKey.self) { size in
                // a single label is half the measured HStack (because of the duplicate)
                contentSize = CGSize(width: size.width / 2, height: size.height)
                restartIfNeeded()
            }
            .animation(animation, value: running)

            if fadeEdges {
                edgeFades
                    .allowsHitTesting(false)
            }
        }
        .frame(width: frameWidth, alignment: .leading)
        .frame(height: contentHeight)
        .background(backgroundColor)
        .clipped()
        .onHover { if pauseOnHover { hovering = $0; updateRunState() } }
        .accessibilityLabel(Text(text))
        .onChange(of: text) { _, _ in restartIfNeeded() }
        .onAppear { restartIfNeeded() }
        .onDisappear { running = false }
        .accessibilityReduceMotion { value in
            if value { running = false }
            else { restartIfNeeded() }
        }
    }

    private var label: some View {
        Text(text)
            .font(font)
            .foregroundColor(textColor)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var contentHeight: CGFloat {
        max(14, NSFont.preferredFont(forTextStyle: nsFont).pointSize * 1.3)
    }

    private var animatedOffset: CGFloat {
        // Animate from 0 to target based on direction
        let travel = contentSize.width + gap
        switch resolvedDirection {
        case .rightToLeft: return -travel
        case .leftToRight: return travel
        case .automatic:   return -travel
        }
    }

    private var animation: Animation {
        guard needsScroll, !hovering else { return .default.speed(0) }
        return .linear(duration: duration).delay(minDelay).repeatForever(autoreverses: false)
    }

    private func restartIfNeeded() {
        withAnimation(.none) {
            running = false
            offset = 0
        }
        updateRunState()
    }

    private func updateRunState() {
        guard needsScroll, !hovering else { running = false; return }
        running = true
    }

    // Gradient edge fades
    private var edgeFades: some View {
        HStack {
            LinearGradient(colors: [.black.opacity(0.001), .black.opacity(0.6), .black],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: fadeWidth)
            Spacer()
            LinearGradient(colors: [.black, .black.opacity(0.6), .black.opacity(0.001)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: fadeWidth)
        }
        .blendMode(.destinationOut)
        .compositingGroup()
    }
}

// MARK: - Backwards compatibility wrapper
/// Matches your previous API so you don’t have to change call sites.
public struct MarqueeText: View {
    @Binding var text: String
    let font: Font
    let nsFont: NSFont.TextStyle
    let textColor: Color
    let backgroundColor: Color
    let minDuration: Double
    let frameWidth: CGFloat

    public init(_ text: Binding<String>,
                font: Font = .body,
                nsFont: NSFont.TextStyle = .body,
                textColor: Color = .primary,
                backgroundColor: Color = .clear,
                minDuration: Double = 3.0,
                frameWidth: CGFloat = 200) {
        _text = text
        self.font = font
        self.nsFont = nsFont
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.minDuration = minDuration
        self.frameWidth = frameWidth
    }

    public var body: some View {
        LoftMarqueeText(
            $text,
            font: font,
            nsFont: nsFont,
            textColor: textColor,
            backgroundColor: backgroundColor,
            frameWidth: frameWidth,
            gap: 20,
            speed: 30,
            minDelay: minDuration,
            direction: .automatic,
            pauseOnHover: true,
            fadeEdges: false
        )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        var long = "This is a very long marquee text that needs to scroll across the notch surface • Zenith Loft • LoftOS"
        MarqueeText(.constant(long),
                    font: .callout,
                    nsFont: .callout,
                    textColor: .white,
                    backgroundColor: .clear,
                    minDuration: 0.6,
                    frameWidth: 220)
            .frame(height: 24)
            .background(Color.black.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 8))

        LoftMarqueeText(.constant(long),
                        font: .body,
                        nsFont: .body,
                        textColor: .white,
                        backgroundColor: .clear,
                        frameWidth: 260,
                        gap: 24,
                        speed: 40,
                        minDelay: 0.2,
                        direction: .rightToLeft,
                        pauseOnHover: true,
                        fadeEdges: true,
                        fadeWidth: 18)
            .frame(height: 26)
            .background(Color.black.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    .padding()
    .background(Color.black)
}
