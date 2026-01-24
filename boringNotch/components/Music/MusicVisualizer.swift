//
//  MusicVisualizer.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 02/08/24.
//  Updated by Yuvraj Soni
import AppKit
import Cocoa
import SwiftUI

class AudioSpectrum: NSView {
    private var barShapeLayers: [CAShapeLayer] = []
    private var barGradientLayers: [CAGradientLayer] = []
    private var barScales: [CGFloat] = []
    private var isPlaying: Bool = true
    private var animationTimer: Timer?

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

    // MARK: - UI Setup
    private func setupBars() {
        layer?.sublayers?.removeAll()

        // ✅ 3 Lines like a music indicator
        let barCount = 3

        // Make bars thicker and spacing clean
        let barWidth: CGFloat = 3.5
        let spacing: CGFloat = 3.0

        // Height of the whole widget
        let totalHeight: CGFloat = 16

        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
        frame.size = CGSize(width: totalWidth, height: totalHeight)

        for i in 0 ..< barCount {
            let xPosition = CGFloat(i) * (barWidth + spacing)

            // ✅ Shape layer (this makes the rounded pill bar)
            let shape = CAShapeLayer()
            shape.frame = CGRect(x: xPosition, y: 0, width: barWidth, height: totalHeight)
            shape.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            shape.position = CGPoint(x: xPosition + barWidth / 2, y: totalHeight / 2)
            shape.masksToBounds = true

            let roundedPath = NSBezierPath(
                roundedRect: CGRect(x: 0, y: 0, width: barWidth, height: totalHeight),
                xRadius: barWidth / 2,
                yRadius: barWidth / 2
            )
            shape.path = roundedPath.cgPath

            // ✅ Gradient layer (this is the shiny color inside)
            let gradient = CAGradientLayer()
            gradient.frame = shape.bounds

            // Vertical gradient for shine
            gradient.startPoint = CGPoint(x: 0.5, y: 0.0)
            gradient.endPoint = CGPoint(x: 0.5, y: 1.0)

            // ✅ More premium colors
            let dim = NSColor.white.withAlphaComponent(0.25).cgColor
            let mid = NSColor.white.withAlphaComponent(0.55).cgColor
            let shine = NSColor.white.withAlphaComponent(1.0).cgColor

            // ✅ Longer shine band
            gradient.colors = [
                dim,
                mid,
                shine,
                mid,
                dim
            ]

            // Longer spread = more long reflection feel
            gradient.locations = [
                0.0,
                0.40,
                0.55,
                0.70,
                1.0
            ]

            // ✅ Mask gradient inside the rounded bar
            gradient.mask = shape

            // Store and add
            barShapeLayers.append(shape)
            barGradientLayers.append(gradient)
            barScales.append(0.30)

            layer?.addSublayer(gradient)

            // ✅ Shine animation (slow and long)
            addLongShineAnimation(to: gradient, delay: Double(i) * 0.18)
        }

        resetBars()
    }

    // MARK: - Shine Animation (Long + Smooth)
    private func addLongShineAnimation(to gradient: CAGradientLayer, delay: Double = 0) {

        // ✅ Moving shine effect by shifting gradient locations
        let shineAnim = CABasicAnimation(keyPath: "locations")

        // Wider movement distance = longer shine travel
        shineAnim.fromValue = [-0.8, -0.35, 0.0, 0.25, 0.6]
        shineAnim.toValue   = [0.4, 0.75, 1.0, 1.25, 1.7]

        // Slower = smoother + premium
        shineAnim.duration = 2.3
        shineAnim.repeatCount = .infinity
        shineAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        shineAnim.beginTime = CACurrentMediaTime() + delay
        shineAnim.isRemovedOnCompletion = false

        gradient.add(shineAnim, forKey: "longShine")
    }

    // MARK: - Bar Animation
    private func startAnimating() {
        guard animationTimer == nil else { return }

        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.updateBars()
        }
    }

    private func stopAnimating() {
        animationTimer?.invalidate()
        animationTimer = nil
        resetBars()
    }

    private func updateBars() {
        for (i, barLayer) in barShapeLayers.enumerated() {

            let currentScale = barScales[i]

            // ✅ Better natural movement values for 3 bars
            let targetScale: CGFloat
            if i == 0 {
                targetScale = CGFloat.random(in: 0.35...0.95)
            } else if i == 1 {
                targetScale = CGFloat.random(in: 0.45...1.0)
            } else {
                targetScale = CGFloat.random(in: 0.30...0.85)
            }

            barScales[i] = targetScale

            let animation = CABasicAnimation(keyPath: "transform.scale.y")
            animation.fromValue = currentScale
            animation.toValue = targetScale
            animation.duration = 0.22

            // Smooth bounce vibe
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animation.autoreverses = true

            // Keep it visually stable
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false

            if #available(macOS 13.0, *) {
                animation.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            }

            barLayer.add(animation, forKey: "scaleY")
        }
    }

    private func resetBars() {
        for (i, barLayer) in barShapeLayers.enumerated() {
            barLayer.removeAllAnimations()
            barLayer.transform = CATransform3DMakeScale(1, 0.30, 1)
            barScales[i] = 0.30

            // ✅ Keep shine running even when paused (optional)
            // If you want shine to stop on pause, uncomment next line:
            // barGradientLayers[i].removeAnimation(forKey: "longShine")
        }
    }

    // MARK: - Control
    func setPlaying(_ playing: Bool) {
        isPlaying = playing
        if isPlaying {
            startAnimating()
        } else {
            stopAnimating()
        }
    }
}

struct AudioSpectrumWrapperView: NSViewRepresentable {
    @Binding var isPlaying: Bool

    func makeNSView(context: Context) -> AudioSpectrum {
        let spectrum = AudioSpectrum()
        spectrum.setPlaying(isPlaying)
        return spectrum
    }

    func updateNSView(_ nsView: AudioSpectrum, context: Context) {
        nsView.setPlaying(isPlaying)
    }
}

#Preview {
    AudioSpectrumWrapperView(isPlaying: .constant(true))
        .frame(width: 28, height: 18)
        .padding()
        .background(Color.black)
}
