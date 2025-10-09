//
//  ThumbnailService.swift
//  boringNotch
//
//  Created by Alexander on 2025-10-07.
//

import Foundation
import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

@MainActor
final class ThumbnailService {
    static let shared = ThumbnailService()

    private var cache: [String: NSImage] = [:]
    private let thumbnailGenerator = QLThumbnailGenerator.shared

    private init() {}
    
    func thumbnail(for url: URL, size: CGSize) async -> NSImage? {
        let cacheKey = "\(url.path)_\(size.width)x\(size.height)"
        
        if let cached = cache[cacheKey] {
            return cached
        }
        
        if let quickLookThumbnail = await generateQuickLookThumbnail(for: url, size: size) {
            cache[cacheKey] = quickLookThumbnail
            return quickLookThumbnail
        }
        
        return nil
    }
    
    func clearCache() {
        cache.removeAll()
    }
    
    func clearCache(for url: URL) {
        cache = cache.filter { !$0.key.starts(with: url.path) }
    }
    
    // MARK: - Private Methods
    
    private func generateQuickLookThumbnail(for url: URL, size: CGSize) async -> NSImage? {
    let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        return await url.accessSecurityScopedResource { scopedURL in
            NSLog("🔐 ThumbnailService: obtaining security scope for \(scopedURL.path)")
            let request = QLThumbnailGenerator.Request(
                fileAt: scopedURL,
                size: size,
                scale: scale,
                representationTypes: .all,
            )
            request.iconMode = true

            return await withCheckedContinuation { (continuation: CheckedContinuation<NSImage?, Never>) in
                thumbnailGenerator.generateBestRepresentation(for: request) { representation, error in
                    if let rep = representation {
                        NSLog("🔍 ThumbnailService: generated thumbnail for \(scopedURL.path)")
                        continuation.resume(returning: rep.nsImage)
                    } else {
                        if let err = error { NSLog("⚠️ ThumbnailService: thumbnail error for \(scopedURL.path): \(err.localizedDescription)") }
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }
}

// MARK: - Extensions

extension QLThumbnailRepresentation {
    var nsImage: NSImage {
        return NSImage(cgImage: self.cgImage, size: self.cgImage.size)
    }
}

extension CGImage {
    var size: NSSize {
        return NSSize(width: self.width, height: self.height)
    }
}
