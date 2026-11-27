//
//  Image2Color.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import SwiftUI
import AppKit
import Cocoa
import Foundation
import CoreImage
import CoreGraphics
import CoreImage.CIFilterBuiltins

private struct AverageColorComponents: Sendable {
    let red: Double
    let green: Double
    let blue: Double
}

extension NSImage {
    @MainActor
    func averageColor() async -> NSColor? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let components = await Task.detached(priority: .userInitiated) {
            Self.averageColorComponents(for: cgImage)
        }.value

        guard let components else {
            return nil
        }

        return NSColor(
            red: components.red,
            green: components.green,
            blue: components.blue,
            alpha: 1.0
        )
    }

    nonisolated private static func averageColorComponents(for cgImage: CGImage) -> AverageColorComponents? {
        let maxDimension = 64
        let sourceWidth = max(1, cgImage.width)
        let sourceHeight = max(1, cgImage.height)
        let scale = min(1.0, Double(maxDimension) / Double(max(sourceWidth, sourceHeight)))
        let width = max(1, Int((Double(sourceWidth) * scale).rounded()))
        let height = max(1, Int((Double(sourceHeight) * scale).rounded()))
        let totalPixels = width * height

        guard totalPixels > 0,
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else {
            return nil
        }

        let pointer = data.bindMemory(to: UInt32.self, capacity: totalPixels)
        var totalRed: UInt64 = 0
        var totalGreen: UInt64 = 0
        var totalBlue: UInt64 = 0

        for i in 0..<totalPixels {
            let color = pointer[i]
            totalRed += UInt64(color & 0xFF)
            totalGreen += UInt64((color >> 8) & 0xFF)
            totalBlue += UInt64((color >> 16) & 0xFF)
        }

        let averageRed = Double(totalRed) / Double(totalPixels) / 255.0
        let averageGreen = Double(totalGreen) / Double(totalPixels) / 255.0
        let averageBlue = Double(totalBlue) / Double(totalPixels) / 255.0
        let minBrightness = 0.5

        guard !(averageRed < 0.03 && averageGreen < 0.03 && averageBlue < 0.03) else {
            return AverageColorComponents(red: minBrightness, green: minBrightness, blue: minBrightness)
        }

        let maximum = max(averageRed, averageGreen, averageBlue)
        let minimum = min(averageRed, averageGreen, averageBlue)

        guard maximum < minBrightness else {
            return AverageColorComponents(red: averageRed, green: averageGreen, blue: averageBlue)
        }

        let saturation = maximum == 0 ? 0 : (maximum - minimum) / maximum
        let saturationScale = maximum / minBrightness
        let chroma = minBrightness * saturation * saturationScale
        let rawHue: Double

        if maximum == minimum {
            rawHue = 0
        } else if maximum == averageRed {
            rawHue = ((averageGreen - averageBlue) / (maximum - minimum)).truncatingRemainder(dividingBy: 6)
        } else if maximum == averageGreen {
            rawHue = ((averageBlue - averageRed) / (maximum - minimum)) + 2
        } else {
            rawHue = ((averageRed - averageGreen) / (maximum - minimum)) + 4
        }

        let hue = rawHue < 0 ? rawHue + 6 : rawHue
        let x = chroma * (1 - abs((hue.truncatingRemainder(dividingBy: 2)) - 1))
        let match = minBrightness - chroma
        let rgb: (Double, Double, Double)

        switch hue {
        case ..<1:
            rgb = (chroma, x, 0)
        case ..<2:
            rgb = (x, chroma, 0)
        case ..<3:
            rgb = (0, chroma, x)
        case ..<4:
            rgb = (0, x, chroma)
        case ..<5:
            rgb = (x, 0, chroma)
        default:
            rgb = (chroma, 0, x)
        }

        return AverageColorComponents(red: rgb.0 + match, green: rgb.1 + match, blue: rgb.2 + match)
    }

    /// The most prominent *colourful* hue in the image (saturated, reasonably bright pixels
    /// win), unlike `averageColor()` which blends everything toward grey. Returns nil for
    /// essentially monochrome artwork.
    /// `secondary` is the next most prominent colour at least ~45° of hue away from the
    /// primary, if the artwork has one.
    @MainActor
    func vibrantColors() async -> (primary: NSColor, secondary: NSColor?)? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let result = await Task.detached(priority: .userInitiated) {
            Self.dominantVibrantHSB(for: cgImage)
        }.value
        guard let result else { return nil }
        let make = { (hsb: (Double, Double, Double)) in
            NSColor(hue: hsb.0, saturation: hsb.1, brightness: hsb.2, alpha: 1)
        }
        return (make(result.primary), result.secondary.map(make))
    }

    nonisolated private static func dominantVibrantHSB(
        for cgImage: CGImage
    ) -> (primary: (Double, Double, Double), secondary: (Double, Double, Double)?)? {
        let side = 32
        let totalPixels = side * side
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = context.data else { return nil }
        let pointer = data.bindMemory(to: UInt32.self, capacity: totalPixels)

        let bucketCount = 24
        var weights = [Double](repeating: 0, count: bucketCount)
        var pixels: [(hue: Double, sat: Double, bri: Double, weight: Double, bucket: Int)] = []
        pixels.reserveCapacity(totalPixels)

        for i in 0..<totalPixels {
            let value = pointer[i]
            let r = Double(value & 0xFF) / 255
            let g = Double((value >> 8) & 0xFF) / 255
            let b = Double((value >> 16) & 0xFF) / 255
            let maxC = max(r, g, b)
            let minC = min(r, g, b)
            let delta = maxC - minC
            let sat = maxC == 0 ? 0 : delta / maxC
            guard maxC > 0.18, sat > 0.22 else { continue }
            var hue: Double
            if maxC == r {
                hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxC == g {
                hue = (b - r) / delta + 2
            } else {
                hue = (r - g) / delta + 4
            }
            hue /= 6
            if hue < 0 { hue += 1 }
            // Favour pixels that are both saturated and bright.
            let weight = sat * sat * maxC
            let bucket = min(bucketCount - 1, Int(hue * Double(bucketCount)))
            weights[bucket] += weight
            pixels.append((hue, sat, maxC, weight, bucket))
        }

        // Too few colourful pixels: treat the artwork as monochrome.
        guard pixels.count > totalPixels / 25 else { return nil }

        func distance(_ a: Int, _ b: Int) -> Int { min(abs(a - b), bucketCount - abs(a - b)) }
        let scores = (0..<bucketCount).map { i in
            weights[i] + 0.5 * (weights[(i + bucketCount - 1) % bucketCount] + weights[(i + 1) % bucketCount])
        }
        guard let best = scores.indices.max(by: { scores[$0] < scores[$1] }) else { return nil }

        // Weighted circular mean over a bucket and its neighbours.
        func meanColor(around bucket: Int) -> (Double, Double, Double)? {
            var x = 0.0, y = 0.0, satSum = 0.0, briSum = 0.0, weightSum = 0.0
            for p in pixels where distance(p.bucket, bucket) <= 1 {
                x += cos(p.hue * 2 * .pi) * p.weight
                y += sin(p.hue * 2 * .pi) * p.weight
                satSum += p.sat * p.weight
                briSum += p.bri * p.weight
                weightSum += p.weight
            }
            guard weightSum > 0 else { return nil }
            var hue = atan2(y, x) / (2 * .pi)
            if hue < 0 { hue += 1 }
            return (hue, satSum / weightSum, briSum / weightSum)
        }
        guard let primary = meanColor(around: best) else { return nil }

        // Second colour: clearly different hue and at least a fifth as prominent.
        let secondBucket = scores.indices
            .filter { distance($0, best) >= 3 && scores[$0] >= scores[best] * 0.2 }
            .max(by: { scores[$0] < scores[$1] })
        return (primary, secondBucket.flatMap(meanColor(around:)))
    }

    func getBrightness() -> CGFloat {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return 0
        }

        let inputImage = CIImage(cgImage: cgImage)

        let filter = CIFilter.areaAverage()
        filter.inputImage = inputImage
        filter.extent = inputImage.extent

        guard let outputImage = filter.outputImage else {
            return 0
        }

        let context = CIContext(options: nil)

        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(outputImage,
                       toBitmap: &bitmap,
                       rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8,
                       colorSpace: CGColorSpaceCreateDeviceRGB())

        let brightness = (0.2126 * CGFloat(bitmap[0]) + 0.7152 * CGFloat(bitmap[1]) + 0.0722 * CGFloat(bitmap[2])) / 255.0

        return brightness
    }
}

extension Color {
    func ensureMinimumBrightness(factor: CGFloat) -> Color {
        guard factor >= 0 && factor <= 1 else {
            return self // Return original color if factor is out of bounds
        }

        let nsColor = NSColor(self)

        // Convert to RGB color space
        guard let rgbColor = nsColor.usingColorSpace(.sRGB) else {
            return self // Return original color if conversion fails
        }

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        rgbColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        // Calculate perceived brightness using the formula: (0.299*R + 0.587*G + 0.114*B)
        let perceivedBrightness = (0.2126 * red + 0.7152 * green + 0.0722 * blue)

        let scale = factor / perceivedBrightness
        red = min(red * scale, 1.0)
        green = min(green * scale, 1.0)
        blue = min(blue * scale, 1.0)

        return Color(red: Double(red), green: Double(green), blue: Double(blue), opacity: Double(alpha))
    }
}
