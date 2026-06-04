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
    
    /// Extract up to `max` area-weighted dominant colors from the image, sorted by the
    /// area they cover. Modeled on `averageColor`'s pixel walk (premultipliedLast
    /// CGContext, background queue, completion hops to main), but instead of averaging
    /// the whole image into one color it buckets pixels into a coarse 4-bit/channel RGB
    /// histogram, then returns the most-populated buckets as representative colors.
    ///
    /// This is the root-cause fix for the muddy peek aurora: a multi-color logo
    /// (gmail's red/blue/green/yellow) averages to a single beige blob, but its
    /// dominant *buckets* preserve the real brand hues.
    ///
    /// - Background pixels are dropped before bucketing: transparent (alpha < 128),
    ///   near-white (brightness > 0.92 && saturation < 0.12), and near-black
    ///   (brightness < 0.08). Each surviving bucket's representative is the area-
    ///   weighted centroid of its *un-quantized* channels.
    /// - Buckets are deduped by hue (kept only if > 25° from every already-accepted
    ///   color, wrap-aware); near-grays (saturation < 0.15) dedupe by > 0.18 brightness
    ///   instead. An empty result (a monochrome mark) is valid and expected.
    func dominantColors(max maxColors: Int = 4, completion: @escaping ([NSColor]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            let width = cgImage.width
            let height = cgImage.height
            let totalPixels = width * height

            guard totalPixels > 0,
                  let context = CGContext(data: nil,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

            guard let data = context.data else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            let pointer = data.bindMemory(to: UInt32.self, capacity: totalPixels)

            // bucket key (12-bit RGB) → (count, summed un-quantized r/g/b)
            struct Bucket { var count: UInt64 = 0; var r: UInt64 = 0; var g: UInt64 = 0; var b: UInt64 = 0 }
            var buckets: [UInt16: Bucket] = [:]

            for i in 0..<totalPixels {
                let px = pointer[i]
                let r = UInt32(px & 0xFF)
                let g = UInt32((px >> 8) & 0xFF)
                let b = UInt32((px >> 16) & 0xFF)
                let a = UInt32((px >> 24) & 0xFF)

                if a < 128 { continue }

                let rf = CGFloat(r) / 255.0
                let gf = CGFloat(g) / 255.0
                let bf = CGFloat(b) / 255.0

                // Perceived brightness + a quick saturation estimate to drop near-white
                // and near-black backgrounds before they dominate the histogram.
                let maxC = Swift.max(rf, gf, bf)
                let minC = Swift.min(rf, gf, bf)
                let brightness = maxC
                let saturation = maxC <= 0 ? 0 : (maxC - minC) / maxC

                if brightness > 0.92 && saturation < 0.12 { continue } // near-white bg
                if brightness < 0.08 { continue }                       // near-black

                let key = UInt16(((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4))
                var bucket = buckets[key] ?? Bucket()
                bucket.count += 1
                bucket.r += UInt64(r)
                bucket.g += UInt64(g)
                bucket.b += UInt64(b)
                buckets[key] = bucket
            }

            // Most-populated first → representative = area-weighted centroid.
            let ranked = buckets.values
                .sorted { $0.count > $1.count }
                .map { bucket -> NSColor in
                    let c = CGFloat(bucket.count)
                    return NSColor(srgbRed: CGFloat(bucket.r) / 255.0 / c,
                                   green: CGFloat(bucket.g) / 255.0 / c,
                                   blue: CGFloat(bucket.b) / 255.0 / c,
                                   alpha: 1.0)
                }

            // Dedupe so we don't return four shades of the same hue.
            var accepted: [NSColor] = []
            for color in ranked {
                guard accepted.count < maxColors else { break }
                var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0, al: CGFloat = 0
                color.getHue(&h, saturation: &s, brightness: &br, alpha: &al)
                let isDistinct = accepted.allSatisfy { other in
                    var oh: CGFloat = 0, os: CGFloat = 0, ob: CGFloat = 0, oa: CGFloat = 0
                    other.getHue(&oh, saturation: &os, brightness: &ob, alpha: &oa)
                    if s < 0.15 && os < 0.15 {
                        // Both near-gray: separate by brightness, not hue.
                        return abs(br - ob) > 0.18
                    }
                    // Hue distance on the 0...1 wheel, wrap-aware → degrees.
                    let raw = abs(h - oh)
                    let dist = Swift.min(raw, 1 - raw) * 360
                    return dist > 25
                }
                if isDistinct { accepted.append(color) }
            }

            DispatchQueue.main.async { completion(accepted) }
        }
    }

    /// Extract a toolkit's brand palette directly from its logo SVG's `fill="#…"`
    /// metadata, ordered by how many fills use each color (a cheap area proxy). The
    /// exact brand hex, not a histogram approximation. Returns [] for a monochrome mark
    /// (only black/white/none).
    ///
    /// Operates on the raw SVG bytes — no rasterization, no bitmap allocation — so it is
    /// strictly lighter than `dominantColors`, which survives only as a raster fallback
    /// for any non-SVG (PNG) logo. Composio's CDN serves SVGs whose brand colors sit in
    /// explicit `fill="#…"` attributes (gmail → `#EA4335 #34A853 #4285F4 #FBBC04`).
    ///
    /// Filtering thresholds (near-white, near-black) mirror `dominantColors` exactly so
    /// "monochrome" is detected identically on both paths. Near-identical fills collapse
    /// into one brand bucket using the same hue/brightness dedupe as `dominantColors`
    /// (gmail's `#EA4335` + `#C5221F` → one red bucket → red wins as the accent).
    static func brandColorsFromSVG(_ data: Data, max maxColors: Int = 4) -> [NSColor] {
        guard let svg = String(data: data, encoding: .utf8) else { return [] }
        // Composio SVGs carry colors as `fill="…"` attributes (not CSS `style=`).
        guard let re = try? NSRegularExpression(pattern: "fill\\s*=\\s*\"([^\"]*)\"",
                                                options: .caseInsensitive) else { return [] }
        let range = NSRange(svg.startIndex..., in: svg)

        // Brand buckets in first-seen (document) order; near-identical fills collapse
        // together and bump the bucket's count (more fills ≈ more area).
        var reps: [NSColor] = []
        var counts: [Int] = []

        re.enumerateMatches(in: svg, range: range) { match, _, _ in
            guard let match, let r = Range(match.range(at: 1), in: svg) else { return }
            guard let color = colorFromFill(String(svg[r])) else { return }
            if let idx = reps.firstIndex(where: { sameBrandBucket($0, color) }) {
                counts[idx] += 1
            } else {
                reps.append(color)
                counts.append(1)
            }
        }

        guard !reps.isEmpty else { return [] }

        // Occurrence count desc, document order (stable) as tiebreak.
        let ordered = zip(reps, counts).enumerated()
            .sorted { lhs, rhs in
                lhs.element.1 != rhs.element.1 ? lhs.element.1 > rhs.element.1
                                               : lhs.offset < rhs.offset
            }
            .map { $0.element.0 }

        return Array(ordered.prefix(maxColors))
    }

    /// Parse one SVG `fill` value into a brand color, or nil if it's a background /
    /// non-color to ignore. Uses the SAME thresholds as `dominantColors`: transparent/
    /// `none`, near-white (brightness > 0.92 && saturation < 0.12), near-black
    /// (brightness < 0.08).
    private static func colorFromFill(_ raw: String) -> NSColor? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch value {
        case "none", "transparent", "white", "black": return nil
        default: break
        }
        guard let color = colorFromHex(value) else { return nil }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        if b > 0.92 && s < 0.12 { return nil } // near-white bg
        if b < 0.08 { return nil }             // near-black
        return color
    }

    /// True when two colors collapse into the same brand bucket — same rule as
    /// `dominantColors`' dedupe: hue within 25° (wrap-aware), or both near-grey within
    /// 0.18 brightness.
    private static func sameBrandBucket(_ a: NSColor, _ b: NSColor) -> Bool {
        var ha: CGFloat = 0, sa: CGFloat = 0, ba: CGFloat = 0, aa: CGFloat = 0
        var hb: CGFloat = 0, sb: CGFloat = 0, bb: CGFloat = 0, ab: CGFloat = 0
        a.getHue(&ha, saturation: &sa, brightness: &ba, alpha: &aa)
        b.getHue(&hb, saturation: &sb, brightness: &bb, alpha: &ab)
        if sa < 0.15 && sb < 0.15 {
            return abs(ba - bb) <= 0.18 // both near-grey: separate by brightness
        }
        let rawDist = abs(ha - hb)
        return Swift.min(rawDist, 1 - rawDist) * 360 <= 25
    }

    /// Decode `#RGB`, `#RRGGBB`, or `#RRGGBBAA` into an sRGB NSColor (alpha ignored — we
    /// only want the hue). Returns nil for anything that isn't a hex triple. Shared by
    /// the SVG fill parser and `PiAgentManager`'s curated override table.
    static func colorFromHex(_ hex: String) -> NSColor? {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard s.hasPrefix("#") else { return nil }
        s.removeFirst()
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() } // #RGB → #RRGGBB
        guard s.count == 6 || s.count == 8,
              let value = UInt32(s.prefix(6), radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255.0,
                       green: CGFloat((value >> 8) & 0xFF) / 255.0,
                       blue: CGFloat(value & 0xFF) / 255.0,
                       alpha: 1)
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
