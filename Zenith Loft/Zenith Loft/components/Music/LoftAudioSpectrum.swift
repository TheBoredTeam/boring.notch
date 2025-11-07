//
//  LoftAudioSpectrum.swift
//  Zenith Loft (LoftOS)
//
//  Clean-room music visualizer (bar spectrum) for macOS.
//  - NSView + CAShapeLayer for smooth, low-overhead animation
//  - Customizable: bars, size, color, speed, min/max scale
//  - Respects Reduce Motion
//  - Backwards-compat wrappers keep old names working
//

import AppKit
import SwiftUI

// MARK: - Core NSView

final class LoftAudioSpectrum: NSView {

    // Customization
    var barCount: Int
    var barWidth: CGFloat
    var spacing: CGFloat
    var barHeight: CGFloat
    var barColor: NSColor
    var animationInterval: TimeInterval
    var minScale: CGFloat
    var maxScale: CGFloat
    var preferredFPS: Float?

    // State
    private var barLayers: [CAShapeLayer] = []
    private var animationTimer: Timer?
    private var isPlaying: Bool = true
    private var reduceMotion: Bool = false

    // MARK: Init

    init(frame: NSRect = .zero,
         barCount: Int = 4,
         barWidth: CGFloat = 2,
         spacing: CGFloat = 2,
         barHeight: CGFloat = 14,
         barColor: NSColor = .white,
         animationInterval: TimeInterval = 0.28,
         minScale: CGFloat = 0.35,
         maxScale: CGFloat = 1.0,
         preferredFPS: Float? = 24) {

        self.barCount = max(1, barCount)
        self.barWidth = max(1, barWidth)
        self.spacing = max(0, spacing)
        self.barHeight = max(6, barHeight)
        self.barColor = barColor
        self.animationInterval = max(0.05, animationInterval)
        self.minScale = max(0.0, minScale)
        self.maxScale = max(minScale, maxScale)
        self.preferredFPS = preferredFPS

        super.init(frame: frame)
        self.wantsLayer = true
        self.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        setupBars()
        updateIntrinsicSize()
    }

    required init?(coder: NSCoder) {
        self.barCount = 4
        self.barWidth = 2
        self.spacing = 2
        self.barHeight = 14
        self.barColor = .white
        self.animationInterval = 0.28
        self.minScale = 0.35
        self.maxScale = 1.0
        self.preferredFPS = 24
        super.init(coder: coder)
        self.wantsLayer = true
        self.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        setupBars()
        updateIntrinsicSize()
    }

    // MARK: Setup

    private func updateIntrinsicSize() {
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
        self.frame.size = CGSize(width: totalWidth, height: barHeight)
    }

    private func setupBars() {
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        barLayers.removeAll()

        for i in 0..<barCount {
            let x = CGFloat(i) * (barWidth + spacing)
            let rect = CGRect(x: 0, y: 0, width: barWidth, height: barHeight)

            let path = NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2)
            let bar = CAShapeLayer()
            bar.frame = CGRect(x: x, y: 0, width: barWidth, height: barHeight)
            bar.position = CGPoint(x: x + barWidth / 2, y: barHeight / 2)
            bar.path = path.cgPath
            bar.fillColor = barColor.cgColor
            bar.transform = CATransform3DMakeScale(1, minScale, 1)

            layer?.addSublayer(bar)
            barLayers.append(bar)
        }
    }

    // MARK: Animation control

    func setPlaying(_ playing: Bool) {
        isPlaying = playing
        if isPlaying && !reduceMotion {
            startAnimating()
        } else {
            stopAnimating()
        }
    }

    private func startAnimating() {
        guard animationTimer == nil else { return }
        guard !reduceMotion else { return }
        animationTimer = Timer.scheduledTimer(withTimeInterval: animationInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(animationTimer!, forMode: .common)
    }

    private func stopAnimating() {
        animationTimer?.invalidate()
        animationTimer = nil
        resetBars()
    }

    private func tick() {
        guard isPlaying, !reduceMotion else { return }
        for bar in barLayers {
            let current = (bar.presentation()?.value(forKeyPath: "transform.scale.y") as? CGFloat) ?? minScale
            let target = CGFloat.random(in: minScale...maxScale)

            let anim = CABasicAnimation(keyPath: "transform.scale.y")
            anim.fromValue = current
            anim.toValue = target
            anim.duration = animationInterval
            anim.autoreverses = true
            anim.fillMode = .forwards
            anim.isRemovedOnCompletion = false
            if #available(macOS 13.0, *), let fps = preferredFPS {
                anim.preferredFrameRateRange = CAFrameRateRange(minimum: fps, maximum: fps, preferred: fps)
            }
            bar.add(anim, forKey: "loft.scaleY")
        }
    }

    private func resetBars() {
        for bar in barLayers {
            bar.removeAllAnimations()
            bar.transform = CATransform3DMakeScale(1, minScale, 1)
        }
    }

    // MARK: Live updates (if you decide to tweak properties after init)

    func updateAppearance(color: NSColor? = nil,
                          barCount: Int? = nil,
                          barWidth: CGFloat? = nil,
                          spacing: CGFloat? = nil,
                          barHeight: CGFloat? = nil) {
        var requiresRebuild = false

        if let c = color { self.barColor = c }
        if let bc = barCount, bc != self.barCount { self.barCount = max(1, bc); requiresRebuild = true }
        if let bw = barWidth, bw != self.barWidth { self.barWidth = max(1, bw); requiresRebuild = true }
        if let sp = spacing, sp != self.spacing { self.spacing = max(0, sp); requiresRebuild = true }
        if let bh = barHeight, bh != self.barHeight { self.barHeight = max(6, bh); requiresRebuild = true }

        if requiresRebuild {
            setupBars()
            updateIntrinsicSize()
        } else {
            barLayers.forEach { $0.fillColor = self.barColor.cgColor }
        }
    }
}

// MARK: - SwiftUI bridge

struct LoftAudioSpectrumView: NSViewRepresentable {
    @Binding var isPlaying: Bool

    // Expose a few common knobs for SwiftUI
    var barCount: Int = 4
    var barWidth: CGFloat = 2
    var spacing: CGFloat = 2
    var barHeight: CGFloat = 14
    var color: NSColor = .white
    var animationInterval: TimeInterval = 0.28
    var minScale: CGFloat = 0.35
    var maxScale: CGFloat = 1.0
    var preferredFPS: Float? = 24

    func makeNSView(context: Context) -> LoftAudioSpectrum {
        let v = LoftAudioSpectrum(barCount: barCount,
                                  barWidth: barWidth,
                                  spacing: spacing,
                                  barHeight: barHeight,
                                  barColor: color,
                                  animationInterval: animationInterval,
                                  minScale: minScale,
                                  maxScale: maxScale,
                                  preferredFPS: preferredFPS)
        v.setPlaying(isPlaying)
        return v
    }

    func updateNSView(_ nsView: LoftAudioSpectrum, context: Context) {
        nsView.setPlaying(isPlaying)
        nsView.updateAppearance(color: color,
                                barCount: barCount,
                                barWidth: barWidth,
                                spacing: spacing,
                                barHeight: barHeight)
    }
}

// MARK: - Backwards-compat wrappers (so you don't need to rename call sites yet)

@available(*, deprecated, message: "Use LoftAudioSpectrum instead.")
final class AudioSpectrum: LoftAudioSpectrum {}

@available(*, deprecated, message: "Use LoftAudioSpectrumView instead.")
struct AudioSpectrumView: NSViewRepresentable {
    @Binding var isPlaying: Bool
    func makeNSView(context: Context) -> AudioSpectrum {
        let v = AudioSpectrum()
        v.setPlaying(isPlaying)
        return v
    }
    func updateNSView(_ nsView: AudioSpectrum, context: Context) {
        nsView.setPlaying(isPlaying)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        // Loft version with knobs
        LoftAudioSpectrumView(isPlaying: .constant(true),
                              barCount: 5,
                              barWidth: 3,
                              spacing: 2,
                              barHeight: 16,
                              color: .white,
                              animationInterval: 0.24,
                              minScale: 0.35,
                              maxScale: 1.0,
                              preferredFPS: 24)
            .frame(width: 30, height: 18)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 4))

        // Legacy wrapper (kept for compatibility)
        AudioSpectrumView(isPlaying: .constant(true))
            .frame(width: 16, height: 20)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
    .padding()
    .background(Color.black)
}
