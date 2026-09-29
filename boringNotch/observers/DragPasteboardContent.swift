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

    /// True when every dragged item can be stored on the shelf.
    /// An item may advertise extra formats alongside a supported one.
    static func isDroppable(_ pasteboard: NSPasteboard) -> Bool {
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else { return false }
        return items.allSatisfy { item in
            item.types.contains { droppableTypes.contains($0) }
        }
    }

    static func itemProviders(from pasteboard: NSPasteboard) -> [NSItemProvider] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.compactMap(itemProvider(from:))
    }

    private static func itemProvider(from item: NSPasteboardItem) -> NSItemProvider? {
        let provider = NSItemProvider()
        var didRegister = false
        for type in item.types {
            guard let data = item.data(forType: type) else { continue }
            provider.registerDataRepresentation(forTypeIdentifier: type.rawValue, visibility: .all) { completion in
                completion(data, nil)
                return nil
            }
            didRegister = true
        }
        guard didRegister else { return nil }
        return provider
    }
}
