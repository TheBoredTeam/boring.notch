//
//  LiquidGlassBackdropView.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//
//  A CoreAnimation backdrop that samples the desktop behind the notch window and
//  refracts it along the notch's perimeter: `glassBackground` bends the sampled
//  image through a signed distance field of the notch shape, so the edge reads as
//  glass rather than as a blurred panel. All of it is private API, so the shapes
//  are built by name through the ObjC runtime instead of being linked.
//

import AppKit
import Foundation
import QuartzCore
import SwiftUI

private typealias SetDoubleFunc = @convention(c) (AnyObject, Selector, Double) -> Void
private typealias SetObjFunc = @convention(c) (AnyObject, Selector, AnyObject) -> Void

final class LiquidGlassBackdropView: NSView {
    var refraction: Double = -24.0
    var lensHeight: Double = 23.0
    var blur: Double = 0.0
    var aberration: Double = 4.0
    var topRadius: CGFloat = 19.0
    var bottomRadius: CGFloat = 24.0

    private var backdrop: CALayer?
    private var sdfLayer: CALayer?
    private var sdfElement: CALayer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        updateGeometry()
    }

    private func setup() {
        guard let root = layer else { return }
        root.sublayers?.forEach { $0.removeFromSuperlayer() }

        guard let backdropClass = NSClassFromString("CABackdropLayer") as? CALayer.Type,
              let sdfLayerClass = NSClassFromString("CASDFLayer") as? CALayer.Type,
              let sdfElementClass = NSClassFromString("CASDFElementLayer") as? CALayer.Type,
              let sdfEffectClass = NSClassFromString("CASDFOutputEffect") as? NSObject.Type else {
            return
        }

        let backdropInstance = backdropClass.init()
        backdropInstance.frame = bounds
        backdropInstance.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        backdropInstance.setValue(true, forKey: "tracksLuma")
        backdropInstance.setValue(true, forKey: "allowsFilteredLuma")
        backdropInstance.setValue(true, forKey: "windowServerAware")
        backdropInstance.allowsGroupOpacity = false

        // 1. CASDFOutputEffect converts the distance field into normals the
        //    refraction filter can bend along.
        let effect = sdfEffectClass.init()
        let selMin = NSSelectorFromString("setMinimum:")
        let selMax = NSSelectorFromString("setMaximum:")
        if let methodMin = class_getInstanceMethod(sdfEffectClass, selMin),
           let methodMax = class_getInstanceMethod(sdfEffectClass, selMax) {
            let impMin = unsafeBitCast(method_getImplementation(methodMin), to: SetDoubleFunc.self)
            let impMax = unsafeBitCast(method_getImplementation(methodMax), to: SetDoubleFunc.self)
            impMin(effect, selMin, -1000.0)
            impMax(effect, selMax, 1.0)
        }

        let sdfLayerInstance = sdfLayerClass.init()
        sdfLayerInstance.name = "@0"
        sdfLayerInstance.frame = bounds
        sdfLayerInstance.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

        let selEffect = NSSelectorFromString("setEffect:")
        if let methodEffect = class_getInstanceMethod(sdfLayerClass, selEffect) {
            let imp = unsafeBitCast(method_getImplementation(methodEffect), to: SetObjFunc.self)
            imp(sdfLayerInstance, selEffect, effect)
        }

        // C1 Hermite smoothness: without it the refraction shows hard steps.
        let selSmooth = NSSelectorFromString("setSmoothness:")
        if let methodSmooth = class_getInstanceMethod(sdfLayerClass, selSmooth) {
            let imp = unsafeBitCast(method_getImplementation(methodSmooth), to: SetDoubleFunc.self)
            imp(sdfLayerInstance, selSmooth, 38.0)
        }

        // 2. The shape element. It is inset by topRadius on both sides so its
        //    sidewalls line up with the notch's vertical walls. AppKit puts y=0
        //    at the bottom, so the corner radius rounds the bottom corners.
        let sdfElementInstance = sdfElementClass.init()
        let contentWidth = max(bounds.width - topRadius * 2, 0)
        sdfElementInstance.frame = CGRect(x: topRadius, y: 0, width: contentWidth, height: bounds.height)
        sdfElementInstance.cornerRadius = bottomRadius
        sdfElementInstance.setValue("bounds", forKey: "mode")
        sdfElementInstance.setValue("union", forKey: "operation")

        sdfLayerInstance.sublayers = [sdfElementInstance]
        backdropInstance.sublayers = [sdfLayerInstance]
        root.addSublayer(backdropInstance)

        self.backdrop = backdropInstance
        self.sdfLayer = sdfLayerInstance
        self.sdfElement = sdfElementInstance

        rebuild()
    }

    func updateGeometry() {
        guard let backdrop = backdrop,
              let sdfLayer = sdfLayer,
              let sdfElement = sdfElement else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.frame = bounds
        sdfLayer.frame = bounds
        let contentWidth = max(bounds.width - topRadius * 2, 0)
        sdfElement.frame = CGRect(x: topRadius, y: 0, width: contentWidth, height: bounds.height)
        sdfElement.cornerRadius = bottomRadius
        backdrop.setNeedsDisplay()
        sdfLayer.setNeedsDisplay()
        CATransaction.commit()
    }

    func rebuild() {
        guard let filterClass = NSClassFromString("CAFilter") as AnyObject as? NSObjectProtocol,
              let backdrop = backdrop else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        guard let filter = filterClass.perform(NSSelectorFromString("filterWithType:"), with: "glassBackground")?
            .takeUnretainedValue() as AnyObject? else {
            CATransaction.commit()
            return
        }

        filter.setValue("glassBackground", forKey: "name")
        filter.setValue("@0", forKey: "inputSourceSublayerName")

        // 1. Optical ray-bending, continuous across left, right and bottom.
        filter.setValue(refraction, forKey: "inputInnerRefractionAmount")
        filter.setValue(lensHeight, forKey: "inputInnerRefractionHeight")
        filter.setValue(-1.0, forKey: "inputRefractionDistance0")
        filter.setValue(0.0, forKey: "inputRefractionDistance1")
        filter.setValue(1.0, forKey: "inputRefractionOpacity")

        // 2. Blur stays at zero by default: the point of the pipeline is a clear
        //    surface, not another translucent panel.
        filter.setValue(blur, forKey: "inputBlurRadius")
        filter.setValue(blur * 1.5, forKey: "inputBlurFillBlurRadius")
        filter.setValue(0.85, forKey: "inputBlurOpacity0")
        filter.setValue(0.85, forKey: "inputBlurOpacity1")
        filter.setValue(1.0, forKey: "inputBlurOpacity2")
        filter.setValue(1.0, forKey: "inputBlurOpacity3")
        filter.setValue(blur > 0 ? 0.60 : 0.0, forKey: "inputBlurFillNormalOpacity")

        // 3. Sub-pixel chromatic dispersion along the refractive perimeter.
        filter.setValue(aberration, forKey: "inputAberrationAmount")
        filter.setValue(lensHeight, forKey: "inputAberrationHeight")
        filter.setValue(0.0, forKey: "inputAberrationOffset")
        filter.setValue(0.0, forKey: "inputAberrationAngle")

        // 4. Clarity: full face opacity, no bleed.
        filter.setValue(0.0, forKey: "inputBleedAmount")
        filter.setValue(1.0, forKey: "inputFaceOpacity")
        filter.setValue(75.0, forKey: "inputShadowAmount")
        filter.setValue(0.50, forKey: "inputKeyFillHighlightAmount")

        backdrop.filters = [filter]
        backdrop.setNeedsDisplay()

        CATransaction.commit()
    }
}

// MARK: - SwiftUI Representable

struct LiquidGlassBackdropRepresentable: NSViewRepresentable {
    var refraction: Double
    var lensHeight: Double
    var blur: Double
    var aberration: Double
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    func makeNSView(context: Context) -> LiquidGlassBackdropView {
        // Start at the open notch's frame so the first composite is already the
        // right size; layout() corrects it from there.
        let view = LiquidGlassBackdropView(frame: NSRect(x: 0, y: 0, width: 640, height: 195))
        apply(to: view)
        view.rebuild()
        return view
    }

    func updateNSView(_ nsView: LiquidGlassBackdropView, context: Context) {
        apply(to: nsView)
        nsView.updateGeometry()
        nsView.rebuild()
    }

    private func apply(to view: LiquidGlassBackdropView) {
        // Negative refraction bends the sampled image inward, which is what
        // reads as a convex glass edge.
        view.refraction = -refraction
        view.lensHeight = lensHeight
        view.blur = blur
        view.aberration = aberration
        view.topRadius = topRadius
        view.bottomRadius = bottomRadius
    }
}
