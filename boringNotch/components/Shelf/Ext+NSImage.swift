//
//  Ext+NSImage.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/8.
//

import Cocoa

extension NSImage {
    var pngRepresentation: Data {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .init()
        }
        let imageRep = NSBitmapImageRep(cgImage: cgImage)
        imageRep.size = size
        return imageRep.representation(using: .png, properties: [:]) ?? .init()
    }
}
