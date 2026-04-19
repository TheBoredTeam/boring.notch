//
//  MarqueeTextView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 08/08/2024.
//

import SwiftUI

struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct MeasureSizeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(GeometryReader { geometry in
            Color.clear.preference(key: SizePreferenceKey.self, value: geometry.size)
        })
    }
}

struct MarqueeText: View {
    @Binding var text: String
    let font: Font
    let nsFont: NSFont.TextStyle
    let textColor: Color
    let backgroundColor: Color
    /// Initial pause before scrolling starts (does NOT repeat between loops)
    let minDuration: Double
    let frameWidth: CGFloat

    @State private var animate = false
    @State private var textSize: CGSize = .zero
    @State private var offset: CGFloat = 0

    init(_ text: Binding<String>, font: Font = .body, nsFont: NSFont.TextStyle = .body, textColor: Color = .primary, backgroundColor: Color = .clear, minDuration: Double = 3.0, frameWidth: CGFloat = 200) {
        _text = text
        self.font = font
        self.nsFont = nsFont
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.minDuration = minDuration
        self.frameWidth = frameWidth
    }

    private let spacing: CGFloat = 24

    private var needsScrolling: Bool {
        textSize.width > frameWidth
    }

    // Seamless loop: the gap between the two copies equals `spacing`,
    // so when the first copy exits the left edge, the second copy is already
    // right behind it on the right — no jump, no pause between loops.
    private var loopOffset: CGFloat {
        -(textSize.width + spacing)
    }

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .leading) {
                HStack(spacing: spacing) {
                    Text(text)
                    Text(text)
                        .opacity(needsScrolling ? 1 : 0)
                }
                .id(text)
                .font(font)
                .foregroundColor(textColor)
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: animate ? loopOffset : 0)
                // Continuous animation — NO .delay() here so there is no pause
                // between loop iterations.
                .animation(
                    animate
                        ? .linear(duration: Double(max(textSize.width, 1) / 40))
                              .repeatForever(autoreverses: false)
                        : .none,
                    value: animate
                )
                .background(backgroundColor)
                .modifier(MeasureSizeModifier())
                .onPreferenceChange(SizePreferenceKey.self) { size in
                    self.textSize = CGSize(
                        width: (size.width - spacing) / 2,
                        height: NSFont.preferredFont(forTextStyle: nsFont).pointSize
                    )
                    self.animate = false
                    self.offset = 0
                    // Apply the initial delay ONCE before the infinite loop starts.
                    DispatchQueue.main.asyncAfter(deadline: .now() + max(minDuration, 0.05)) {
                        if needsScrolling {
                            self.animate = true
                        }
                    }
                }
            }
            .frame(width: frameWidth, alignment: .leading)
            .clipped()
            // Fade edges: text fades to clear on both sides for a polished look.
            .mask(
                HStack(spacing: 0) {
                    LinearGradient(
                        gradient: Gradient(colors: [backgroundColor, textColor.opacity(1)]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: needsScrolling ? min(18, frameWidth * 0.12) : 0)

                    Rectangle()

                    LinearGradient(
                        gradient: Gradient(colors: [textColor.opacity(1), backgroundColor]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: needsScrolling ? min(18, frameWidth * 0.12) : 0)
                }
            )
        }
        .frame(height: textSize.height * 1.3)
    }
}
