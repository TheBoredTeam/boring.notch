import SwiftUI
import AppKit
import Cocoa
import Foundation
import CoreImage
import CoreGraphics
import CoreImage.CIFilterBuiltins

extension NSImage {
    func loftAverageColor(completion: @escaping (NSColor?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            let width = cgImage.width
            let height = cgImage.height
            let totalPixels = width * height
            
            guard let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let data = context.data else {
                DispatchQueue.main.async { completion(nil) }
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
            
            let finalColor: NSColor = {
                if isNearBlack {
                    return NSColor(white: minBrightness, alpha: 1.0)
                } else {
                    var color = NSColor(red: averageRed, green: averageGreen, blue: averageBlue, alpha: 1.0)
                    var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
                    color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
                    
                    if brightness < minBrightness {
                        let saturationScale = brightness / minBrightness
                        color = NSColor(
                            hue: hue,
                            saturation: saturation * saturationScale,
                            brightness: minBrightness,
                            alpha: alpha
                        )
                    }
                    return color
                }
            }()
            
            DispatchQueue.main.async { completion(finalColor) }
        }
    }
    
    func loftGetBrightness() -> CGFloat {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return 0
        }
        
        let inputImage = CIImage(cgImage: cgImage)
        let filter = CIFilter.areaAverage()
        filter.inputImage = inputImage
        filter.extent = inputImage.extent
        
        guard let outputImage = filter.outputImage else { return 0 }
        
        let context = CIContext(options: nil)
        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        
        let brightness = (0.2126 * CGFloat(bitmap[0]) +
                          0.7152 * CGFloat(bitmap[1]) +
                          0.0722 * CGFloat(bitmap[2])) / 255.0
        return brightness
    }
}

extension Color {
    func loftEnsureMinimumBrightness(factor: CGFloat) -> Color {
        guard factor >= 0 && factor <= 1 else { return self }
        
        let nsColor = NSColor(self)
        guard let rgbColor = nsColor.usingColorSpace(.sRGB) else { return self }
        
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgbColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        
        // Perceived brightness
        let perceived = (0.2126 * r + 0.7152 * g + 0.0722 * b)
        let scale = perceived == 0 ? 0 : (factor / perceived)
        
        let rr = min(r * scale, 1.0)
        let gg = min(g * scale, 1.0)
        let bb = min(b * scale, 1.0)
        
        return Color(red: Double(rr), green: Double(gg), blue: Double(bb), opacity: Double(a))
    }
}
