//
//  ClipboardHistoryViewModel.swift
//  boringNotch
//
//  Created by Claude on 2026-07-05.
//

import AppKit
import Combine
import Defaults
import SwiftUI

@MainActor
final class ClipboardHistoryViewModel: ObservableObject {
    static let shared = ClipboardHistoryViewModel()

    @Published private(set) var items: [ClipboardItem] = []

    private let persistence = ClipboardPersistenceService.shared
    private var enabledCancellable: AnyCancellable?

    private init() {
        items = persistence.load()
        persistence.pruneOrphanedImages(keeping: items)

        enabledCancellable = Defaults.publisher(.enableClipboardHistory)
            .sink { change in
                Task { @MainActor in
                    if change.newValue {
                        ClipboardMonitorService.shared.start()
                    } else {
                        ClipboardMonitorService.shared.stop()
                        if BoringViewCoordinator.shared.currentView == .clipboard {
                            BoringViewCoordinator.shared.showEmpty()
                        }
                    }
                }
            }
    }

    /// Called once at app start; the Defaults publisher above keeps the
    /// monitor in sync with the setting afterwards.
    func bootstrap() {
        if Defaults[.enableClipboardHistory] {
            ClipboardMonitorService.shared.start()
        }
    }

    var isEmpty: Bool { items.isEmpty }

    // MARK: - Mutations

    func add(_ item: ClipboardItem) {
        if let latest = items.first(where: { !$0.pinned }),
           latest.contentFingerprint == item.contentFingerprint
        {
            return
        }
        items.insert(item, at: 0)
        enforceLimit()
        persist()
    }

    func delete(_ item: ClipboardItem) {
        if let fileName = item.imageFileName {
            persistence.deleteImage(fileName: fileName)
        }
        items.removeAll { $0.id == item.id }
        persist()
    }

    func togglePin(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].pinned.toggle()
        persist()
    }

    func clearAll() {
        for item in items where !item.pinned {
            if let fileName = item.imageFileName {
                persistence.deleteImage(fileName: fileName)
            }
        }
        items.removeAll { !$0.pinned }
        persist()
    }

    // MARK: - Copy back

    func copyToPasteboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.kind {
        case .text, .link:
            pasteboard.setString(item.plainText ?? "", forType: .string)
        case .image:
            if let fileName = item.imageFileName,
               let image = persistence.loadImage(fileName: fileName)
            {
                pasteboard.writeObjects([image])
            }
        case .fileURL:
            // Sandbox access to the original files is gone once they left the
            // pasteboard, so re-copy the paths as text.
            let paths = (item.fileURLStrings ?? [])
                .compactMap { URL(string: $0)?.path }
                .joined(separator: "\n")
            pasteboard.setString(paths, forType: .string)
        }

        ClipboardMonitorService.shared.ignoredChangeCount = pasteboard.changeCount
    }

    // MARK: - Private

    private func enforceLimit() {
        let limit = max(1, Defaults[.clipboardHistorySize])
        var unpinnedCount = items.filter { !$0.pinned }.count
        guard unpinnedCount > limit else { return }
        for item in items.reversed() where !item.pinned && unpinnedCount > limit {
            if let fileName = item.imageFileName {
                persistence.deleteImage(fileName: fileName)
            }
            items.removeAll { $0.id == item.id }
            unpinnedCount -= 1
        }
    }

    private func persist() {
        persistence.save(items)
    }
}
