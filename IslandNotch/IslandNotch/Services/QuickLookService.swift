//  QuickLookService.swift
//  IslandNotch
//
//  Purpose: Shows a full-res, offline Quick Look preview of a screenshot on
//           right-click. Backs QLPreviewPanel with a single-item data source.
//  Layer: Service

import AppKit
import Quartz

/// Singleton Quick Look controller. QLPreviewPanel is app-global, so the data
/// source must be a stable object the panel can call back into.
final class QuickLookService: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookService()

    private var items: [URL] = []

    /// Presents the panel previewing `url`.
    func preview(_ url: URL) {
        items = [url]
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        if QLPreviewPanel.sharedPreviewPanelExists() && panel.isVisible {
            panel.reloadData()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { items.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        items[index] as NSURL
    }
}
