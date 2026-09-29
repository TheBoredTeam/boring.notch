// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Combine
import SwiftUI
import XCTest
@testable import boringNotch

@MainActor
private final class TabSource: ExtensionTabControllerSource {
    struct Request: Equatable { let id: String; let displayID: String? }
    var requests: [Request] = []
    var controllers: [NSViewController] = []

    func tabController(id: String, displayID: String?) -> NSViewController? {
        requests.append(Request(id: id, displayID: displayID))
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

    func tabController(id: String, displayID: String?) -> NSViewController? {
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
    private func descriptor(_ id: String = "tasks", title: String = "Tasks", symbol: String = "checklist") -> ExtensionTabDescriptor {
        .init(id: id, title: title, symbol: symbol)
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
        let initial = try XCTUnwrap(registry.tabs.first).contentIdentity(displayID: "display")
        registry.replace(providerID: "example", tabs: [descriptor()], source: source)
        XCTAssertEqual(publications, 2) // Initial empty state and registration.
        registry.replace(providerID: "example", tabs: [descriptor(title: "Running", symbol: "play.fill")], source: source)
        XCTAssertEqual(publications, 3)
        XCTAssertEqual(registry.tabs.first?.descriptor.title, "Running")
        XCTAssertEqual(registry.tabs.first?.contentIdentity(displayID: "display"), initial)
        registry.replace(providerID: "example", tabs: [descriptor()], source: TabSource())
        XCTAssertNotEqual(registry.tabs.first?.contentIdentity(displayID: "display"), initial)
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
        let first = try XCTUnwrap(tab.makeController(displayID: "display-a"))
        let second = try XCTUnwrap(tab.makeController(displayID: "display-b"))
        let third = try XCTUnwrap(tab.makeController(displayID: "display-a"))
        XCTAssertFalse(first === second)
        XCTAssertFalse(first === third)
        XCTAssertEqual(source.requests.map(\.displayID), ["display-a", "display-b", "display-a"])
        XCTAssertEqual(source.requests.map(\.id), ["tasks", "tasks", "tasks"])
        XCTAssertNotEqual(tab.contentIdentity(displayID: "display-a"), tab.contentIdentity(displayID: "display-b"))
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
