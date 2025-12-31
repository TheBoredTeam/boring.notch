//
//  MusicVisualizer.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 02/08/24.
//
import AppKit
import Cocoa
import SwiftUI

class AudioSpectrum: NSView {
    private var barLayers: [CAGradientLayer] = []
    private var isPlaying = false
    private var tintColor: NSColor = .systemBlue
    
    private let barWidth: CGFloat = 2
    private let barCount = 4
    private let spacing: CGFloat = 2
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
        let totalWidth = CGFloat(barCount) * (barWidth + spacing)
        if frame.width < totalWidth {
            frame.size = CGSize(width: totalWidth, height: totalHeight)
        }
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        for i in 0..<barCount {
            let xPosition = CGFloat(i) * (barWidth + spacing)
            let barLayer = CAGradientLayer()
            barLayer.frame = CGRect(x: xPosition, y: 0, width: barWidth, height: totalHeight)
            barLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            barLayer.position = CGPoint(x: xPosition + barWidth / 2, y: totalHeight / 2)
            barLayer.cornerRadius = barWidth / 2
            barLayer.contentsScale = scale
            barLayer.shouldRasterize = false
            barLayer.startPoint = CGPoint(x: 0.5, y: 0)
            barLayer.endPoint = CGPoint(x: 0.5, y: 1)
            barLayer.colors = [tintColor.withAlphaComponent(0.6).cgColor, tintColor.cgColor]
            barLayer.transform = CATransform3DMakeScale(1.0, 0.3, 1.0)
            layer?.addSublayer(barLayer)
            barLayers.append(barLayer)
        }
    }

    private func startAnimating() {
        for (index, barLayer) in barLayers.enumerated() {
            animateBar(barLayer, delay: Double(index) * 0.1)
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
            if i == 0 {
                values.append(startValue)
            } else if i == numSteps {
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

    private func stopAnimating() {
        isPlaying = false
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.3)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        for barLayer in barLayers {
            barLayer.removeAnimation(forKey: "scaleAnimation")
            barLayer.transform = CATransform3DMakeScale(1.0, 0.35, 1.0)
        }
        CATransaction.commit()
    }

    func setPlaying(_ playing: Bool) {
        guard isPlaying != playing else { return }
        isPlaying = playing
        playing ? startAnimating() : stopAnimating()
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
    
    func makeNSView(context: Context) -> AudioSpectrum {
        let spectrum = AudioSpectrum()
        spectrum.setTintColor(NSColor(tintColor))
        spectrum.setPlaying(isPlaying)
        return spectrum
    }
    
    func updateNSView(_ nsView: AudioSpectrum, context: Context) {
        nsView.setTintColor(NSColor(tintColor))
        nsView.setPlaying(isPlaying)
    }
}

#Preview {
    ZStack {
        Color.black
        AudioSpectrumView(isPlaying: true, tintColor: .green)
            .frame(width: 20, height: 14)
    }
    .padding()
}
