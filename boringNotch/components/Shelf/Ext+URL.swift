//
//  Ext+URL.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/8.
//

import Cocoa
import Foundation
import QuickLook

extension URL {
    func snapshotPreview() -> NSImage {
        if let preview = QLThumbnailImageCreate(
            kCFAllocatorDefault,
            self as CFURL,
            CGSize(width: 128, height: 128),
            nil
        )?.takeRetainedValue() {
            return NSImage(cgImage: preview, size: .zero)
        }
        return NSWorkspace.shared.icon(forFile: path)
    }
}
