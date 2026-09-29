// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

/// A mounted native tab permits the nonactivating panel to accept keyboard
/// input when a control requests it. Mounting alone never changes focus.
@MainActor
protocol ExtensionTabInputHosting: AnyObject {
    var extensionTabInput: ExtensionTabInputScope { get }
}

@MainActor
final class ExtensionTabInputScope {
    private weak var owner: NSView?
    private weak var panel: NSPanel?
    private var previousKeyOnlyIfNeeded = false

    func allowsKey(in window: NSWindow) -> Bool {
        panel === window && owner?.window === window
    }

    func mount(_ view: NSView, in panel: NSPanel) {
        guard owner !== view || self.panel !== panel else { return }
        if let owner { unmount(owner) }
        owner = view
        self.panel = panel
        previousKeyOnlyIfNeeded = panel.becomesKeyOnlyIfNeeded
        // AppKit asks the clicked control's needsPanelToBecomeKey. A button
        // does not steal focus; a text field can enter the responder chain.
        panel.becomesKeyOnlyIfNeeded = true
    }

    func unmount(_ view: NSView) {
        // A disappearing old tab must not revoke its replacement's input.
        guard owner === view, let panel else { return }
        if owns(panel.firstResponder, inside: view) {
            panel.endEditing(for: nil)
            panel.makeFirstResponder(nil)
        }
        owner = nil
        self.panel = nil
        panel.becomesKeyOnlyIfNeeded = previousKeyOnlyIfNeeded
        if panel.isKeyWindow && !panel.canBecomeKey { panel.resignKey() }
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
    @ObservedObject var registry: ExtensionTabRegistry = .shared

    var body: some View {
        GeometryReader { geometry in
            if let tab = registry.tab(for: id) {
                ExtensionTabController(tab: tab, displayID: displayID)
                    .id(tab.contentIdentity(displayID: displayID))
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
    let displayID: String?

    func makeNSViewController(context: Context) -> NSViewController {
        let content = tab.makeController(displayID: displayID) ?? NSHostingController(rootView:
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
