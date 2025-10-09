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
    }

    func hide() {
        stopAccessingCurrentURLs()
        selectedURL = nil
        urls.removeAll()
        isQuickLookOpen = false
        if let panel = previewPanel, panel.isVisible {
            panel.orderOut(nil)
        }
    }
    
    private func stopAccessingCurrentURLs() {
        for url in accessingURLs where url.isFileURL {
            url.stopAccessingSecurityScopedResource()
        }
        accessingURLs.removeAll()
    }
    
    func showQuickLook(urls: [URL]) {
        show(urls: urls, selectFirst: true, slideshow: false)
    }

    func updateSelection(urls: [URL]) {
        guard isQuickLookOpen else { return }
    show(urls: urls, selectFirst: true)
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
