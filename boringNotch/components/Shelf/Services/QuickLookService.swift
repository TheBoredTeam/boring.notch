//
//  QuickLookService.swift
//  boringNotch
//
//  Created by Alexander on 2025-10-07.
//

import Foundation
import Combine
import UniformTypeIdentifiers
import SwiftUI
import QuickLook
import QuickLookUI
import AppKit

struct ShelfQuickLookRequestGeneration: Sendable {
    private var value: UInt = 0

    mutating func begin() -> UInt {
        value &+= 1
        return value
    }

    mutating func invalidate() {
        value &+= 1
    }

    func isCurrent(_ candidate: UInt) -> Bool {
        candidate == value
    }
}

@MainActor
final class QuickLookService: ObservableObject {
    @Published var urls: [URL] = []
    @Published var selectedURL: URL?

    @Published var isQuickLookOpen: Bool = false

    private var previewPanel: QLPreviewPanel?
    private var accessingURLs: [URL] = []
    private var previewPanelObserver: Any?
    private var selectionCancellable: AnyCancellable?
    private var selectionTask: Task<Void, Never>?
    private var requestGeneration = ShelfQuickLookRequestGeneration()
    private let shelfState: ShelfStateViewModel
    private let presentsPanel: Bool

    init(
        shelfState: ShelfStateViewModel = .shared,
        observeShelfSelection: Bool = true,
        presentsPanel: Bool = true
    ) {
        self.shelfState = shelfState
        self.presentsPanel = presentsPanel
        if observeShelfSelection {
            selectionCancellable = ShelfSelectionModel.shared.$selectedIDs
                .dropFirst()
                .sink { [weak self] selectedIDs in
                    self?.selectionTask?.cancel()
                    self?.selectionTask = Task { [weak self] in
                        await self?.applyShelfSelection(selectedIDs: selectedIDs)
                    }
                }
        }
    }

    func show(urls: [URL], selectFirst: Bool = true, slideshow: Bool = false) {
        guard !urls.isEmpty else { return }
        selectionTask?.cancel()
        let generation = requestGeneration.begin()
        present(urls: urls, selectFirst: selectFirst, generation: generation)
    }

    private func present(urls: [URL], selectFirst: Bool, generation: UInt) {
        guard requestGeneration.isCurrent(generation) else { return }
        stopAccessingCurrentURLs()
        accessingURLs = urls.filter { url in
            if url.isFileURL {
                return url.startAccessingSecurityScopedResource()
            }
            return true
        }
        self.urls = accessingURLs
        self.isQuickLookOpen = true

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            if selectFirst,
               self.requestGeneration.isCurrent(generation),
               self.isQuickLookOpen {
                self.selectedURL = accessingURLs.first
            }
        }

        guard presentsPanel else { return }
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
        selectionTask?.cancel()
        requestGeneration.invalidate()
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
    }

    func updateSelection(urls: [URL]) {
        guard isQuickLookOpen else { return }
        show(urls: urls, selectFirst: true)
    }

    func applyShelfSelection(selectedIDs: Set<UUID>) async {
        guard isQuickLookOpen else { return }
        guard !selectedIDs.isEmpty else {
            hide()
            return
        }

        let generation = requestGeneration.begin()
        stopAccessingCurrentURLs()
        selectedURL = nil
        urls.removeAll()

        var resolvedURLs: [URL] = []
        for item in shelfState.items where selectedIDs.contains(item.id) {
            switch item.kind {
            case .file:
                if let file = await shelfState.resolveFile(
                    for: item,
                    intent: .userInitiated,
                    refresh: true
                ) {
                    resolvedURLs.append(file.url)
                }
            case .link(let url):
                resolvedURLs.append(url)
            case .text:
                break
            }
        }

        guard !Task.isCancelled,
              requestGeneration.isCurrent(generation),
              isQuickLookOpen else { return }
        guard !resolvedURLs.isEmpty else {
            hide()
            return
        }
        present(urls: resolvedURLs, selectFirst: true, generation: generation)
    }
}

extension QuickLookService {
    @objc private func previewPanelWillClose(_ notification: Notification) {
        guard let panel = notification.object as? QLPreviewPanel, panel === previewPanel else { return }
        // Ensure cleanup happens on main actor
        Task { @MainActor in
            selectionTask?.cancel()
            requestGeneration.invalidate()
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
