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

extension NSImage {
    func averageColor(completion: @escaping (NSColor?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            let width = cgImage.width
            let height = cgImage.height
            let totalPixels = width * height
            
            guard let context = CGContext(data: nil,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            
            guard let data = context.data else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
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
            
            let averageRed = CGFloat(totalRed) / CGFloat(totalPixels) / 255.0
            let averageGreen = CGFloat(totalGreen) / CGFloat(totalPixels) / 255.0
            let averageBlue = CGFloat(totalBlue) / CGFloat(totalPixels) / 255.0
            
            let minBrightness: CGFloat = 0.5
            let isNearBlack = averageRed < 0.03 && averageGreen < 0.03 && averageBlue < 0.03
            
            var finalColor: NSColor
            
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
        let perceivedBrightness = (0.299 * red + 0.587 * green + 0.114 * blue)
        
        let scale = factor / perceivedBrightness
        red = min(red * scale, 1.0)
        green = min(green * scale, 1.0)
        blue = min(blue * scale, 1.0)
        
        return Color(red: Double(red), green: Double(green), blue: Double(blue), opacity: Double(alpha))
    }
}
