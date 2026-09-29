// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Combine

@MainActor
protocol ExtensionTabControllerSource: AnyObject {
    func tabController(id: String, displayID: String?) -> NSViewController?
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
        let replacement = tabs.map {
            ExtensionTab(id: ExtensionTabID(providerID: providerID, localID: $0.id), descriptor: $0, source: source)
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

    func tab(for id: ExtensionTabID) -> ExtensionTab? {
        providers[id.providerID]?.first { $0.id == id }
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

    @MainActor func contentIdentity(displayID: String?) -> ExtensionTabContentID {
        ExtensionTabContentID(tab: id, source: ObjectIdentifier(source), displayID: displayID)
    }

    @MainActor func makeController(displayID: String?) -> NSViewController? {
        source.tabController(id: id.localID, displayID: displayID)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.descriptor == rhs.descriptor && lhs.source === rhs.source
    }
}

struct ExtensionTabContentID: Hashable {
    let tab: ExtensionTabID
    let source: ObjectIdentifier
    let displayID: String?
}
