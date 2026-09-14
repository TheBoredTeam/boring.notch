//
//  QuickShareService.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-24.
//

import AppKit
import Defaults
import Foundation

struct QuickShareProvider: Identifiable, Hashable, Sendable {
    static let airDropId = NSSharingService.Name.sendViaAirDrop.rawValue
    static let systemShareMenuId = "com.boringnotch.share.system-picker"
    static let systemShareMenu = QuickShareProvider(
        id: systemShareMenuId,
        displayName: String(localized: "System Share Menu"),
        supportsRawText: true,
        isAvailable: true
    )

    let id: String
    let displayName: String
    let supportsRawText: Bool
    let isAvailable: Bool

    static func unavailable(id: String) -> QuickShareProvider {
        QuickShareProvider(
            id: id,
            displayName: id,
            supportsRawText: false,
            isAvailable: false
        )
    }

    static func migratedSelection(
        _ storedID: String,
        availableProviders: [QuickShareProvider]
    ) -> String {
        if storedID == "System Share Menu" {
            return systemShareMenuId
        }
        if storedID == "AirDrop" {
            return airDropId
        }
        if availableProviders.contains(where: { $0.id == storedID }) {
            return storedID
        }
        return availableProviders.first(where: { $0.displayName == storedID })?.id ?? storedID
    }
}

@MainActor
final class QuickShareService: ObservableObject {
    static let shared = QuickShareService()

    @Published private(set) var availableProviders: [QuickShareProvider] = [.systemShareMenu]
    @Published var isPickerOpen = false
    @Published private(set) var lastShareError: String?

    private var cachedServices: [String: NSSharingService] = [:]
    private var cachedIcons: [String: NSImage] = [:]
    private let finder: ShareServiceFinder
    private let decoder: ShelfTransferDecoder
    private let storage: TemporaryFileStorageService

    init(
        finder: ShareServiceFinder = ShareServiceFinder(),
        storage: TemporaryFileStorageService = .shared,
        automaticallyDiscoversProviders: Bool = true
    ) {
        self.finder = finder
        self.storage = storage
        self.decoder = ShelfTransferDecoder(storage: storage)
        if automaticallyDiscoversProviders {
            Task { await discoverAvailableProviders() }
        }
    }

    func provider(forStoredID storedID: String) -> QuickShareProvider {
        availableProviders.first(where: { $0.id == storedID })
            ?? .unavailable(id: storedID)
    }

    func providerOptions(including storedID: String) -> [QuickShareProvider] {
        guard !availableProviders.contains(where: { $0.id == storedID }) else {
            return availableProviders
        }
        return [.unavailable(id: storedID)] + availableProviders
    }

    func icon(for providerId: String, size: CGFloat) -> NSImage? {
        if providerId == QuickShareProvider.systemShareMenuId {
            return NSImage(
                systemSymbolName: "square.and.arrow.up",
                accessibilityDescription: String(localized: "Share")
            )
        }
        if let cachedIcon = cachedIcons[providerId] {
            return resizedIcon(cachedIcon, to: size)
        }
        guard let service = cachedServices[providerId] else { return nil }
        cachedIcons[providerId] = service.image
        return resizedIcon(service.image, to: size)
    }

    private func resizedIcon(_ image: NSImage, to size: CGFloat) -> NSImage {
        let targetSize = NSSize(width: size, height: size)
        return NSImage(size: targetSize, flipped: false) { rect in
            image.draw(
                in: rect,
                from: NSRect(origin: .zero, size: image.size),
                operation: .copy,
                fraction: 1
            )
            return true
        }
    }

    func discoverAvailableProviders() async {
        let sampleURL = URL(string: "https://example.com")
        let sampleItems: [Any] = sampleURL.map { [$0, "Test" as NSString] }
            ?? ["Test" as NSString]
        let services = await finder.findApplicableServices(for: sampleItems)
        applyDiscoveredServices(services)

        let storedID = Defaults[.quickShareProvider]
        let migratedID = QuickShareProvider.migratedSelection(
            storedID,
            availableProviders: availableProviders
        )
        if migratedID != storedID {
            Defaults[.quickShareProvider] = migratedID
        }
    }

    private func applyDiscoveredServices(_ services: [NamedSharingService]) {
        cachedServices.removeAll()
        cachedIcons.removeAll()
        var providers = services.map { namedService in
            let id = namedService.name.rawValue
            cachedServices[id] = namedService.service
            return QuickShareProvider(
                id: id,
                displayName: namedService.service.title,
                supportsRawText: namedService.service.canPerform(withItems: ["Test Text"]),
                isAvailable: true
            )
        }
        if let index = providers.firstIndex(where: { $0.id == QuickShareProvider.airDropId }) {
            providers.insert(providers.remove(at: index), at: 0)
        }
        providers.append(.systemShareMenu)
        availableProviders = providers
    }

    func showFilePicker(for provider: QuickShareProvider, from view: NSView?) async {
        guard !isPickerOpen else {
            Log.shelf.error("Quick Share file picker is already open")
            return
        }

        isPickerOpen = true
        SharingStateManager.shared.beginInteraction()

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.title = String(
            format: String(localized: "Select Files for %@"),
            provider.displayName
        )
        panel.message = String(
            format: String(localized: "Choose files to share via %@"),
            provider.displayName
        )

        let response = panel.runModal()
        isPickerOpen = false
        SharingStateManager.shared.endInteraction()
        if response == .OK, !panel.urls.isEmpty {
            await shareFilesOrText(panel.urls, using: provider, from: view)
        }
    }

    func shareFilesOrText(
        _ items: [Any],
        using provider: QuickShareProvider,
        from view: NSView?,
        resources suppliedResources: ShelfTransferResources? = nil
    ) async {
        lastShareError = nil
        let resources = suppliedResources ?? ShelfTransferResources(storage: storage)
        for url in items.compactMap({ $0 as? URL }).filter(\.isFileURL) {
            resources.beginAccessingSecurityScope(for: url)
        }

        let service: NSSharingService?
        if provider.id == QuickShareProvider.systemShareMenuId {
            service = nil
        } else {
            let actualServices = await finder.findApplicableServices(for: items)
            service = actualServices.first(where: { $0.name.rawValue == provider.id })?.service
            guard service != nil else {
                resources.release()
                lastShareError = String(
                    format: String(localized: "“%@” is unavailable for these items."),
                    provider.displayName
                )
                return
            }
        }

        let delegate = SharingStateManager.shared.makeDelegate {
            resources.release()
        }

        if let service {
            delegate.markServiceBegan()
            service.delegate = delegate
            service.perform(withItems: items)
            return
        }

        guard let view else {
            delegate.cancel()
            lastShareError = String(localized: "The System Share Menu could not be shown.")
            return
        }
        let picker = NSSharingServicePicker(items: items)
        picker.delegate = delegate
        delegate.markPickerBegan()
        picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
    }

    func shareDroppedFiles(
        _ providers: [NSItemProvider],
        using shareProvider: QuickShareProvider,
        from view: NSView?
    ) async {
        let batch = await decoder.decode(providers)
        var itemsToShare: [Any] = []
        itemsToShare.reserveCapacity(batch.values.count)

        for value in batch.values {
            switch value {
            case .file(let file):
                itemsToShare.append(file.url)
            case .link(let url):
                itemsToShare.append(url)
            case .text(let text):
                if shareProvider.supportsRawText {
                    itemsToShare.append(text)
                } else if let textURL = await storage.createTempFile(for: .text(text)) {
                    batch.resources.registerOwnedTemporaryFile(textURL)
                    itemsToShare.append(textURL)
                }
            }
        }

        guard !itemsToShare.isEmpty else {
            batch.resources.release()
            lastShareError = String(localized: "No shareable items were found.")
            return
        }
        await shareFilesOrText(
            itemsToShare,
            using: shareProvider,
            from: view,
            resources: batch.resources
        )
    }
}
