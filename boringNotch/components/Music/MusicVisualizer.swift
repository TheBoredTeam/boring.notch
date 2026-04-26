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

class AudioSpectrum: NSView {
    private var barLayers: [CAGradientLayer] = []
    private var isPlaying = false
    private var useRealtime = false
    private var tintColor: NSColor = .systemBlue

    private let barWidth: CGFloat = 2
    private let barCount = AudioCaptureManager.barCount
    private let spacing: CGFloat = 1
    private let totalHeight: CGFloat = 14

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupBars()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupBars()
    }

    private func setupBars() {
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
        if frame.width < totalWidth {
            frame.size = CGSize(width: totalWidth, height: totalHeight)
        }
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        for i in 0..<barCount {
            let xPosition = CGFloat(i) * (barWidth + spacing)
            let barLayer = CAGradientLayer()
            barLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            barLayer.bounds = CGRect(x: 0, y: 0, width: barWidth, height: barWidth)
            barLayer.position = CGPoint(x: xPosition + barWidth / 2, y: totalHeight / 2)
            barLayer.cornerRadius = barWidth / 2
            barLayer.contentsScale = scale
            barLayer.shouldRasterize = false
            barLayer.startPoint = CGPoint(x: 0.5, y: 0)
            barLayer.endPoint = CGPoint(x: 0.5, y: 1)
            barLayer.colors = [tintColor.withAlphaComponent(0.6).cgColor, tintColor.cgColor]
            layer?.addSublayer(barLayer)
            barLayers.append(barLayer)
        }
    }

    private func expandBars(animated: Bool) {
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.3)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        for (index, barLayer) in barLayers.enumerated() {
            let x = CGFloat(index) * (barWidth + spacing)
            barLayer.bounds = CGRect(x: 0, y: 0, width: barWidth, height: totalHeight)
            barLayer.position = CGPoint(x: x + barWidth / 2, y: totalHeight / 2)
            barLayer.transform = CATransform3DMakeScale(1.0, 0.3, 1.0)
        }
        CATransaction.commit()
    }

    private func collapseBarsToDots() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.3)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        for (index, barLayer) in barLayers.enumerated() {
            barLayer.removeAnimation(forKey: "scaleAnimation")
            barLayer.transform = CATransform3DIdentity
            let x = CGFloat(index) * (barWidth + spacing)
            barLayer.bounds = CGRect(x: 0, y: 0, width: barWidth, height: barWidth)
            barLayer.position = CGPoint(x: x + barWidth / 2, y: totalHeight / 2)
        }
        CATransaction.commit()
    }

    private func startRandomAnimating() {
        for (index, barLayer) in barLayers.enumerated() {
            animateBar(barLayer, delay: Double(index) * 0.08)
        }
    }

    private func animateBar(_ barLayer: CAGradientLayer, delay: Double = 0) {
        guard isPlaying else { return }
        let animation = CAKeyframeAnimation(keyPath: "transform.scale.y")
        var values: [CGFloat] = []
        var keyTimes: [NSNumber] = []
        let numSteps = 50
        let startValue = CGFloat.random(in: 0.3...1.0)
        for i in 0...numSteps {
            if i == 0 || i == numSteps {
                values.append(startValue)
            } else {
                values.append(CGFloat.random(in: 0.3...1.0))
            }
            keyTimes.append(NSNumber(value: Double(i) / Double(numSteps)))
        }
        animation.values = values
        animation.keyTimes = keyTimes
        animation.duration = 15
        animation.repeatCount = .infinity
        animation.calculationMode = .cubic
        animation.beginTime = CACurrentMediaTime() + delay
        if #available(macOS 12.0, *) {
            animation.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 30, preferred: 15)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        barLayer.transform = CATransform3DMakeScale(1.0, startValue, 1.0)
        CATransaction.commit()
        barLayer.add(animation, forKey: "scaleAnimation")
    }

    private func stopRandomAnimating() {
        for barLayer in barLayers {
            barLayer.removeAnimation(forKey: "scaleAnimation")
        }
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
        guard isPlaying else { return }
        if enabled {
            stopRandomAnimating()
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for barLayer in barLayers {
                barLayer.transform = CATransform3DMakeScale(1.0, 0.3, 1.0)
            }
            CATransaction.commit()
            startRandomAnimating()
        }
    }

    func setLevels(_ values: [CGFloat]) {
        guard isPlaying, useRealtime, values.count == barCount else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.033)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
        for (i, barLayer) in barLayers.enumerated() {
            let clamped = max(0.12, min(1.0, values[i]))
            barLayer.transform = CATransform3DMakeScale(1.0, clamped, 1.0)
        }
        CATransaction.commit()
    }

    func setTintColor(_ color: NSColor) {
        tintColor = color
        let colors = [color.withAlphaComponent(0.6).cgColor, color.cgColor]
        barLayers.forEach { $0.colors = colors }
    }
}

struct AudioSpectrumView: NSViewRepresentable {
    let isPlaying: Bool
    let tintColor: Color
    @Default(.realtimeAudioWaveform) var realtimeEnabled: Bool
    @ObservedObject var audioCapture = AudioCaptureManager.shared

    func makeNSView(context: Context) -> AudioSpectrum {
        let spectrum = AudioSpectrum()
        spectrum.setTintColor(NSColor(tintColor))
        spectrum.setUseRealtime(realtimeEnabled && audioCapture.isCapturing)
        spectrum.setPlaying(isPlaying)
        if realtimeEnabled && audioCapture.isCapturing {
            spectrum.setLevels(audioCapture.levels)
        }
        return spectrum
    }

    func updateNSView(_ nsView: AudioSpectrum, context: Context) {
        nsView.setTintColor(NSColor(tintColor))
        nsView.setUseRealtime(realtimeEnabled && audioCapture.isCapturing)
        nsView.setPlaying(isPlaying)
        if realtimeEnabled && audioCapture.isCapturing {
            nsView.setLevels(audioCapture.levels)
        }
    }
}

#Preview {
    ZStack {
        Color.black
        AudioSpectrumView(isPlaying: true, tintColor: .green)
            .frame(width: 18, height: 14)
    }
    .padding()
}
