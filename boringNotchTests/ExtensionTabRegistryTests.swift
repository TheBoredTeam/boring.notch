// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

import AppKit
import Combine
import SwiftUI
import XCTest
@testable import boringNotch

@MainActor
private final class TabSource: ExtensionTabControllerSource {
    struct Request: Equatable {
        let id: String
        let context: ExtensionTabLayoutContext
        var displayID: String? { context.displayID }
    }
    var presentations: Set<ExtensionTabPresentation> = [.regular]
    var requests: [Request] = []
    var controllers: [NSViewController] = []

    func supportsTabPresentation(_ presentation: ExtensionTabPresentation) -> Bool { presentations.contains(presentation) }

    func tabController(id: String, context: ExtensionTabLayoutContext) -> NSViewController? {
        requests.append(Request(id: id, context: context))
        let controller = NSViewController()
        controller.view = NSTextField(labelWithString: "Live content")
        controller.preferredContentSize = NSSize(width: 10_000, height: 10_000)
        controllers.append(controller)
        return controller
    }
}

@MainActor
private final class InputTabPanel: NSPanel, ExtensionTabInputHosting {
    let extensionTabInput = ExtensionTabInputScope()
    override var canBecomeKey: Bool { extensionTabInput.allowsKey(in: self) }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class InputTabSource: ExtensionTabControllerSource {
    var field: NSTextField?

    func tabController(id: String, context: ExtensionTabLayoutContext) -> NSViewController? {
        let controller = NSViewController()
        let field = NSTextField(string: "Draft")
        field.frame = NSRect(x: 8, y: 8, width: 240, height: 24)
        controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 128))
        controller.view.addSubview(field)
        self.field = field
        return controller
    }
}

@MainActor
final class ExtensionTabRegistryTests: XCTestCase {
    func testPublisherIconCachingFallbackAndContentIdentity() throws {
        let registry = ExtensionTabRegistry()
        let source = TabSource()
        let png = try TabIconFixture.png()
        let value = ExtensionTabDescriptor(id: "tasks", title: "Tasks", symbol: "square", iconPNG: png)
        registry.replace(providerID: "example", tabs: [value], source: source)
        let initial = try XCTUnwrap(registry.tabs.first)
        let image = try XCTUnwrap(initial.iconImage)
        let identity = initial.contentIdentity(context: context())
        for _ in 0..<100 { registry.replace(providerID: "example", tabs: [value], source: source) }
        XCTAssertTrue(registry.tabs.first?.iconImage === image, "Repeated metadata must not decode another image")
        registry.replace(providerID: "example", tabs: [
            .init(id: "tasks", title: "Renamed", symbol: "circle", iconPNG: png)
        ], source: source)
        XCTAssertTrue(registry.tabs.first?.iconImage === image, "Title and symbol changes reuse the static image")
        XCTAssertEqual(registry.tabs.first?.contentIdentity(context: context()), identity)
        registry.replace(providerID: "example", tabs: [
            .init(id: "tasks", title: "Tasks", symbol: "circle", iconPNG: try TabIconFixture.png(alpha: 0.5))
        ], source: source)
        XCTAssertNotNil(registry.tabs.first?.iconImage)
        XCTAssertFalse(registry.tabs.first?.iconImage === image)
        XCTAssertEqual(registry.tabs.first?.contentIdentity(context: context()), identity, "Icon changes do not remount content")
        registry.replace(providerID: "example", tabs: [
            .init(id: "tasks", title: "Tasks", symbol: "circle", iconPNG: "invalid")
        ], source: source)
        XCTAssertEqual(registry.tabs.count, 1)
        XCTAssertNil(registry.tabs.first?.iconImage)
        XCTAssertEqual(registry.tabs.first?.systemSymbol, "circle")
        XCTAssertEqual(registry.tabs.first?.contentIdentity(context: context()), identity)
        XCTAssertTrue(source.requests.isEmpty, "Icon registration cannot create controllers or take focus")
    }

    private func descriptor(_ id: String = "tasks", title: String = "Tasks", symbol: String = "checklist") -> ExtensionTabDescriptor {
        .init(id: id, title: title, symbol: symbol)
    }

    private func context(_ displayID: String? = "display", presentation: ExtensionTabPresentation = .regular,
                         size: CGSize = CGSize(width: 320, height: 128)) -> ExtensionTabLayoutContext {
        ExtensionTabLayoutContext(presentation: presentation, displayID: displayID, contentSize: size)
    }

    func testNamespacesAndDeterministicProviderOrder() throws {
        let registry = ExtensionTabRegistry()
        let source = TabSource()
        registry.replace(providerID: "z.example", tabs: [descriptor()], source: source)
        registry.replace(providerID: "a.example", tabs: [descriptor("second"), descriptor("first")], source: source)
        XCTAssertEqual(registry.tabs.map(\.id), [
            .init(providerID: "a.example", localID: "second"), .init(providerID: "a.example", localID: "first"),
            .init(providerID: "z.example", localID: "tasks")
        ])
        registry.replace(providerID: "a.example", tabs: [descriptor()], source: source)
        XCTAssertEqual(Set(registry.tabs.map(\.id)).count, 2)
        XCTAssertTrue(source.requests.isEmpty, "Registration must not create content or steal focus")
    }

    func testIdenticalPublicationDoesNotChurnAndMetadataKeepsContentIdentity() throws {
        let registry = ExtensionTabRegistry()
        let source = TabSource()
        var publications = 0
        let observer = registry.$tabs.sink { _ in publications += 1 }
        defer { observer.cancel() }
        registry.replace(providerID: "example", tabs: [descriptor()], source: source)
        let initial = try XCTUnwrap(registry.tabs.first).contentIdentity(context: context())
        registry.replace(providerID: "example", tabs: [descriptor()], source: source)
        XCTAssertEqual(publications, 2) // Initial empty state and registration.
        registry.replace(providerID: "example", tabs: [descriptor(title: "Running", symbol: "play.fill")], source: source)
        XCTAssertEqual(publications, 3)
        XCTAssertEqual(registry.tabs.first?.descriptor.title, "Running")
        XCTAssertEqual(registry.tabs.first?.contentIdentity(context: context()), initial)
        registry.replace(providerID: "example", tabs: [descriptor()], source: TabSource())
        XCTAssertNotEqual(registry.tabs.first?.contentIdentity(context: context()), initial)
    }

    func testSelectionOnlyFallsBackWhenSelectedTabIsRemoved() throws {
        let registry = ExtensionTabRegistry()
        let source = TabSource()
        registry.replace(providerID: "example", tabs: [descriptor()], source: source)
        let selected = NotchViews.extensionTab(try XCTUnwrap(registry.tabs.first).id)
        var available = Set(registry.tabs.map(\.id))
        XCTAssertEqual(NotchViews.home.reconciled(availableExtensionTabs: available), .home)
        XCTAssertEqual(NotchViews.shelf.reconciled(availableExtensionTabs: available), .shelf)
        XCTAssertEqual(selected.reconciled(availableExtensionTabs: available), selected)
        registry.replace(providerID: "other", tabs: [descriptor()], source: source)
        registry.remove(providerID: "other")
        available = Set(registry.tabs.map(\.id))
        XCTAssertEqual(selected.reconciled(availableExtensionTabs: available), selected)
        registry.remove(providerID: "example")
        XCTAssertEqual(selected.reconciled(availableExtensionTabs: Set(registry.tabs.map(\.id))), .home)
    }

    func testReplacementRemovalAndInvalidPublicationReleaseRegistryOwnership() {
        let registry = ExtensionTabRegistry()
        weak var weakSource: TabSource?
        do {
            let source = TabSource()
            weakSource = source
            registry.replace(providerID: "example", tabs: [descriptor()], source: source)
        }
        XCTAssertNotNil(weakSource)
        let replacement = TabSource()
        registry.replace(providerID: "example", tabs: [descriptor()], source: replacement)
        XCTAssertNil(weakSource)
        registry.replace(providerID: "example", tabs: [descriptor(), descriptor()], source: replacement)
        XCTAssertTrue(registry.tabs.isEmpty)
        registry.replace(providerID: "example", tabs: [descriptor()], source: replacement)
        registry.replace(providerID: "example", tabs: [], source: replacement)
        XCTAssertNil(registry.tab(for: .init(providerID: "example", localID: "tasks")))
    }

    func testEachMountRequestsAnIndependentDisplayController() throws {
        let registry = ExtensionTabRegistry()
        let source = TabSource()
        registry.replace(providerID: "example", tabs: [descriptor()], source: source)
        let tab = try XCTUnwrap(registry.tabs.first)
        let first = try XCTUnwrap(tab.makeController(context: context("display-a")))
        let second = try XCTUnwrap(tab.makeController(context: context("display-b")))
        let third = try XCTUnwrap(tab.makeController(context: context("display-a")))
        XCTAssertFalse(first === second)
        XCTAssertFalse(first === third)
        XCTAssertEqual(source.requests.map(\.displayID), ["display-a", "display-b", "display-a"])
        XCTAssertEqual(source.requests.map(\.id), ["tasks", "tasks", "tasks"])
        XCTAssertNotEqual(tab.contentIdentity(context: context("display-a")), tab.contentIdentity(context: context("display-b")))
    }

    func testRegistryRequiresDeclarationAndRendererSupportForCompact() throws {
        let registry = ExtensionTabRegistry()
        let legacy = TabSource()
        let modern = TabSource()
        modern.presentations = [.regular, .compact]
        let both = ExtensionTabDescriptor(id: "both", title: "Both", symbol: "square", presentations: [.regular, .compact])
        let compact = ExtensionTabDescriptor(id: "compact", title: "Compact", symbol: "square", presentations: [.compact])
        registry.replace(providerID: "legacy", tabs: [descriptor(), both], source: legacy)
        registry.replace(providerID: "modern", tabs: [descriptor(), both, compact], source: modern)
        XCTAssertEqual(registry.tabs(for: .compact).map(\.id), [
            .init(providerID: "modern", localID: "both"), .init(providerID: "modern", localID: "compact")
        ])
        XCTAssertEqual(registry.tabs(for: .regular).count, 4)
        XCTAssertNil(registry.tab(for: .init(providerID: "legacy", localID: "both"), presentation: .compact))
        XCTAssertNil(registry.tab(for: .init(providerID: "modern", localID: "compact"), presentation: .regular))
        let legacyTab = try XCTUnwrap(registry.tab(for: .init(providerID: "legacy", localID: "both")))
        XCTAssertNil(legacyTab.makeController(context: context(presentation: .compact)))
        XCTAssertTrue(legacy.requests.isEmpty, "A compact request must never invoke a legacy renderer")
        let modernTab = try XCTUnwrap(registry.tab(for: .init(providerID: "modern", localID: "both"), presentation: .compact))
        XCTAssertNil(modernTab.makeController(context: context(presentation: .compact, size: .zero)))
        XCTAssertNil(modernTab.makeController(context: context(presentation: .compact, size: CGSize(width: 337, height: 132))))
        XCTAssertNil(modernTab.makeController(context: context(presentation: .compact, size: CGSize(width: 336, height: 133))))
        XCTAssertTrue(modern.requests.isEmpty, "Invalid geometry must never reach extension code")
        XCTAssertNotNil(modernTab.makeController(context: context(presentation: .compact, size: CGSize(width: 336, height: 132))))
        XCTAssertEqual(modern.requests.last?.context.contentSize.width, 336)
        XCTAssertNotEqual(modernTab.contentIdentity(context: context()),
                          modernTab.contentIdentity(context: context(presentation: .compact)))
        XCTAssertNotEqual(modernTab.contentIdentity(context: context()),
                          modernTab.contentIdentity(context: context(size: CGSize(width: 321, height: 128))))
    }

    func testNativePresentationAndBoundsRemountWithoutMetadataChurn() throws {
        _ = NSApplication.shared
        let registry = ExtensionTabRegistry()
        let source = TabSource()
        source.presentations = [.regular, .compact]
        let value = ExtensionTabDescriptor(id: "tasks", title: "Tasks", symbol: "checklist", presentations: [.regular, .compact])
        registry.replace(providerID: "example", tabs: [value], source: source)
        let id = try XCTUnwrap(registry.tabs.first).id
        let hostingView = NSHostingView(rootView:
            ExtensionTabContent(id: id, displayID: "display", presentation: .regular, registry: registry)
                .frame(width: 578, height: 132))
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 578, height: 132),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        defer { window.contentView = nil; window.close() }
        settle(hostingView)
        XCTAssertEqual(source.requests.map(\.context), [context(size: CGSize(width: 578, height: 132))])
        let original = try XCTUnwrap(source.controllers.first)
        registry.replace(providerID: "example", tabs: [
            .init(id: "tasks", title: "Renamed", symbol: "play", presentations: [.regular, .compact])
        ], source: source)
        settle(hostingView)
        XCTAssertEqual(source.requests.count, 1)
        hostingView.rootView = ExtensionTabContent(id: id, displayID: "display", presentation: .compact, registry: registry)
            .frame(width: 336, height: 132)
        window.setContentSize(NSSize(width: 336, height: 132))
        settle(hostingView)
        XCTAssertEqual(source.requests.count, 2)
        XCTAssertEqual(source.requests.last?.context, context(presentation: .compact, size: CGSize(width: 336, height: 132)))
        XCTAssertNil(original.view.window)
        let compact = try XCTUnwrap(source.controllers.last)
        XCTAssertEqual(compact.view.bounds.size, CGSize(width: 336, height: 132))
        hostingView.rootView = ExtensionTabContent(id: id, displayID: "display", presentation: .compact, registry: registry)
            .frame(width: 300, height: 116)
        window.setContentSize(NSSize(width: 300, height: 116))
        settle(hostingView)
        XCTAssertEqual(source.requests.count, 3)
        XCTAssertEqual(source.requests.last?.context, context(presentation: .compact, size: CGSize(width: 300, height: 116)))
        XCTAssertNil(compact.view.window)
    }

    func testUnsupportedCompactNativeMountDoesNotCreateContentOrPermitInput() throws {
        _ = NSApplication.shared
        let registry = ExtensionTabRegistry()
        let source = TabSource()
        registry.replace(providerID: "example", tabs: [descriptor()], source: source)
        let id = try XCTUnwrap(registry.tabs.first).id
        let hostingView = NSHostingView(rootView:
            ExtensionTabContent(id: id, displayID: "display", presentation: .compact, registry: registry)
                .frame(width: 336, height: 132))
        let panel = InputTabPanel(contentRect: NSRect(x: -10_000, y: -10_000, width: 336, height: 132),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.contentView = hostingView
        defer { panel.contentView = nil; panel.close() }
        settle(hostingView)
        XCTAssertTrue(source.requests.isEmpty)
        XCTAssertFalse(panel.canBecomeKey)
    }

    func testNativeMountKeepsControllerForMetadataAndLiveContentUpdates() throws {
        _ = NSApplication.shared
        let registry = ExtensionTabRegistry()
        let source = TabSource()
        registry.replace(providerID: "example", tabs: [descriptor()], source: source)
        let id = try XCTUnwrap(registry.tabs.first).id
        let content = ExtensionTabContent(id: id, displayID: "display", registry: registry).frame(width: 320, height: 128)
        let hostingView = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 320, height: 128),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.orderBack(nil)
        defer { window.orderOut(nil); window.close() }
        settle(hostingView)
        XCTAssertEqual(source.controllers.count, 1)
        let controller = try XCTUnwrap(source.controllers.first)
        XCTAssertEqual(controller.view.bounds.width, 320, accuracy: 1)
        XCTAssertEqual(controller.view.bounds.height, 128, accuracy: 1)
        let text = try XCTUnwrap(controller.view as? NSTextField)
        text.stringValue = "Updated without publication"
        registry.replace(providerID: "example", tabs: [descriptor(title: "Now running", symbol: "play.fill")], source: source)
        settle(hostingView)
        XCTAssertEqual(source.controllers.count, 1)
        XCTAssertEqual(text.stringValue, "Updated without publication")
        XCTAssertTrue(controller.view.window === window)
        let replacement = TabSource()
        registry.replace(providerID: "example", tabs: [descriptor()], source: replacement)
        settle(hostingView)
        XCTAssertEqual(replacement.controllers.count, 1)
        XCTAssertNil(controller.view.window)
        registry.remove(providerID: "example")
        settle(hostingView)
        XCTAssertNil(replacement.controllers.first?.view.window)
    }

    func testNativeInputMountAllowsTextEditingWithoutTakingFocusAndRevokesOnRemoval() throws {
        _ = NSApplication.shared
        let previousKeyWindow = NSApp.keyWindow
        let registry = ExtensionTabRegistry()
        let source = InputTabSource()
        registry.replace(providerID: "example", tabs: [descriptor()], source: source)
        let id = try XCTUnwrap(registry.tabs.first).id
        let panel = InputTabPanel(contentRect: NSRect(x: -10_000, y: -10_000, width: 320, height: 128),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        let previousKeyOnlyIfNeeded = panel.becomesKeyOnlyIfNeeded
        XCTAssertFalse(panel.canBecomeKey)
        let hostingView = NSHostingView(rootView:
            ExtensionTabContent(id: id, displayID: "display", registry: registry).frame(width: 320, height: 128))
        panel.contentView = hostingView
        defer { panel.contentView = nil; panel.close() }
        settle(hostingView)
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertTrue(panel.becomesKeyOnlyIfNeeded)
        XCTAssertFalse(panel.isKeyWindow, "Mounting a tab must never take keyboard focus")
        XCTAssertTrue(NSApp.keyWindow === previousKeyWindow)

        let field = try XCTUnwrap(source.field)
        XCTAssertTrue(field.window === panel)
        XCTAssertTrue(panel.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.insertText(" edited", replacementRange: NSRange(location: editor.string.utf16.count, length: 0))
        XCTAssertEqual(editor.string, "Draft edited")
        registry.replace(providerID: "example", tabs: [descriptor(title: "Renamed")], source: source)
        settle(hostingView)
        XCTAssertTrue(field.currentEditor() === editor)
        XCTAssertEqual(editor.string, "Draft edited")

        registry.remove(providerID: "example")
        settle(hostingView)
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertEqual(panel.becomesKeyOnlyIfNeeded, previousKeyOnlyIfNeeded)
        XCTAssertNil(field.window)
        XCTAssertFalse(panel.firstResponder === editor)
        XCTAssertTrue(NSApp.keyWindow === previousKeyWindow)
    }

    func testInputScopeRejectsLateUnmountAndCannotOutliveItsView() {
        _ = NSApplication.shared
        let panel = InputTabPanel(contentRect: NSRect(x: -10_000, y: -10_000, width: 320, height: 128),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        let root = NSView(frame: panel.contentLayoutRect)
        let old = NSView(frame: root.bounds)
        let replacement = NSView(frame: root.bounds)
        panel.contentView = root
        root.addSubview(old)
        root.addSubview(replacement)
        panel.extensionTabInput.mount(old, in: panel)
        panel.extensionTabInput.mount(replacement, in: panel)
        panel.extensionTabInput.unmount(old)
        XCTAssertTrue(panel.canBecomeKey, "A retired mount cannot revoke its replacement")
        replacement.removeFromSuperview()
        XCTAssertFalse(panel.canBecomeKey, "Detached content cannot retain keyboard eligibility")
        panel.extensionTabInput.unmount(replacement)
        XCTAssertFalse(panel.becomesKeyOnlyIfNeeded)
    }

    private func settle(_ view: NSView) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        view.layoutSubtreeIfNeeded()
    }
}
