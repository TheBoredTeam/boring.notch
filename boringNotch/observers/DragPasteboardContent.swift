//
//  DragPasteboardContent.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import AppKit
import UniformTypeIdentifiers

/// Droppable payload on the system drag pasteboard, shared by the notch shelf and the floating shelf.
enum DragPasteboardContent {
    private static let droppableTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        NSPasteboard.PasteboardType(UTType.url.identifier),
        .string
    ]

    /// An item may advertise extra formats alongside a supported one.
    static func isDroppable(_ pasteboard: NSPasteboard) -> Bool {
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else { return false }
        return items.allSatisfy { item in
            item.types.contains { droppableTypes.contains($0) }
        }
    }
}
