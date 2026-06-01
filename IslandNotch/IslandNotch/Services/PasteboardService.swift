//  PasteboardService.swift
//  IslandNotch
//
//  Purpose: Writes a screenshot to the clipboard in the form the active agent
//           wants — a path string or the image bytes.
//  Layer: Service

import AppKit
import Foundation

enum PasteboardService {
    /// Copies `url` to the general pasteboard formatted for `mode`.
    /// Returns false only if image bytes were requested but couldn't be loaded.
    @discardableResult
    static func copy(url: URL, mode: PayloadMode) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch mode {
        case .pathPlain:
            pb.setString(url.path, forType: .string)
            return true
        case .pathLookAtPrefixed:
            pb.setString("look at " + url.path, forType: .string)
            return true
        case .imageBytes:
            guard let image = NSImage(contentsOf: url) else {
                Log.store.error("imageBytes copy failed; no image at \(url.path)")
                return false
            }
            return pb.writeObjects([image])
        }
    }
}
