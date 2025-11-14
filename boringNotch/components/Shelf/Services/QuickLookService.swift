//
//  QuickLookService.swift
//  boringNotch
//
//  Created by Alexander on 2025-10-07.
//

import Foundation
import UniformTypeIdentifiers
import SwiftUI
import QuickLookUI
import AppKit

@MainActor
final class QuickLookService: ObservableObject {
    @Published var urls: [URL] = []
    @Published var selectedURL: URL?

    @Published var isQuickLookOpen: Bool = false

    private var previewPanel: QLPreviewPanel?
    private var dataSource: QuickLookDataSource?
    private var accessingURLs: [URL] = []
    private var previewPanelObserver: Any?

    func show(urls: [URL], selectFirst: Bool = true, slideshow: Bool = false) {
        guard !urls.isEmpty else { return }
        stopAccessingCurrentURLs()
        accessingURLs = urls.filter { url in
            if url.isFileURL {
                return url.startAccessingSecurityScopedResource()
            }
            return true
        }
        self.urls = accessingURLs
        self.isQuickLookOpen = true
        if selectFirst {
            self.selectedURL = accessingURLs.first
        }
        // Observe the shared Quick Look preview panel closing so we can relinquish security scope
        let panel = QLPreviewPanel.shared()
        // Remove any existing observer for previous panel
        if let prev = previewPanel {
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: prev)
        }
        previewPanel = panel
        NotificationCenter.default.addObserver(self, selector: #selector(previewPanelWillClose(_:)), name: NSWindow.willCloseNotification, object: panel)
    }

    func hide() {
        stopAccessingCurrentURLs()
        selectedURL = nil
        urls.removeAll()
        isQuickLookOpen = false
        if let panel = previewPanel, panel.isVisible {
            panel.orderOut(nil)
        }
        if let panel = previewPanel {
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: panel)
            previewPanel = nil
        }
    }
    
    private func stopAccessingCurrentURLs() {
        NSLog("Stopping access to \(accessingURLs.count) URLs")
        for url in accessingURLs where url.isFileURL {
            url.stopAccessingSecurityScopedResource()
        }
        accessingURLs.removeAll()
        // If Quick Look panel was closed externally, also remove observer and clear reference
        if let panel = previewPanel {
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: panel)
            previewPanel = nil
        }
    }
    
    func showQuickLook(urls: [URL]) {
        show(urls: urls, selectFirst: true, slideshow: false)
    }

    func updateSelection(urls: [URL]) {
        guard isQuickLookOpen else { return }
    show(urls: urls, selectFirst: true)
    }
}

extension QuickLookService {
    @objc private func previewPanelWillClose(_ notification: Notification) {
        guard let panel = notification.object as? QLPreviewPanel, panel === previewPanel else { return }
        // Ensure cleanup happens on main actor
        Task { @MainActor in
            stopAccessingCurrentURLs()
            selectedURL = nil
            urls.removeAll()
            isQuickLookOpen = false
            // Remove observer and clear reference
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: panel)
            previewPanel = nil
        }
    }
}

struct QuickLookPresenter: ViewModifier {
    @ObservedObject var service: QuickLookService

    func body(content: Content) -> some View {
        content
            .quickLookPreview($service.selectedURL, in: service.urls)
    }
}

extension View {
    func quickLookPresenter(using service: QuickLookService) -> some View {
        self.modifier(QuickLookPresenter(service: service))
    }
}


final class QuickLookDataSource: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private let urls: [URL]

    init(urls: [URL]) {
        self.urls = urls
        super.init()
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return urls.count
    }
    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard index >= 0 && index < urls.count else { return nil }
        return urls[index] as QLPreviewItem
    }
}
