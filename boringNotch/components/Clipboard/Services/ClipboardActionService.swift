//
//  ClipboardActionService.swift
//  boringNotch
//

import AppKit
import Foundation
import UniformTypeIdentifiers

/// Actions available on a clipboard entry. Mirrors `ShelfActionService`'s static-namespace shape.
@MainActor
enum ClipboardActionService {
    /// Security-scoped URLs kept open for the lifetime of the copy, so the receiving app can
    /// still resolve them when the user pastes. Released on the next copy.
    /// Same approach as `ShelfItemViewModel.copiedURLs`.
    private static var copiedURLs: [URL] = []

    /// Puts an entry back on the pasteboard.
    ///
    /// Routed through `ClipboardMonitor.performOwnWrite` so the write does not come back around
    /// as a fresh capture on the next poll.
    static func copy(_ item: ClipboardItem) {
        releaseCopiedURLs()

        ClipboardMonitor.shared.performOwnWrite { pb in
            switch item.kind {
            case .text(let string):
                pb.setString(string, forType: .string)

            case .link(let url):
                pb.setString(url.absoluteString, forType: .string)
                pb.setString(url.absoluteString, forType: .URL)

            case .image(let ref):
                let blobURL = ClipboardBlobStore.shared.url(forFileName: ref.fileName)
                guard let data = try? Data(contentsOf: blobURL) else {
                    print("❌ Clipboard image blob missing: \(ref.fileName)")
                    return
                }
                // Write back the original representation, not a transcode.
                let type: NSPasteboard.PasteboardType =
                    ref.utiIdentifier == UTType.tiff.identifier ? .tiff : .png
                pb.setData(data, forType: type)

            case .files(let refs):
                let urls = resolveURLs(for: refs)
                guard !urls.isEmpty else { return }
                // Hold the scope open past this call; the paste happens later.
                copiedURLs = urls.filter { $0.startAccessingSecurityScopedResource() }
                pb.writeObjects(urls as [NSURL])
                pb.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
            }
        }
    }

    static func copyPath(_ item: ClipboardItem) {
        guard case .files(let refs) = item.kind else { return }
        ClipboardMonitor.shared.performOwnWrite { pb in
            pb.setString(refs.map(\.path).joined(separator: "\n"), forType: .string)
        }
    }

    static func openLink(_ item: ClipboardItem) {
        guard case .link(let url) = item.kind else { return }
        NSWorkspace.shared.open(url)
    }

    /// Works with or without a resolvable bookmark: revealing is an app-to-app request to Finder,
    /// not a file read, so the plain path is enough.
    static func revealInFinder(_ item: ClipboardItem) {
        guard case .files(let refs) = item.kind, let first = refs.first else { return }
        let url = resolveURL(for: first) ?? first.url
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func delete(_ item: ClipboardItem) {
        let id = item.id
        ClipboardStore.shared.remove(item)
        Task { await ClipboardThumbnailCache.shared.evict(id) }
    }

    static func clearAll() {
        ClipboardStore.shared.clearAll()
        Task { await ClipboardThumbnailCache.shared.clear() }
    }

    // MARK: - Helpers

    private static func resolveURLs(for refs: [ClipboardFileRef]) -> [URL] {
        refs.compactMap { resolveURL(for: $0) ?? $0.url }
    }

    private static func resolveURL(for ref: ClipboardFileRef) -> URL? {
        guard let data = ref.bookmark else { return nil }
        return Bookmark(data: data).resolveURL()
    }

    private static func releaseCopiedURLs() {
        for url in copiedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        copiedURLs.removeAll()
    }
}
