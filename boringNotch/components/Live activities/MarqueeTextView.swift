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
    let text: String
    let font: Font
    let nsFont: NSFont.TextStyle
    let color: Color
    let delayDuration: Double
    let frameWidth: CGFloat
    
    /// Used to repeat the text until it no longer fits the given *frameWidth*.
    /// When *true* will **always** scroll the text
    let infiniteText: Bool
    
    @State private var animate = false
    @State private var textSize: CGSize = .zero
    @State private var offset: CGFloat = 0
    
    init(_ text: String, font: Font = .body, nsFont: NSFont.TextStyle = .body, color: Color = .primary, delayDuration: Double = 3.0, frameWidth: CGFloat, infiniteText: Bool = false) {
        self.text = text
        self.font = font
        self.nsFont = nsFont
        self.color = color
        self.delayDuration = delayDuration
        self.frameWidth = frameWidth
        self.infiniteText = infiniteText
    }
    
    private var needsScrolling: Bool {
        textSize.width > frameWidth
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                HStack(spacing: 20) {
                    Text(text)
                    Text(text)
                        .opacity(needsScrolling ? 1 : 0)
                }
                .id(text)
                .font(font)
                .foregroundColor(color)
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: self.animate ? offset : 0)
                .animation(
                    self.animate ?
                        .linear(duration: Double(textSize.width / 30))
                        .delay(delayDuration)
                        .repeatForever(autoreverses: false) : .none,
                    value: self.animate
                )
                .modifier(MeasureSizeModifier())
                .onPreferenceChange(SizePreferenceKey.self) { size in
                    self.textSize = CGSize(width: size.width / 2, height: NSFont.preferredFont(forTextStyle: nsFont).pointSize)
                    /*
                    if infiniteText && !needsScrolling {
                        text = text + " " + _bindingText.wrappedValue
                        return
                    }
                     */
                    self.animate = false
                    self.offset = 0
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01){
                        if needsScrolling {
                            self.animate = true
                            self.offset = -(textSize.width + 10)
                            
                        }
                    }
                }
            }
            .frame(width: frameWidth, alignment: .leading)
            .clipped()
        }
        .frame(height: textSize.height * 1.3)
        
    }
}

struct TimedLyricText: View {
    let text: String
    let font: Font
    let nsFont: NSFont.TextStyle
    let color: Color
    let displayDuration: Double?
    let animationID: Double?
    let startDelay: Double
    let endLead: Double
    let frameWidth: CGFloat

    private enum TimingProfile {
        static let shortLineScrollDuration: Double = 0.35
        static let minStartDelay: Double = 0.35
        static let minScrollDuration: Double = 0.55
        static let pxPerSecond: CGFloat = 52
        static let maxBookendShare: Double = 0.42
        static let startDelayShare: Double = 0.28
    }

    @State private var textSize: CGSize = .zero
    @State private var offset: CGFloat = 0
    @State private var animationToken = UUID()

    init(
        _ text: String,
        font: Font = .body,
        nsFont: NSFont.TextStyle = .body,
        color: Color = .primary,
        displayDuration: Double? = nil,
        animationID: Double? = nil,
        startDelay: Double = 0.4,
        endLead: Double = 0.9,
        frameWidth: CGFloat
    ) {
        self.text = text
        self.font = font
        self.nsFont = nsFont
        self.color = color
        self.displayDuration = displayDuration
        self.animationID = animationID
        self.startDelay = startDelay
        self.endLead = endLead
        self.frameWidth = frameWidth
    }

    private var finalOffset: CGFloat {
        min(frameWidth - textSize.width, 0)
    }

    private var needsScrolling: Bool {
        finalOffset < 0
    }

    private var naturalScrollDuration: Double {
        max(Double(abs(finalOffset) / TimingProfile.pxPerSecond), TimingProfile.minScrollDuration)
    }

    private var animationTiming: (delay: Double, duration: Double) {
        guard let displayDuration, displayDuration > 0 else {
            return (startDelay, naturalScrollDuration)
        }

        let minimumScrollDuration = min(TimingProfile.shortLineScrollDuration, displayDuration)
        guard displayDuration > minimumScrollDuration else {
            return (0, minimumScrollDuration)
        }

        let bookendBudget = min(startDelay + endLead, displayDuration * TimingProfile.maxBookendShare)
        let delay = resolvedStartDelay(from: bookendBudget)
        let scrollDuration = max(displayDuration - bookendBudget, 0)

        return (delay, scrollDuration)
    }

    private func resolvedStartDelay(from bookendBudget: Double) -> Double {
        let dynamicDelay = bookendBudget * TimingProfile.startDelayShare
        let preferredDelay = max(TimingProfile.minStartDelay, dynamicDelay)

        return min(startDelay, preferredDelay, bookendBudget)
    }

    var body: some View {
        GeometryReader { _ in
            Text(text)
                .id(text)
                .font(font)
                .foregroundColor(color)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: offset)
                .modifier(MeasureSizeModifier())
                .onPreferenceChange(SizePreferenceKey.self) { size in
                    textSize = CGSize(width: size.width, height: NSFont.preferredFont(forTextStyle: nsFont).pointSize)
                    restartAnimationIfNeeded()
                }
                .onChange(of: text) { _ in restartAnimationIfNeeded() }
                .onChange(of: frameWidth) { _ in restartAnimationIfNeeded() }
                .onChange(of: animationID) { _ in restartAnimationIfNeeded() }
        }
        .frame(width: frameWidth, alignment: .leading)
        .clipped()
        .frame(height: textSize.height * 1.3)
    }

    private func restartAnimationIfNeeded() {
        animationToken = UUID()
        let token = animationToken

        var resetTransaction = Transaction()
        resetTransaction.animation = nil
        withTransaction(resetTransaction) {
            offset = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            guard animationToken == token, needsScrolling else { return }
            let timing = animationTiming
            withAnimation(.linear(duration: timing.duration).delay(timing.delay)) {
                offset = finalOffset
            }
        }
    }
}
