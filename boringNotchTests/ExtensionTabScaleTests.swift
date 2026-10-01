// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

import AppKit
import Combine
import SwiftUI
import XCTest
@testable import boringNotch

/// Sources deliberately retain no controllers. A weak audit distinguishes
/// registered metadata from actual mounted content, including retired views.
@MainActor
private final class ScaleTabAudit {
    @MainActor
    final class Record {
        let id: ExtensionTabID
        let context: ExtensionTabLayoutContext
        weak var controller: NSViewController?
        weak var view: NSView?

        init(id: ExtensionTabID, context: ExtensionTabLayoutContext, controller: NSViewController) {
            self.id = id
            self.context = context
            self.controller = controller
            view = controller.view
        }
    }

    var records: [Record] = []
    var liveControllerCount: Int { records.filter { $0.controller != nil }.count }
}

private final class ScaleWeakReference<T: AnyObject> {
    weak var value: T?
    init(_ value: T?) { self.value = value }
}

@MainActor
private final class ScaleTabSource: ExtensionTabControllerSource {
    let providerID: String
    let supportsCompact: Bool
    let audit: ScaleTabAudit

    init(providerID: String, supportsCompact: Bool, audit: ScaleTabAudit) {
        self.providerID = providerID
        self.supportsCompact = supportsCompact
        self.audit = audit
    }

    func supportsTabPresentation(_ presentation: ExtensionTabPresentation) -> Bool {
        presentation == .regular || supportsCompact
    }

    func tabController(id: String, context: ExtensionTabLayoutContext) -> NSViewController? {
        let controller = NSViewController()
        controller.view = NSTextField(labelWithString: "\(providerID)/\(id)")
        // Content cannot enlarge the fixed host even with an excessive preferred size.
        controller.preferredContentSize = NSSize(width: 10_000, height: 10_000)
        audit.records.append(.init(id: .init(providerID: providerID, localID: id),
                                   context: context, controller: controller))
        return controller
    }
}

@MainActor
private final class ScaleTabPanel: NSPanel, ExtensionTabInputHosting {
    let extensionTabInput = ExtensionTabInputScope()
    override var canBecomeKey: Bool { extensionTabInput.allowsKey(in: self) }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class ScaleTabFixture {
    static let providerCount = 125
    // Every provider uses the same local IDs in a deliberately unsorted order.
    static let localIDs = ["tab-7", "tab-2", "tab-5", "tab-0", "tab-6", "tab-1", "tab-4", "tab-3"]
    static let regularLocalIDs = ["tab-2", "tab-5", "tab-0", "tab-1", "tab-4", "tab-3"]
    static let compactLocalIDs = ["tab-7", "tab-5", "tab-6", "tab-4"]

    let registry = ExtensionTabRegistry()
    let audit = ScaleTabAudit()
    var sources: [ScaleTabSource] = []

    init() {
        sources = (0..<Self.providerCount).map {
            // 25 legacy renderers deliberately cannot honor compact declarations.
            ScaleTabSource(providerID: Self.providerID($0), supportsCompact: $0 % 5 != 0, audit: audit)
        }
    }

    static func providerID(_ index: Int) -> String { String(format: "scale.provider.%03d", index) }

    static func descriptors(provider: Int, revision: Int = 0) -> [ExtensionTabDescriptor] {
        localIDs.map { id in
            let presentations: [ExtensionTabPresentation]?
            switch id {
            case "tab-0", "tab-1": presentations = nil
            case "tab-2", "tab-3": presentations = [.regular]
            case "tab-4", "tab-5": presentations = [.regular, .compact]
            default: presentations = [.compact]
            }
            return .init(id: id, title: "Provider \(provider) \(id) revision \(revision)",
                         symbol: revision.isMultiple(of: 2) ? "square" : "circle", presentations: presentations)
        }
    }

    func registerAll(revision: Int = 0) {
        for index in (0..<Self.providerCount).reversed() {
            registry.replace(providerID: Self.providerID(index),
                             tabs: Self.descriptors(provider: index, revision: revision), source: sources[index])
        }
    }

    static func expectedIDs(presentation: ExtensionTabPresentation? = nil) -> [ExtensionTabID] {
        (0..<providerCount).flatMap { provider -> [ExtensionTabID] in
            let locals: [String]
            switch presentation {
            case .regular: locals = regularLocalIDs
            case .compact: locals = provider % 5 == 0 ? [] : compactLocalIDs
            case nil: locals = localIDs
            }
            return locals.map { .init(providerID: providerID(provider), localID: $0) }
        }
    }
}

@MainActor
final class ExtensionTabScaleTests: XCTestCase {
    func testThousandTabsKeepNamespacesOrderEligibilityAndLazyRegistration() {
        let fixture = ScaleTabFixture()
        let registrationMilliseconds = milliseconds { fixture.registerAll() }
        let registry = fixture.registry
        let allIDs = ScaleTabFixture.expectedIDs()
        let regularIDs = ScaleTabFixture.expectedIDs(presentation: .regular)
        let compactIDs = ScaleTabFixture.expectedIDs(presentation: .compact)
        XCTAssertEqual(registry.tabs.count, 1_000)
        XCTAssertEqual(Set(registry.tabs.map(\.id)).count, 1_000, "Local IDs from different providers must never alias")
        XCTAssertEqual(registry.tabs.map(\.id), allIDs)
        XCTAssertEqual(registry.tabs(for: .regular).map(\.id), regularIDs)
        XCTAssertEqual(registry.tabs(for: .compact).map(\.id), compactIDs)
        XCTAssertEqual(regularIDs.count, 750)
        XCTAssertEqual(compactIDs.count, 400)

        for presentation in [ExtensionTabPresentation.regular, .compact] {
            let eligible = Set(presentation == .regular ? regularIDs : compactIDs)
            for id in allIDs {
                XCTAssertEqual(registry.tab(for: id, presentation: presentation)?.id, eligible.contains(id) ? id : nil)
            }
            XCTAssertNil(registry.tab(for: .init(providerID: "missing", localID: "tab-0"), presentation: presentation))
            XCTAssertNil(registry.tab(for: .init(providerID: ScaleTabFixture.providerID(0), localID: "missing"),
                                      presentation: presentation))
        }

        var filteredCount = 0
        let filterMilliseconds = milliseconds {
            for _ in 0..<100 {
                filteredCount += registry.tabs(for: .regular).count
                filteredCount += registry.tabs(for: .compact).count
            }
        }
        XCTAssertEqual(filteredCount, 115_000)
        var lookupHits = 0
        let lookupMilliseconds = milliseconds {
            for _ in 0..<20 {
                for id in allIDs {
                    if registry.tab(for: id, presentation: .regular) != nil { lookupHits += 1 }
                    if registry.tab(for: id, presentation: .compact) != nil { lookupHits += 1 }
                }
            }
        }
        XCTAssertEqual(lookupHits, 23_000)
        XCTAssertTrue(fixture.audit.records.isEmpty, "Registration, filtering, and lookup must never create native content")
        print(String(format: "[ExtensionTabScale] providers=125 tabs=1000 regular=750 compact=400 registration_ms=%.3f filters_200_ms=%.3f lookups_40000_ms=%.3f",
                     registrationMilliseconds, filterMilliseconds, lookupMilliseconds))
    }

    func testThousandTabMetadataChurnPreservesContentIdentityAndSuppressesIdenticalPublications() {
        let fixture = ScaleTabFixture()
        fixture.registerAll()
        let registry = fixture.registry
        let context = ExtensionTabLayoutContext(presentation: .regular, displayID: "scale-display",
                                                contentSize: CGSize(width: 578, height: 132))
        let identities = registry.tabs.map { $0.contentIdentity(context: context) }
        XCTAssertTrue(registry.tabs.allSatisfy { $0.systemSymbol == "square" })
        var publications = 0
        let observer = registry.$tabs.sink { _ in publications += 1 }
        defer { observer.cancel() }
        fixture.registerAll()
        XCTAssertEqual(publications, 1, "Replaying every identical provider snapshot must not publish")
        let metadataMilliseconds = milliseconds {
            for revision in 1...5 { fixture.registerAll(revision: revision) }
        }
        XCTAssertEqual(publications, 626, "Each of 625 changed provider snapshots publishes exactly once")
        XCTAssertEqual(registry.tabs.count, 1_000)
        XCTAssertEqual(registry.tabs.map { $0.contentIdentity(context: context) }, identities)
        XCTAssertTrue(registry.tabs.allSatisfy { $0.descriptor.title.hasSuffix("revision 5") })
        XCTAssertTrue(registry.tabs.allSatisfy { $0.systemSymbol == "circle" }, "A new snapshot must refresh its resolved symbol")
        fixture.registerAll(revision: 5)
        XCTAssertEqual(publications, 626)
        XCTAssertEqual(registry.tabs(for: .regular).count, 750)
        XCTAssertEqual(registry.tabs(for: .compact).count, 400)
        let invalidSymbols = ScaleTabFixture.descriptors(provider: 124, revision: 6).map {
            ExtensionTabDescriptor(id: $0.id, title: $0.title, symbol: "not-a-real-sf-symbol", presentations: $0.presentations)
        }
        registry.replace(providerID: ScaleTabFixture.providerID(124), tabs: invalidSymbols, source: fixture.sources[124])
        XCTAssertEqual(publications, 627)
        XCTAssertTrue(registry.tabs.suffix(8).allSatisfy { $0.systemSymbol == "puzzlepiece.extension" })
        XCTAssertEqual(registry.tabs.map { $0.contentIdentity(context: context) }, identities,
                       "Symbol validation or fallback must not replace mounted content identity")
        XCTAssertTrue(fixture.audit.records.isEmpty, "5,000 metadata changes must not instantiate hidden views")
        print(String(format: "[ExtensionTabScale] metadata_provider_updates=625 metadata_tab_updates=5000 metadata_ms=%.3f",
                     metadataMilliseconds))
    }

    func testRemovalAtScalePreservesSelectionUntilItsProviderDisappears() throws {
        let fixture = ScaleTabFixture()
        fixture.registerAll()
        let registry = fixture.registry
        let selectedID = ExtensionTabID(providerID: ScaleTabFixture.providerID(124), localID: "tab-7")
        let selected = NotchViews.extensionTab(selectedID)
        let regularSelection = NotchViews.extensionTab(.init(providerID: ScaleTabFixture.providerID(124), localID: "tab-0"))
        let initialCompactIDs = Set(registry.tabs(for: .compact).map(\.id))
        XCTAssertEqual(selected.reconciled(availableExtensionTabs: initialCompactIDs), selected)
        XCTAssertEqual(regularSelection.reconciled(availableExtensionTabs: initialCompactIDs), .home)
        XCTAssertEqual(selected.reconciled(availableExtensionTabs: Set(registry.tabs(for: .regular).map(\.id))), .home)

        let removedSource = ScaleWeakReference(fixture.sources.first)
        let selectedSource = ScaleWeakReference(fixture.sources.last)
        fixture.sources.removeAll()
        XCTAssertNotNil(removedSource.value, "Published metadata retains its provider without constructing content")
        XCTAssertNotNil(selectedSource.value)
        for provider in 0..<124 {
            registry.remove(providerID: ScaleTabFixture.providerID(provider))
            let available = Set(registry.tabs(for: .compact).map(\.id))
            XCTAssertEqual(selected.reconciled(availableExtensionTabs: available), selected)
            XCTAssertEqual(NotchViews.home.reconciled(availableExtensionTabs: available), .home)
            XCTAssertEqual(NotchViews.shelf.reconciled(availableExtensionTabs: available), .shelf)
            XCTAssertEqual(registry.tabs.count, (124 - provider) * 8)
        }
        XCTAssertNil(removedSource.value)
        XCTAssertNotNil(selectedSource.value)
        XCTAssertEqual(registry.tabs(for: .compact).count, 4)
        registry.remove(providerID: ScaleTabFixture.providerID(124))
        XCTAssertTrue(registry.tabs.isEmpty)
        XCTAssertNil(selectedSource.value, "An unmounted removed provider must not be retained")
        XCTAssertNil(registry.tab(for: selectedID, presentation: .compact))
        XCTAssertEqual(selected.reconciled(availableExtensionTabs: Set(registry.tabs.map(\.id))), .home)
        XCTAssertTrue(fixture.audit.records.isEmpty)
    }

    func testSelectingFourHundredCompactTabsMountsOnlySelectedContentAndReleasesRetiredControllers() throws {
        _ = NSApplication.shared
        let previousKeyWindow = NSApp.keyWindow
        let fixture = ScaleTabFixture()
        fixture.registerAll()
        let registry = fixture.registry
        let eligibleIDs = registry.tabs(for: .compact).map(\.id)
        XCTAssertEqual(eligibleIDs.count, 400)
        XCTAssertTrue(fixture.audit.records.isEmpty)
        let size = CGSize(width: 336, height: 132)
        let displayID = "scale-display"
        let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
        let panel = ScaleTabPanel(contentRect: NSRect(origin: CGPoint(x: -10_000, y: -10_000), size: size),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.contentView = hostingView
        // This offscreen test panel is never ordered front or made key.
        defer { panel.contentView = nil; panel.close() }
        let start = DispatchTime.now().uptimeNanoseconds
        for (index, id) in eligibleIDs.enumerated() {
            hostingView.rootView = AnyView(ExtensionTabContent(id: id, displayID: displayID,
                                                              presentation: .compact, registry: registry)
                .frame(width: size.width, height: size.height))
            guard settle(hostingView, until: {
                fixture.audit.records.count == index + 1
                    && fixture.audit.liveControllerCount == 1
                    && fixture.audit.records.last?.view?.window === panel
            }) else {
                XCTFail("Selection \(index) failed to leave exactly its selected controller mounted; requests=\(fixture.audit.records.count), live=\(fixture.audit.liveControllerCount)")
                return
            }
            let record = try XCTUnwrap(fixture.audit.records.last)
            XCTAssertEqual(record.id, id)
            XCTAssertEqual(record.context, .init(presentation: .compact, displayID: displayID, contentSize: size))
            XCTAssertEqual(record.view?.bounds.size, size, "All 400 selected tabs must remain within the same compact bounds")
            XCTAssertTrue(panel.canBecomeKey)
        }
        let selectionMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        XCTAssertEqual(fixture.audit.records.count, 400)
        XCTAssertTrue(fixture.audit.records.dropLast().allSatisfy { $0.controller == nil && $0.view == nil })
        let selectedRecord = try XCTUnwrap(fixture.audit.records.last)
        fixture.registerAll(revision: 1)
        XCTAssertTrue(settle(hostingView, until: { fixture.audit.records.last?.controller === selectedRecord.controller }))
        XCTAssertEqual(fixture.audit.records.count, 400, "Updating all 1,000 titles must preserve the selected controller")
        XCTAssertEqual(fixture.audit.liveControllerCount, 1)
        XCTAssertNotNil(selectedRecord.controller)

        let selectedID = try XCTUnwrap(eligibleIDs.last)
        registry.remove(providerID: selectedID.providerID)
        XCTAssertTrue(settle(hostingView, until: { fixture.audit.liveControllerCount == 0 && !panel.canBecomeKey }))
        XCTAssertNil(selectedRecord.controller)
        XCTAssertTrue(fixture.audit.records.allSatisfy { $0.view == nil })
        XCTAssertFalse(panel.isKeyWindow)
        XCTAssertTrue(NSApp.keyWindow === previousKeyWindow, "Selecting or removing tabs must not steal focus")
        XCTAssertEqual(registry.tabs.count, 992)
        print(String(format: "[ExtensionTabScale] native_selected_tabs=400 created=400 live_after_removal=0 selection_ms=%.3f",
                     selectionMilliseconds))
    }

    private func milliseconds(_ action: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        action()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    /// Pump AppKit until a lifecycle condition is observable; the timeout only
    /// bounds a broken test and is not a performance expectation.
    private func settle(_ view: NSView, until condition: () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: 2)
        repeat {
            autoreleasepool {
                view.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
                view.layoutSubtreeIfNeeded()
            }
            if condition() { return true }
        } while Date() < deadline
        return false
    }
}
