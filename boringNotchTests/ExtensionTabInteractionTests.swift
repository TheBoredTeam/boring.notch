// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

import AppKit
import Combine
import SwiftUI
import XCTest
@testable import boringNotch

@MainActor
private final class InteractionPanel: NSPanel, ExtensionTabInputHosting {
    let extensionTabInput = ExtensionTabInputScope()
    var simulatedKey: Bool?
    override var isKeyWindow: Bool { simulatedKey ?? super.isKeyWindow }
    override var canBecomeKey: Bool { extensionTabInput.allowsKey(in: self) }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class KeyboardNavigationTable: NSTableView {
    override var acceptsFirstResponder: Bool { isEnabled }
    override var needsPanelToBecomeKey: Bool { isEnabled }
}

@MainActor
private final class NavigationRows: NSObject, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { 3 }
}

@MainActor
private final class FocusableButton: NSButton {
    override var acceptsFirstResponder: Bool { true }
}

@MainActor
private final class PopoverModel: ObservableObject {
    @Published var isPresented = false
    @Published var draft = ""
}

private struct IndependentPopoverView: View {
    @ObservedObject var model: PopoverModel

    var body: some View {
        Button("Compose") { model.isPresented = true }
            .popover(isPresented: $model.isPresented) {
                TextField("Message", text: $model.draft).padding().frame(width: 220)
            }
            .frame(width: 320, height: 128)
    }
}

@MainActor
private final class PopoverSource: ExtensionTabControllerSource {
    let model = PopoverModel()
    var requests = 0

    func tabController(id: String, context: ExtensionTabLayoutContext) -> NSViewController? {
        requests += 1
        return NSHostingController(rootView: IndependentPopoverView(model: model))
    }
}

@MainActor
final class ExtensionTabInteractionTests: XCTestCase {
    func testRealNativePopoverHoldsOnlyItsAnchorAndSignalsDismissal() throws {
        _ = NSApplication.shared
        let panel = makePanel()
        defer { panel.contentView = nil; panel.close() }
        let owner = try XCTUnwrap(panel.contentView)
        let scope = panel.extensionTabInput
        let previousKey = NSApp.keyWindow
        scope.mount(owner, in: panel)
        XCTAssertTrue(scope.allowsKey(in: panel))
        XCTAssertFalse(scope.keepsNotchOpen, "Mounting does not create an interaction hold")
        XCTAssertTrue(NSApp.keyWindow === previousKey, "Mounting never takes keyboard focus")
        var changes: [Bool] = []
        let observer = scope.interactionChanges.sink { changes.append(scope.keepsNotchOpen) }
        defer { observer.cancel() }
        let popover = nativePopover()
        defer { popover.close() }
        popover.show(relativeTo: CGRect(x: 100, y: 50, width: 30, height: 20), of: owner, preferredEdge: .maxY)
        XCTAssertTrue(settle { popover.isShown && scope.keepsNotchOpen && changes.last == true })
        XCTAssertTrue(popover.contentViewController?.view.window?.parent === panel,
                      "AppKit associates a native popover with its positioning window")
        popover.close()
        XCTAssertTrue(settle { !scope.keepsNotchOpen && changes.last == false })
        XCTAssertEqual(changes, [true, false], "Dismissal must schedule a fresh hover-close decision without polling")
        scope.unmount(owner)
        XCTAssertFalse(scope.allowsKey(in: panel))
    }

    func testIndependentSwiftUIPopoverAcceptsNativeTypingAndClosesWhenItsTabUnmounts() throws {
        _ = NSApplication.shared
        let registry = ExtensionTabRegistry()
        let source = PopoverSource()
        registry.replace(providerID: "independent", tabs: [.init(id: "compose", title: "Compose", symbol: "pencil")], source: source)
        let id = ExtensionTabID(providerID: "independent", localID: "compose")
        let panel = makePanel()
        panel.contentView = NSHostingView(rootView: ExtensionTabContent(id: id, displayID: "test", registry: registry)
            .frame(width: 320, height: 128))
        defer { panel.contentView = nil; panel.close() }
        XCTAssertTrue(settle { source.requests == 1 && panel.extensionTabInput.allowsKey(in: panel) })
        XCTAssertFalse(panel.extensionTabInput.keepsNotchOpen)
        source.model.isPresented = true
        XCTAssertTrue(settle { panel.extensionTabInput.keepsNotchOpen })
        let children = panel.childWindows ?? []
        XCTAssertFalse(children.isEmpty, "The independent SwiftUI popover must create a real owned window")
        XCTAssertTrue(children.contains(where: \.isVisible))
        let popoverWindow = try XCTUnwrap(children.first(where: \.isVisible))
        let field = try XCTUnwrap(popoverWindow.contentView.flatMap(editableField))
        XCTAssertTrue(popoverWindow.makeFirstResponder(field))
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: popoverWindow.windowNumber,
            context: nil, characters: "4", charactersIgnoringModifiers: "4", isARepeat: false, keyCode: 21))
        // Route through the real popover window's responder chain without
        // activating the test process or sending input to the user's app.
        popoverWindow.sendEvent(event)
        XCTAssertTrue(settle { source.model.draft == "4" })
        XCTAssertTrue(source.model.isPresented)
        XCTAssertTrue(panel.extensionTabInput.keepsNotchOpen)
        XCTAssertEqual(source.requests, 1, "Typing must preserve the mounted controller")
        registry.remove(providerID: "independent")
        XCTAssertTrue(settle {
            !panel.extensionTabInput.allowsKey(in: panel)
                && !panel.extensionTabInput.keepsNotchOpen
                && !children.contains(where: \.isVisible)
        })
        XCTAssertEqual(source.requests, 1)
    }

    func testPreexistingAndOtherWindowChildrenDoNotHoldTheMountedTab() throws {
        _ = NSApplication.shared
        let panel = makePanel()
        let otherPanel = makePanel()
        let preexisting = makeChild()
        let unrelated = makeChild()
        let owned = makeChild()
        defer {
            [preexisting, unrelated, owned].forEach { $0.close() }
            panel.contentView = nil; panel.close()
            otherPanel.contentView = nil; otherPanel.close()
        }
        panel.addChildWindow(preexisting, ordered: .above)
        preexisting.orderBack(nil)
        otherPanel.addChildWindow(unrelated, ordered: .above)
        unrelated.orderBack(nil)
        let owner = try XCTUnwrap(panel.contentView)
        panel.extensionTabInput.mount(owner, in: panel)
        XCTAssertFalse(panel.extensionTabInput.keepsNotchOpen)
        panel.addChildWindow(owned, ordered: .above)
        owned.orderBack(nil)
        XCTAssertTrue(panel.extensionTabInput.keepsNotchOpen)
        owned.orderOut(nil)
        XCTAssertFalse(panel.extensionTabInput.keepsNotchOpen, "An invisible child is no longer an interaction")
        panel.addChildWindow(owned, ordered: .above)
        owned.orderBack(nil)
        XCTAssertTrue(panel.extensionTabInput.keepsNotchOpen)
        panel.extensionTabInput.unmount(owner)
        XCTAssertFalse(owned.isVisible, "Owned transient windows cannot outlive their mounted tab")
        XCTAssertTrue(preexisting.isVisible, "A tab cannot dismiss an unrelated preexisting window")
        XCTAssertTrue(unrelated.isVisible)
        XCTAssertFalse(panel.extensionTabInput.keepsNotchOpen)
    }

    func testOnlyKeyTextInputInsideTheMountedViewHoldsTheNotch() throws {
        _ = NSApplication.shared
        let panel = makePanel()
        panel.simulatedKey = false
        defer { panel.contentView = nil; panel.close() }
        let root = try XCTUnwrap(panel.contentView)
        let owner = NSView(frame: CGRect(x: 0, y: 0, width: 180, height: 80))
        let field = NSTextField(string: "Draft")
        field.frame = CGRect(x: 5, y: 5, width: 160, height: 24)
        owner.addSubview(field)
        root.addSubview(owner)
        let outside = NSTextField(string: "Outside")
        outside.frame = CGRect(x: 190, y: 5, width: 120, height: 24)
        root.addSubview(outside)
        panel.extensionTabInput.mount(owner, in: panel)
        XCTAssertTrue(panel.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.insertText(" edited", replacementRange: NSRange(location: editor.string.utf16.count, length: 0))
        XCTAssertEqual(editor.string, "Draft edited")
        XCTAssertFalse(panel.extensionTabInput.keepsNotchOpen, "A field editor left behind in an inactive window is not a hold")
        panel.simulatedKey = true
        XCTAssertTrue(panel.extensionTabInput.keepsNotchOpen)
        XCTAssertTrue(panel.makeFirstResponder(outside))
        XCTAssertFalse(panel.extensionTabInput.keepsNotchOpen, "Another view's field editor does not belong to the tab")
        XCTAssertTrue(panel.makeFirstResponder(field))
        XCTAssertTrue(panel.extensionTabInput.keepsNotchOpen)
        panel.extensionTabInput.unmount(owner)
        XCTAssertFalse(panel.extensionTabInput.keepsNotchOpen)
        XCTAssertNil(field.currentEditor())
    }

    func testSearchToNativeKeyboardNavigationRetainsOnlyTheMountedInteraction() throws {
        _ = NSApplication.shared
        let panel = makePanel()
        panel.simulatedKey = false
        defer { panel.contentView = nil; panel.close() }
        let root = try XCTUnwrap(panel.contentView)
        let owner = NSView(frame: CGRect(x: 0, y: 0, width: 200, height: 128))
        root.addSubview(owner)
        let search = NSSearchField(frame: CGRect(x: 5, y: 100, width: 190, height: 22))
        owner.addSubview(search)
        let rows = NavigationRows()
        let table = KeyboardNavigationTable(frame: CGRect(x: 5, y: 25, width: 190, height: 66))
        table.addTableColumn(NSTableColumn(identifier: .init("result")))
        table.headerView = nil
        table.dataSource = rows
        owner.addSubview(table)
        table.reloadData()
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        let button = FocusableButton(frame: CGRect(x: 5, y: 0, width: 100, height: 22))
        owner.addSubview(button)
        let outside = KeyboardNavigationTable(frame: CGRect(x: 205, y: 25, width: 110, height: 66))
        root.addSubview(outside)
        let scope = panel.extensionTabInput
        let previousKey = NSApp.keyWindow
        scope.mount(owner, in: panel)
        XCTAssertFalse(scope.keepsNotchOpen)
        XCTAssertTrue(NSApp.keyWindow === previousKey, "Mounting does not acquire keyboard focus")
        var holds: [Bool] = []
        let observer = scope.interactionChanges.sink { holds.append(scope.keepsNotchOpen) }
        defer { observer.cancel() }
        panel.simulatedKey = true
        XCTAssertTrue(panel.makeFirstResponder(search))
        XCTAssertNotNil(search.currentEditor())
        XCTAssertTrue(settle { holds.last == true })
        XCTAssertTrue(panel.makeFirstResponder(table))
        XCTAssertTrue(panel.firstResponder === table)
        XCTAssertTrue(scope.keepsNotchOpen, "Leaving the search editor for result navigation must retain the hold")
        let down = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
            context: nil, characters: "\u{f701}", charactersIgnoringModifiers: "\u{f701}", isARepeat: false, keyCode: 125))
        table.keyDown(with: down)
        XCTAssertEqual(table.selectedRow, 1, "The focused native control receives navigation keys")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertEqual(holds, [true], "Responder transfer must not emit a release to the hover-close scheduler")
        XCTAssertTrue(panel.makeFirstResponder(button))
        XCTAssertFalse(scope.keepsNotchOpen, "A focusable button without panel keyboard intent does not hold")
        XCTAssertTrue(panel.makeFirstResponder(outside))
        XCTAssertFalse(scope.keepsNotchOpen, "Another subtree's navigation control cannot hold this tab")
        XCTAssertTrue(panel.makeFirstResponder(table))
        panel.simulatedKey = false
        XCTAssertFalse(scope.keepsNotchOpen, "An inactive window's last navigation responder does not hold")
        panel.simulatedKey = true
        table.isEnabled = false
        XCTAssertFalse(scope.keepsNotchOpen, "A disabled navigation control no longer requests keyboard input")
        scope.unmount(owner)
        XCTAssertFalse(scope.keepsNotchOpen)
    }

    private func makePanel() -> InteractionPanel {
        let panel = InteractionPanel(contentRect: CGRect(x: 100, y: 100, width: 320, height: 128),
                                     styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
                                     backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .mainMenu + 3
        panel.collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
        panel.contentView = NSView(frame: CGRect(x: 0, y: 0, width: 320, height: 128))
        panel.orderBack(nil)
        return panel
    }

    private func makeChild() -> NSPanel {
        let child = NSPanel(contentRect: CGRect(x: 120, y: 120, width: 100, height: 50),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        child.isReleasedWhenClosed = false
        return child
    }

    private func nativePopover() -> NSPopover {
        let popover = NSPopover()
        popover.animates = false
        popover.behavior = .applicationDefined
        let controller = NSViewController()
        controller.view = NSTextField(labelWithString: "Independent content")
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: 180, height: 60)
        return popover
    }

    private func editableField(in root: NSView) -> NSTextField? {
        if let field = root as? NSTextField, field.isEditable { return field }
        return root.subviews.lazy.compactMap { self.editableField(in: $0) }.first
    }

    private func settle(until condition: () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: 2)
        repeat {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            if condition() { return true }
        } while Date() < deadline
        return false
    }
}
