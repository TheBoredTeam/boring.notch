//
//  Image2Color.swift
//  Gojo
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

extension NSImage {

    
    func averageColor(completion: @escaping (NSColor?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
                guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                    return
                }

                let inputImage = CIImage(cgImage: cgImage)
                let filter = CIFilter.areaAverage()
                filter.inputImage = inputImage
                filter.extent = inputImage.extent

                guard let outputImage = filter.outputImage else {
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                    return
                }

                var bitmap = [UInt8](repeating: 0, count: 4)
                let context = CIContext(options: [.workingColorSpace: NSNull()])
                context.render(
                    outputImage,
                    toBitmap: &bitmap,
                    rowBytes: 4,
                    bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                    format: .RGBA8,
                    colorSpace: CGColorSpaceCreateDeviceRGB()
                )

                let averageRed = CGFloat(bitmap[0]) / 255.0
                let averageGreen = CGFloat(bitmap[1]) / 255.0
                let averageBlue = CGFloat(bitmap[2]) / 255.0

                let minBrightness: CGFloat = 0.5
                let isNearBlack = averageRed < 0.03 && averageGreen < 0.03 && averageBlue < 0.03

                let finalColor: NSColor

                if isNearBlack {
                    // If it's near black, just return a gray color with the minimum brightness
                    finalColor = NSColor(white: minBrightness, alpha: 1.0)
                } else {
                    var color = NSColor(red: averageRed, green: averageGreen, blue: averageBlue, alpha: 1.0)

                    var hue: CGFloat = 0
                    var saturation: CGFloat = 0
                    var brightness: CGFloat = 0
                    var alpha: CGFloat = 0

                    color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

                    if brightness < minBrightness {
                        // Increase brightness while maintaining hue and reducing saturation
                        let saturationScale = brightness / minBrightness
                        color = NSColor(hue: hue,
                                        saturation: saturation * saturationScale,
                                        brightness: minBrightness,
                                        alpha: alpha)
                    }

                    finalColor = color
                }

                DispatchQueue.main.async {
                    completion(finalColor)
                }
            }
        }
        
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
