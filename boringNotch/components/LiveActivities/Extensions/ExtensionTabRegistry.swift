// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

import AppKit
import Combine

@MainActor
protocol ExtensionTabControllerSource: AnyObject {
    func supportsTabPresentation(_ presentation: ExtensionTabPresentation) -> Bool
    func tabController(id: String, context: ExtensionTabLayoutContext) -> NSViewController?
}

extension ExtensionTabControllerSource {
    func supportsTabPresentation(_ presentation: ExtensionTabPresentation) -> Bool { presentation == .regular }
}

extension ExtensionRuntime: ExtensionTabControllerSource {}

/// Retains providers while their tabs are available, but never retains or
/// caches view controllers. Each mounted display owns its own controller.
@MainActor
final class ExtensionTabRegistry: ObservableObject {
    static let shared = ExtensionTabRegistry()
    @Published private(set) var tabs: [ExtensionTab] = []
    private var providers: [String: [ExtensionTab]] = [:]

    func replace(providerID: String, tabs: [ExtensionTabDescriptor], runtime: ExtensionRuntime) {
        replace(providerID: providerID, tabs: tabs, source: runtime)
    }

    func replace(providerID: String, tabs: [ExtensionTabDescriptor], source: any ExtensionTabControllerSource) {
        guard (try? ExtensionTabSnapshot(tabs: tabs).validate()) != nil else {
            remove(providerID: providerID)
            return
        }
        let existing = providers[providerID] ?? []
        guard existing.map(\.descriptor) != tabs || existing.contains(where: { $0.source !== source }) else { return }
        let previous = Dictionary(uniqueKeysWithValues: existing.map { ($0.id.localID, $0) })
        let replacement = tabs.map {
            ExtensionTab(id: ExtensionTabID(providerID: providerID, localID: $0.id), descriptor: $0, source: source,
                         previous: previous[$0.id])
        }
        guard providers[providerID] != replacement else { return }
        if replacement.isEmpty {
            providers.removeValue(forKey: providerID)
        } else {
            providers[providerID] = replacement
        }
        publish()
    }

    func remove(providerID: String) {
        guard providers.removeValue(forKey: providerID) != nil else { return }
        publish()
    }

    func tabs(for presentation: ExtensionTabPresentation) -> [ExtensionTab] {
        tabs.filter { $0.supports(presentation) }
    }

    func tab(for id: ExtensionTabID, presentation: ExtensionTabPresentation = .regular) -> ExtensionTab? {
        providers[id.providerID]?.first { $0.id == id && $0.supports(presentation) }
    }

    private func publish() {
        let next = providers.keys.sorted().flatMap { providers[$0] ?? [] }
        if next != tabs { tabs = next }
    }
}

struct ExtensionTab: Identifiable, Equatable {
    let id: ExtensionTabID
    let descriptor: ExtensionTabDescriptor
    let source: any ExtensionTabControllerSource
    let systemSymbol: String
    let iconImage: NSImage?

    @MainActor
    init(id: ExtensionTabID, descriptor: ExtensionTabDescriptor, source: any ExtensionTabControllerSource,
         previous: ExtensionTab? = nil) {
        self.id = id
        self.descriptor = descriptor
        self.source = source
        // Resolve once for this registration. Rendering a large tab strip
        // must not repeatedly load SF Symbols just to validate their names.
        if let previous, previous.descriptor.symbol == descriptor.symbol {
            systemSymbol = previous.systemSymbol
        } else {
            systemSymbol = descriptor.systemSymbol
        }
        if let previous, previous.descriptor.iconPNG == descriptor.iconPNG {
            iconImage = previous.iconImage
        } else {
            iconImage = ExtensionTabIcon.decode(descriptor.iconPNG)
        }
    }

    @MainActor func supports(_ presentation: ExtensionTabPresentation) -> Bool {
        descriptor.supports(presentation) && source.supportsTabPresentation(presentation)
    }

    @MainActor func contentIdentity(context: ExtensionTabLayoutContext) -> ExtensionTabContentID {
        ExtensionTabContentID(tab: id, source: ObjectIdentifier(source), context: context)
    }

    @MainActor func makeController(context: ExtensionTabLayoutContext) -> NSViewController? {
        guard context.isValid, supports(context.presentation) else { return nil }
        return source.tabController(id: id.localID, context: context)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.descriptor == rhs.descriptor && lhs.source === rhs.source
    }
}

struct ExtensionTabContentID: Hashable {
    let tab: ExtensionTabID
    let source: ObjectIdentifier
    let context: ExtensionTabLayoutContext
}
