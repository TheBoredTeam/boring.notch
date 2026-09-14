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
        let width = cgImage.width
        let height = cgImage.height
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
