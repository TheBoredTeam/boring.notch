//
//  QuickShareService.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-24.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

/// Dynamic representation of a sharing provider discovered at runtime
struct QuickShareProvider: Identifiable, Hashable, Sendable {
    var id: String
    var supportsRawText: Bool
}

class QuickShareService: ObservableObject {
    static let shared = QuickShareService()
    
    @Published var availableProviders: [QuickShareProvider] = []
    @Published var isPickerOpen = false
    private var cachedServices: [String: NSSharingService] = [:]
    private var cachedIcons: [String: NSImage] = [:]
    private var cachedApplicationURLsByName: [String: URL]?
    // Hold security-scoped URLs during sharing
    private var sharingAccessingURLs: [URL] = []
    private var lifecycleDelegate: SharingLifecycleDelegate?
   
    init() {
        Task {
            await discoverAvailableProviders()
        }
    }
    
    // MARK: - Icon Retrieval

    @MainActor
    func icon(for providerId: String, size: CGFloat) -> NSImage? {
        if let cachedIcon = cachedIcons[providerId] {
            return resizedIcon(cachedIcon, to: size)
        }

        if let providerIcon = applicationIcon(for: providerId) {
            cachedIcons[providerId] = providerIcon
            return resizedIcon(providerIcon, to: size)
        }

        // For system share menu, return a generic share icon
        if providerId == "System Share Menu" {
            return NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Share")
        }
        
        // Try to get icon from cached service
        if let service = cachedServices[providerId] {
            return resizedIcon(service.image, to: size)
        }

        return nil
    }

    private func applicationIcon(for providerId: String) -> NSImage? {
        guard let applicationURL = applicationURLsByName()[normalizedApplicationName(providerId)] else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: applicationURL.path)
    }

    private func applicationURLsByName() -> [String: URL] {
        if let cachedApplicationURLsByName {
            return cachedApplicationURLsByName
        }

        var urlsByName: [String: URL] = [:]
        for root in applicationSearchRoots {
            indexApplications(in: root, into: &urlsByName)
        }

        cachedApplicationURLsByName = urlsByName
        return urlsByName
    }

    private var applicationSearchRoots: [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app/Contents/Applications", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer/Applications", isDirectory: true)
        ]
    }

    private func indexApplications(in root: URL, into urlsByName: inout [String: URL]) {
        guard FileManager.default.fileExists(atPath: root.path),
              let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isApplicationKey, .localizedNameKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
              ) else {
            return
        }

        for case let url as URL in enumerator where url.pathExtension == "app" {
            indexApplication(url, into: &urlsByName)
        }
    }

    private func indexApplication(_ applicationURL: URL, into urlsByName: inout [String: URL]) {
        cacheApplicationName(applicationURL.deletingPathExtension().lastPathComponent, for: applicationURL, in: &urlsByName)

        if let localizedName = try? applicationURL.resourceValues(forKeys: [.localizedNameKey]).localizedName {
            cacheApplicationName(localizedName, for: applicationURL, in: &urlsByName)
        }

        guard let bundle = Bundle(url: applicationURL) else { return }

        if let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
            cacheApplicationName(bundleName, for: applicationURL, in: &urlsByName)
        }

        if let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
            cacheApplicationName(displayName, for: applicationURL, in: &urlsByName)
        }
    }

    private func cacheApplicationName(_ name: String, for applicationURL: URL, in urlsByName: inout [String: URL]) {
        let normalizedName = normalizedApplicationName(name)
        guard !normalizedName.isEmpty, urlsByName[normalizedName] == nil else { return }
        urlsByName[normalizedName] = applicationURL
    }

    private func normalizedApplicationName(_ name: String) -> String {
        name
            .replacingOccurrences(of: ".app", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
    
    private func resizedIcon(_ image: NSImage, to size: CGFloat) -> NSImage {
        let targetSize = NSSize(width: size, height: size)
        return NSImage(size: targetSize, flipped: false) { rect in
            image.draw(in: rect,
                       from: NSRect(origin: .zero, size: image.size),
                       operation: .copy,
                       fraction: 1.0)
            return true
        }
    }
    // MARK: - Provider Discovery
    
    @MainActor
    func discoverAvailableProviders() async {
        let finder = ShareServiceFinder()

        let testItems: [Any] = [
            URL(string:"http://example.com")!,
            "Test" as NSString
        ]

        let services = await finder.findApplicableServices(for: testItems)

        var providers: [QuickShareProvider] = []

        for svc in services {
            let title = svc.title
            let supportsRawText = svc.canPerform(withItems: ["Test Text"])
            let provider = QuickShareProvider(id: title, supportsRawText: supportsRawText)
            if !providers.contains(provider) {
                providers.append(provider)
                cachedServices[title] = svc
            }
        }
        
        if let idx = providers.firstIndex(where: { $0.id == "AirDrop" }) {
            let ad = providers.remove(at: idx)
            providers.insert(ad, at: 0)
        }

        if !providers.contains(where: { $0.id == "System Share Menu" }) {
            providers.append(QuickShareProvider(id: "System Share Menu", supportsRawText: true))
        }

        self.availableProviders = providers

    }
    
    // MARK: - File Picker
    @MainActor
    func showFilePicker(for provider: QuickShareProvider, from view: NSView?) async {
        guard !isPickerOpen else {
            print("⚠️ QuickShareService: File picker already open")
            return
        }

        isPickerOpen = true
        SharingStateManager.shared.beginInteraction()

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.title = "Select Files for \(provider.id)"
        panel.message = "Choose files to share via \(provider.id)"

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            defer {
                self?.isPickerOpen = false
                SharingStateManager.shared.endInteraction()
            }

            if response == .OK && !panel.urls.isEmpty {
                Task {
                    await self?.shareFilesOrText(panel.urls, using: provider, from: view)
                }
            }
        }

        let response = panel.runModal()
        completion(response)
    }
    
    // MARK: - Sharing
    @MainActor
    func shareFilesOrText(_ items: [Any], using provider: QuickShareProvider, from view: NSView?) async {
        let fileURLs = items.compactMap { $0 as? URL }.filter { $0.isFileURL }
        // Stop any previous sharing access
        stopSharingAccessingURLs()
        // Start security-scoped access for all file URLs
        sharingAccessingURLs = fileURLs.filter { $0.startAccessingSecurityScopedResource() }

        // Setup lifecycle delegate to keep notch open during picker/service
        let delegate = SharingStateManager.shared.makeDelegate { [weak self] in
            self?.lifecycleDelegate = nil
            self?.stopSharingAccessingURLs()
        }
        lifecycleDelegate = delegate

        if let svc = cachedServices[provider.id], svc.canPerform(withItems: items) {
            // For direct service path, explicitly mark service interaction start
            delegate.markServiceBegan()
            svc.delegate = delegate
            svc.perform(withItems: items)
        } else {
            let picker = NSSharingServicePicker(items: items)
            picker.delegate = delegate
            delegate.markPickerBegan()
            if let view {
                picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
            }
        }
    }

    private func stopSharingAccessingURLs() {
        NSLog("Stopping sharing access to URLs")
        for url in sharingAccessingURLs {
            url.stopAccessingSecurityScopedResource()
        }
        sharingAccessingURLs.removeAll()
    }
// MARK: - SharingServiceDelegate

private class SharingServiceDelegate: NSObject {}
    
    func shareDroppedFiles(_ providers: [NSItemProvider], using shareProvider: QuickShareProvider, from view: NSView?) async {
        var itemsToShare: [Any] = []
        var foundText: String?

        for provider in providers {
            if let webURL = await provider.extractURL() {
                itemsToShare.append(webURL)
            } else if foundText == nil, let text = await provider.extractText() {
                foundText = text
            } else if let itemFileURL = await provider.extractItem() {
                let resolvedURL = await resolveShelfItemBookmark(for: itemFileURL) ?? itemFileURL
                itemsToShare.append(resolvedURL)
            }
        }

        // If text was found, prioritize sharing it.
        if let text = foundText {
            if shareProvider.supportsRawText {
                await shareFilesOrText([text], using: shareProvider, from: view)
            } else {
                if let tempTextURL = await TemporaryFileStorageService.shared.createTempFile(for: .text(text)) {
                    await shareFilesOrText([tempTextURL], using: shareProvider, from: view)
                    TemporaryFileStorageService.shared.removeTemporaryFileIfNeeded(at: tempTextURL)
                } else {
                    await shareFilesOrText([text], using: shareProvider, from: view)
                }
            }
        } else if !itemsToShare.isEmpty {
            await shareFilesOrText(itemsToShare, using: shareProvider, from: view)
        }
    }

    private func resolveShelfItemBookmark(for fileURL: URL) async -> URL? {
        let items = await ShelfStateViewModel.shared.items

        for itm in items {
            if let resolved = await ShelfStateViewModel.shared.resolveAndUpdateBookmark(for: itm) {
                if resolved.standardizedFileURL.path == fileURL.standardizedFileURL.path {
                    return resolved
                }
            }
        }
        print("❌ Failed to resolve bookmark for shelf item")
        return nil
    }
}

// MARK: - App Storage Extension for Provider Selection

extension QuickShareProvider {
    static var defaultProvider: QuickShareProvider {
        let svc = QuickShareService.shared

        if let airdrop = svc.availableProviders.first(where: { $0.id == "AirDrop" }) {
            return airdrop
        }
        return svc.availableProviders.first ?? QuickShareProvider(id: "System Share Menu", supportsRawText: true)
    }
}
