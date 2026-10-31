//
//  MusicVisualizer.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 02/08/24.
//
import AppKit
import Cocoa
import Defaults
import SwiftUI

class MusicVisualizerModel: NSView, AudioCaptureLevelsConsumer {
    private let gradientLayer = CAGradientLayer()
    private let barMaskLayer = CAShapeLayer()
    private var isPlaying = false
    private var useRealtime = false
    private var tintColor: NSColor = .systemBlue
    private var lastTintColor: NSColor?

    private weak var attachedManager: AudioCaptureManager?
    private var lastAppliedLevels: [Float]
    private static let levelChangeThreshold: Float = 0.005
    private static let minBarScale: CGFloat = 0.12
    private static let idleBarScale: CGFloat = 0.3
    private static let randomAnimationKey = "randomPathAnimation"
    private static let transitionAnimationKey = "pathTransitionAnimation"

    private let barWidth: CGFloat = 2
    private let barCount = AudioCaptureManager.barCount
    private let spacing: CGFloat = 1
    private let totalHeight: CGFloat = 14

    override init(frame frameRect: NSRect) {
        self.lastAppliedLevels = [Float](repeating: 0, count: AudioCaptureManager.barCount)
        super.init(frame: frameRect)
        wantsLayer = true
        setupBars()
    }

    required init?(coder: NSCoder) {
        self.lastAppliedLevels = [Float](repeating: 0, count: AudioCaptureManager.barCount)
        super.init(coder: coder)
        wantsLayer = true
        setupBars()
    }

    deinit {
        attachedManager?.clearLevelsConsumer(self)
    }

    private func setupBars() {
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
        if frame.width < totalWidth {
            frame.size = CGSize(width: totalWidth, height: totalHeight)
        }

        // One gradient plus one shape mask replaces six independently
        // transformed gradient layers. The visualizer still has six bars,
        // but WindowServer now composites a single tiny layer tree.
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        gradientLayer.frame = CGRect(x: 0, y: 0, width: totalWidth, height: totalHeight)
        gradientLayer.contentsScale = scale
        gradientLayer.shouldRasterize = false
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        gradientLayer.colors = [tintColor.withAlphaComponent(0.6).cgColor, tintColor.cgColor]

        barMaskLayer.frame = gradientLayer.bounds
        barMaskLayer.fillColor = NSColor.black.cgColor
        barMaskLayer.path = path(
            for: Array(repeating: Self.idleBarScale, count: barCount),
            dots: true
        )
        gradientLayer.mask = barMaskLayer
        layer?.addSublayer(gradientLayer)
    }

    private func expandBars(animated: Bool) {
        setPath(
            path(for: Array(repeating: Self.idleBarScale, count: barCount)),
            animated: animated
        )
    }

    private func collapseBarsToDots() {
        barMaskLayer.removeAnimation(forKey: Self.randomAnimationKey)
        setPath(
            path(for: Array(repeating: Self.idleBarScale, count: barCount), dots: true),
            animated: true
        )
    }

    private func startRandomAnimating() {
        guard isPlaying, !useRealtime else { return }

        // Cancel the expand/collapse tween before the repeating animation
        // starts; both otherwise animate the same mask property.
        barMaskLayer.removeAnimation(forKey: Self.transitionAnimationKey)
        let startPath = path(for: randomScales())
        var values: [Any] = [startPath]
        var keyTimes: [NSNumber] = [0]
        let numSteps = 50

        for step in 1..<numSteps {
            values.append(path(for: randomScales()))
            keyTimes.append(NSNumber(value: Double(step) / Double(numSteps)))
        }
        values.append(startPath)
        keyTimes.append(1)

        let animation = CAKeyframeAnimation(keyPath: "path")
        animation.values = values
        animation.keyTimes = keyTimes
        animation.duration = 15
        animation.repeatCount = .infinity
        animation.calculationMode = .cubic
        if #available(macOS 12.0, *) {
            animation.preferredFrameRateRange = CAFrameRateRange(
                minimum: 10,
                maximum: 30,
                preferred: 15
            )
        }

        barMaskLayer.removeAnimation(forKey: Self.randomAnimationKey)
        barMaskLayer.path = startPath
        barMaskLayer.add(animation, forKey: Self.randomAnimationKey)
    }

    private func randomScales() -> [CGFloat] {
        (0..<barCount).map { _ in CGFloat.random(in: Self.idleBarScale...1.0) }
    }

    private func stopRandomAnimating() {
        barMaskLayer.removeAnimation(forKey: Self.randomAnimationKey)
    }

    private func setPath(_ newPath: CGPath, animated: Bool) {
        barMaskLayer.removeAnimation(forKey: Self.transitionAnimationKey)
        guard animated else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            barMaskLayer.path = newPath
            CATransaction.commit()
            return
        }

        let oldPath = barMaskLayer.presentation()?.path ?? barMaskLayer.path ?? newPath
        let animation = CABasicAnimation(keyPath: "path")
        animation.fromValue = oldPath
        animation.toValue = newPath
        animation.duration = 0.3
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        barMaskLayer.path = newPath
        barMaskLayer.add(animation, forKey: Self.transitionAnimationKey)
    }

    func setPlaying(_ playing: Bool) {
        guard isPlaying != playing else { return }
        isPlaying = playing
        if playing {
            expandBars(animated: true)
            if !useRealtime {
                startRandomAnimating()
            }
        } else {
            collapseBarsToDots()
        }
    }

    func setUseRealtime(_ enabled: Bool) {
        guard useRealtime != enabled else { return }
        useRealtime = enabled
        // Force the next incoming frame through the threshold guard.
        for i in 0..<lastAppliedLevels.count { lastAppliedLevels[i] = -1 }
        guard isPlaying else { return }
        if enabled {
            stopRandomAnimating()
        } else {
            expandBars(animated: false)
            startRandomAnimating()
        }
    }

    func attach(to manager: AudioCaptureManager) {
        guard attachedManager !== manager else { return }
        attachedManager?.clearLevelsConsumer(self)
        attachedManager = manager
        manager.setLevelsConsumer(self)
    }

    func syncCurrentLevels(from manager: AudioCaptureManager) {
        guard attachedManager === manager,
              let values = manager.latestLevelsSnapshot() else { return }
        applyLevels(values)
    }

    func audioCaptureManager(_ manager: AudioCaptureManager, didProduceLevels values: [Float]) {
        applyLevels(values)
    }

    private func applyLevels(_ values: [Float]) {
        guard isPlaying, useRealtime, values.count == barCount else { return }
        var maxDelta: Float = 0
        for i in 0..<barCount {
            let delta = abs(values[i] - lastAppliedLevels[i])
            if delta > maxDelta { maxDelta = delta }
        }
        guard maxDelta >= Self.levelChangeThreshold else { return }

        for i in 0..<barCount {
            lastAppliedLevels[i] = values[i]
        }
        let scales = values.map { value in
            max(Self.minBarScale, min(CGFloat(1), CGFloat(value)))
        }
        setPath(path(for: scales), animated: false)
    }

    func setTintColor(_ color: NSColor) {
        if let last = lastTintColor, last.isEqual(color) { return }
        lastTintColor = color
        tintColor = color
        gradientLayer.colors = [
            color.withAlphaComponent(0.6).cgColor,
            color.cgColor
        ]
    }

    private func path(for scales: [CGFloat], dots: Bool = false) -> CGPath {
        let path = CGMutablePath()
        for (index, scale) in scales.enumerated() {
            let height = dots ? barWidth : totalHeight * scale
            let rect = CGRect(
                x: CGFloat(index) * (barWidth + spacing),
                y: (totalHeight - height) / 2,
                width: barWidth,
                height: height
            )
            let cornerRadius = min(barWidth / 2, height / 2)
            path.addRoundedRect(
                in: rect,
                cornerWidth: cornerRadius,
                cornerHeight: cornerRadius,
                transform: .identity
            )
        }
        return path
    }
}

struct MusicVisualizer: NSViewRepresentable {
    let isPlaying: Bool
    let tintColor: Color
    @Default(.realtimeAudioWaveform) var realtimeEnabled: Bool
    @ObservedObject private var audioCapture = AudioCaptureManager.shared

    func makeNSView(context: Context) -> MusicVisualizerModel {
        let spectrum = MusicVisualizerModel()
        spectrum.setTintColor(NSColor(tintColor))
        spectrum.setUseRealtime(realtimeEnabled && audioCapture.isCapturing)
        spectrum.setPlaying(isPlaying)
        spectrum.attach(to: audioCapture)
        spectrum.syncCurrentLevels(from: audioCapture)
        return spectrum
    }

    func updateNSView(_ nsView: MusicVisualizerModel, context: Context) {
        nsView.setTintColor(NSColor(tintColor))
        nsView.setUseRealtime(realtimeEnabled && audioCapture.isCapturing)
        nsView.setPlaying(isPlaying)
        nsView.syncCurrentLevels(from: audioCapture)
    }
}

#Preview {
    ZStack {
        Color.black
        MusicVisualizer(isPlaying: true, tintColor: .green)
            .frame(width: 18, height: 14)
    }
    .padding()
}
