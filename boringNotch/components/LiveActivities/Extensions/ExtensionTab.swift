// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

import AppKit
import Combine
import SwiftUI

/// A mounted native tab permits the nonactivating panel to accept keyboard
/// input when a control requests it. Mounting alone never changes focus.
@MainActor
protocol ExtensionTabInputHosting: AnyObject {
    var extensionTabInput: ExtensionTabInputScope { get }
}

@MainActor
final class ExtensionTabInputScope {
    /// Emitted after AppKit's interaction state changes, never on a timer.
    let interactionChanges = PassthroughSubject<Void, Never>()
    private weak var owner: NSView?
    private weak var panel: NSPanel?
    private var previousKeyOnlyIfNeeded = false
    private let existingChildren = NSHashTable<NSWindow>.weakObjects()
    private var observations = Set<AnyCancellable>()
    private var popovers: [ObjectIdentifier: WeakPopover] = [:]
    private var wasKeepingOpen = false

    private final class WeakPopover {
        weak var value: NSPopover?
        init(_ value: NSPopover) { self.value = value }
    }

    /// Merely mounting a tab or making a button first responder is not a hold.
    /// Only this mount's visible child windows or active native keyboard input count.
    var keepsNotchOpen: Bool {
        guard let owner, let panel, owner.window === panel, panel.isVisible else { return false }
        if !ownedChildren(in: panel).filter(\.isVisible).isEmpty { return true }
        guard panel.isKeyWindow, owns(panel.firstResponder, inside: owner) else { return false }
        if let text = panel.firstResponder as? NSTextView { return text.isEditable }
        if let field = panel.firstResponder as? NSTextField { return field.isEditable }
        if panel.firstResponder is any NSTextInputClient { return true }
        // AppKit controls declare whether they need panel keyboard focus.
        // Honor that contract for navigation as well as editing, without
        // retaining the notch for ordinary buttons or inactive windows.
        guard let view = panel.firstResponder as? NSView else { return false }
        return view.acceptsFirstResponder && view.needsPanelToBecomeKey
    }

    func allowsKey(in window: NSWindow) -> Bool {
        panel === window && owner?.window === window
    }

    func mount(_ view: NSView, in panel: NSPanel) {
        guard owner !== view || self.panel !== panel else { return }
        if let owner { unmount(owner) }
        owner = view
        self.panel = panel
        (panel.childWindows ?? []).forEach { existingChildren.add($0) }
        previousKeyOnlyIfNeeded = panel.becomesKeyOnlyIfNeeded
        // AppKit asks the clicked control's needsPanelToBecomeKey. A button
        // does not steal focus; a text field can enter the responder chain.
        panel.becomesKeyOnlyIfNeeded = true
        observeInteractions(in: panel)
        interactionDidChange()
    }

    func unmount(_ view: NSView) {
        // A disappearing old tab must not revoke its replacement's input.
        guard owner === view, let panel else { return }
        let children = ownedChildren(in: panel)
        let shownPopovers = popovers.values.compactMap(\.value)
        observations.removeAll()
        popovers.removeAll()
        if owns(panel.firstResponder, inside: view) {
            panel.endEditing(for: nil)
            panel.makeFirstResponder(nil)
        }
        owner = nil
        self.panel = nil
        existingChildren.removeAllObjects()
        panel.becomesKeyOnlyIfNeeded = previousKeyOnlyIfNeeded
        // An anchored presentation cannot outlive the tab that created it.
        shownPopovers.forEach { $0.close() }
        for child in children.reversed() {
            child.sheetParent?.endSheet(child)
            child.parent?.removeChildWindow(child)
            if child.isVisible {
                child.orderOut(nil)
                child.close()
            }
        }
        if panel.isKeyWindow && !panel.canBecomeKey { panel.resignKey() }
        interactionDidChange()
    }

    private func ownedChildren(in window: NSWindow) -> [NSWindow] {
        (window.childWindows ?? []).filter { !existingChildren.contains($0) }
            .flatMap { [$0] + ownedChildren(in: $0) }
    }

    private func observeInteractions(in panel: NSPanel) {
        // firstResponder is explicitly KVO compliant in AppKit. Key-window
        // notifications complete the distinction between editing and focus left
        // behind after the user switches to another app or window.
        panel.publisher(for: \.firstResponder)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.interactionDidChange() }
            .store(in: &observations)
        let events: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
            NSWindow.didUpdateNotification, NSWindow.didChangeOcclusionStateNotification,
            NSWindow.willCloseNotification, NSWindow.didEndSheetNotification,
            NSPopover.didShowNotification, NSPopover.didCloseNotification
        ]
        Publishers.MergeMany(events.map { NotificationCenter.default.publisher(for: $0) })
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self, let panel = self.panel, let owner = self.owner else { return }
                if notification.name == NSWindow.willCloseNotification, notification.object as? NSWindow === panel {
                    self.unmount(owner)
                    return
                }
                if let popover = notification.object as? NSPopover {
                    let id = ObjectIdentifier(popover)
                    if notification.name == NSPopover.didCloseNotification {
                        self.popovers.removeValue(forKey: id)
                    } else if let window = popover.contentViewController?.viewIfLoaded?.window,
                              self.ownedChildren(in: panel).contains(where: { $0 === window }) {
                        self.popovers[id] = WeakPopover(popover)
                    }
                }
                self.interactionDidChange()
            }
            .store(in: &observations)
    }

    private func interactionDidChange() {
        let current = keepsNotchOpen
        guard wasKeepingOpen != current else { return }
        wasKeepingOpen = current
        interactionChanges.send()
    }

    private func owns(_ responder: NSResponder?, inside root: NSView) -> Bool {
        if let view = responder as? NSView, view === root || view.isDescendant(of: root) { return true }
        // AppKit's shared field editor may sit outside the content subtree.
        if let editor = responder as? NSTextView, editor.isFieldEditor,
           let view = editor.delegate as? NSView {
            return view === root || view.isDescendant(of: root)
        }
        return false
    }
}

/// The host supplies a finite desktop content region beneath its native tab
/// chrome. Extensions own all layout and live updates inside that region.
struct ExtensionTabContent: View {
    let id: ExtensionTabID
    let displayID: String?
    var presentation: ExtensionTabPresentation = .regular
    @ObservedObject var registry: ExtensionTabRegistry = .shared

    var body: some View {
        GeometryReader { geometry in
            let context = ExtensionTabLayoutContext(presentation: presentation, displayID: displayID,
                                                    contentSize: geometry.size)
            if context.isValid, let tab = registry.tab(for: id, presentation: presentation) {
                ExtensionTabController(tab: tab, layoutContext: context)
                    .id(tab.contentIdentity(context: context))
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .accessibilityLabel(tab.descriptor.title)
            }
        }
        .clipped()
    }
}

private struct ExtensionTabController: NSViewControllerRepresentable {
    let tab: ExtensionTab
    let layoutContext: ExtensionTabLayoutContext

    func makeNSViewController(context: Context) -> NSViewController {
        let content = tab.makeController(context: layoutContext) ?? NSHostingController(rootView:
            ContentUnavailableView {
                Label("Content unavailable", systemImage: "puzzlepiece.extension")
                    .font(.callout)
            }
        )
        return ExtensionTabContainerController(content: content)
    }

    func updateNSViewController(_ controller: NSViewController, context: Context) {
        // The plugin updates its existing AppKit view or observed SwiftUI model.
        // Metadata publications must not reset navigation or content state.
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsViewController: NSViewController, context: Context) -> CGSize? {
        // A plugin's intrinsic/preferred size cannot resize the host's chrome.
        guard let width = proposal.width, let height = proposal.height,
              width.isFinite, height.isFinite else { return .zero }
        return CGSize(width: max(0, width), height: max(0, height))
    }
}

/// AppKit controls can have alignment insets outside their proposed frame. A
/// host-owned container gives every plugin the same exact, clipped boundary.
private final class ExtensionTabContainerController: NSViewController {
    private let content: NSViewController

    init(content: NSViewController) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = ExtensionTabContainerView(frame: .zero)
        view.wantsLayer = true
        view.layer?.masksToBounds = true
        addChild(content)
        content.view.frame = view.bounds
        content.view.autoresizingMask = [.width, .height]
        view.addSubview(content.view)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        content.view.frame = view.bounds
    }
}

private final class ExtensionTabContainerView: NSView {
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if window !== newWindow, let host = window as? any ExtensionTabInputHosting {
            host.extensionTabInput.unmount(self)
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let panel = window as? NSPanel, let host = panel as? any ExtensionTabInputHosting {
            host.extensionTabInput.mount(self, in: panel)
        }
    }
}
