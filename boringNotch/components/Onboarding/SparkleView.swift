//
//  SparkleView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 2024. 09. 26..
//

import SwiftUI
import AppKit

class SparkleNSView: NSView {
    private var emitterLayer: CAEmitterLayer?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        setupEmitterLayer()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupEmitterLayer() {
        let emitterLayer = CAEmitterLayer()
        emitterLayer.emitterShape = .rectangle
        emitterLayer.emitterMode = .surface
        emitterLayer.renderMode = .oldestFirst
        
        let cell = CAEmitterCell()
        cell.contents = NSImage(named: "sparkle")?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        cell.birthRate = 50
        cell.lifetime = 5
        cell.velocity = 10
        cell.velocityRange = 5
        cell.emissionRange = .pi * 2
        cell.scale = 0.2
        cell.scaleRange = 0.1
        cell.alphaSpeed = -0.5
        cell.yAcceleration = 10 // Add a slight downward motion
        
        emitterLayer.emitterCells = [cell]
        
        self.layer?.addSublayer(emitterLayer)
        self.emitterLayer = emitterLayer
        
        updateEmitterForCurrentBounds()
    }
    
    private func updateEmitterForCurrentBounds() {
        guard let emitterLayer = self.emitterLayer else { return }
        
        emitterLayer.frame = self.bounds
        emitterLayer.emitterSize = self.bounds.size
        emitterLayer.emitterPosition = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        
        // Adjust birth rate based on view size
        let area = bounds.width * bounds.height
        let baseBirthRate: Float = 50
        let adjustedBirthRate = 20 // Assuming 200x200 as base size
        emitterLayer.emitterCells?.first?.birthRate = Float(adjustedBirthRate)
    }
    
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateEmitterForCurrentBounds()
    }
}

struct SparkleView: NSViewRepresentable {
    func makeNSView(context: Context) -> SparkleNSView {
        return SparkleNSView()
    }
    
    func updateNSView(_ nsView: SparkleNSView, context: Context) {}
}
