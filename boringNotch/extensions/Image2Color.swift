//
//  Image2Color.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import SwiftUI
import AppKit

extension NSImage {
    func averageColor() -> NSColor? {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
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
            return nil
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let data = context.data else {
            return nil
        }
        
        let pointer = data.bindMemory(to: UInt32.self, capacity: totalPixels)
        
        var totalRed = 0
        var totalGreen = 0
        var totalBlue = 0
        
        for i in 0..<totalPixels {
            let color = pointer[i]
            totalRed += Int(color & 0xFF)
            totalGreen += Int((color >> 8) & 0xFF)
            totalBlue += Int((color >> 16) & 0xFF)
        }
        
        let averageRed = CGFloat(totalRed) / CGFloat(totalPixels) / 255.0
        let averageGreen = CGFloat(totalGreen) / CGFloat(totalPixels) / 255.0
        let averageBlue = CGFloat(totalBlue) / CGFloat(totalPixels) / 255.0
        
        let minBrightness: CGFloat = 0.5
        let isNearBlack = averageRed < 0.03 && averageGreen < 0.03 && averageBlue < 0.03
        
        if isNearBlack {
            // If it's near black, just return a gray color with the minimum brightness
            return NSColor(white: minBrightness, alpha: 1.0)
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
            
            return color
        }
    }
}
