//
//  ShelfItemView.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-24.
//

import SwiftUI
import AppKit
import Defaults

struct ShelfView: View {
    let dropInteraction: DropInteractionState
    let animation: Animation?
    @StateObject var shelfState = ShelfStateViewModel.shared

    private let spacing: CGFloat = 8

    private var displayedItems: [ShelfItem] {
        Defaults[.reverseShelfOrdering] ? Array(shelfState.items.reversed()) : shelfState.items
    }

    var body: some View {
        @Bindable var interaction = dropInteraction

        ShelfQuickLookHost { quickLookService in
            HStack(spacing: 12) {
                FileShareView(dropInteraction: dropInteraction)
                    .aspectRatio(1, contentMode: .fit)
                panel(quickLookService: quickLookService)
                    .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $interaction.dragDetectorTargeting) { providers in
                        handleDrop(providers: providers)
                    }
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !ShelfSelectionModel.shared.isDragging else { return false }
        dropInteraction.dropEvent = true
        shelfState.load(providers)
        return true
    }

    private func panel(quickLookService: QuickLookService) -> some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(
                dropInteraction.dragDetectorTargeting
                    ? Color.accentColor.opacity(0.9)
                    : Color.white.opacity(0.1),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10])
            )
            .overlay {
                ZStack {
                    ShelfBackgroundInteractionView()
                    content(quickLookService: quickLookService)
                        .padding()
                }
            }
            .transaction { transaction in
                transaction.animation = animation
            }
    }

    private func content(quickLookService: QuickLookService) -> some View {
        @Bindable var interaction = dropInteraction

        return Group {
            if shelfState.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray.and.arrow.down")
                        .symbolVariant(.fill)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white, .gray)
                        .imageScale(.large)

                    Text("Drop files here or paste")
                        .foregroundStyle(.gray)
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.medium)
                }
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: spacing) {
                        ForEach(displayedItems) { item in
                            ShelfItemView(
                                item: item,
                                quickLookService: quickLookService,
                                dropInteraction: dropInteraction
                            )
                        }
                    }
                }
                .padding(-spacing)
                .scrollIndicators(.never)
                .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $interaction.dragDetectorTargeting) { providers in
                    handleDrop(providers: providers)
                }
            }
        }
        .onAppear {
            shelfState.cleanupInvalidItems()
        }
    }
}

private struct ShelfBackgroundInteractionView: NSViewRepresentable {
    func makeNSView(context: Context) -> BackgroundView {
        BackgroundView()
    }

    func updateNSView(_ nsView: BackgroundView, context: Context) {}

    static func dismantleNSView(_ nsView: BackgroundView, coordinator: ()) {
        nsView.releaseKeyboardFocus()
        nsView.stopMonitoring()
    }

    final class BackgroundView: NSView {
        private var mouseMonitor: Any?
        private var keyMonitor: Any?
        private var trackingArea: NSTrackingArea?
        private var keepsKeyboardFocus = false

        override var acceptsFirstResponder: Bool { true }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil {
                releaseKeyboardFocus()
            }
            super.viewWillMove(toWindow: newWindow)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()

            guard let window else { return }

            mouseMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] event in
                self?.handleMouseDown(event)
                return event
            }

            keyMonitor = NSEvent.addLocalMonitorForEvents(
                matching: .keyDown
            ) { [weak self] event in
                guard let self else { return event }
                return self.handleKeyDown(event)
            }

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidResignKey(_:)),
                name: NSWindow.didResignKeyNotification,
                object: window
            )

            Task { @MainActor [weak self] in
                self?.requestKeyboardFocusIfPointerInside()
                try? await Task.sleep(for: .milliseconds(150))
                self?.requestKeyboardFocusIfPointerInside()
            }
        }

        @objc private func windowDidResignKey(_ notification: Notification) {
            releaseKeyboardFocus()
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        // The shelf takes keyboard focus on hover, so unhandled keys must not fall through to NSBeep.
        override func keyDown(with event: NSEvent) {}

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let trackingArea = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(trackingArea)
            self.trackingArea = trackingArea
        }

        override func mouseEntered(with event: NSEvent) {
            requestKeyboardFocus()
        }

        override func mouseExited(with event: NSEvent) {
            guard !keepsKeyboardFocus, let window else { return }
            guard !window.frame.contains(NSEvent.mouseLocation) else { return }
            releaseKeyboardFocus()
        }

        private func requestKeyboardFocusIfPointerInside() {
            guard let window, window.isVisible else { return }
            let location = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            guard bounds.contains(location) else { return }
            requestKeyboardFocus()
        }

        func stopMonitoring() {
            if let mouseMonitor {
                NSEvent.removeMonitor(mouseMonitor)
                self.mouseMonitor = nil
            }
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.didResignKeyNotification,
                object: nil
            )
        }

        func releaseKeyboardFocus() {
            keepsKeyboardFocus = false
            guard let window = window as? BoringNotchSkyLightWindow else { return }
            if window.firstResponder === self {
                window.makeFirstResponder(nil)
            }
            if window.isKeyWindow {
                window.resignKey()
            }
            window.wantsKeyboardFocus = false
        }

        private func requestKeyboardFocus() {
            guard let window = window as? BoringNotchSkyLightWindow else { return }
            window.wantsKeyboardFocus = true
            if !window.isKeyWindow {
                window.makeKey()
            }
            if window.firstResponder !== self {
                window.makeFirstResponder(self)
            }
        }

        private func handleMouseDown(_ event: NSEvent) {
            guard let window, event.window === window else { return }

            guard bounds.contains(convert(event.locationInWindow, from: nil)) else {
                if event.type == .leftMouseDown {
                    releaseKeyboardFocus()
                }
                return
            }

            let contentView = window.contentView
            let isItemClick = contentView.map { view in
                isShelfItemInteraction(view.hitTest(view.convert(event.locationInWindow, from: nil)))
            } ?? false

            if event.type == .rightMouseDown {
                guard !isItemClick else { return }
                showPasteMenu(with: event)
                return
            }

            requestKeyboardFocus()
            keepsKeyboardFocus = true
            guard !isItemClick else { return }

            ShelfSelectionModel.shared.clear()
        }

        private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
            guard let window,
                  event.window === window,
                  window.isKeyWindow,
                  !(window.firstResponder is NSTextView),
                  Self.isPasteShortcut(event),
                  ShelfPasteService.canPaste
            else { return event }

            ShelfPasteService.paste()
            return nil
        }

        private static func isPasteShortcut(_ event: NSEvent) -> Bool {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            return modifiers.contains(.command)
                && !modifiers.contains(.shift)
                && !modifiers.contains(.option)
                && !modifiers.contains(.control)
                && event.charactersIgnoringModifiers?.lowercased() == "v"
        }

        private func showPasteMenu(with event: NSEvent) {
            let menu = NSMenu()
            let pasteItem = NSMenuItem(
                title: Strings.paste,
                action: #selector(paste(_:)),
                keyEquivalent: ""
            )
            pasteItem.target = self
            pasteItem.isEnabled = ShelfPasteService.canPaste
            menu.addItem(pasteItem)
            menu.popUp(
                positioning: pasteItem,
                at: convert(event.locationInWindow, from: nil),
                in: self
            )
        }

        @objc func paste(_ sender: Any?) {
            guard ShelfPasteService.canPaste else { return }
            ShelfPasteService.paste()
        }

        private func isShelfItemInteraction(_ hitView: NSView?) -> Bool {
            var view = hitView
            while let currentView = view {
                if currentView is any ShelfItemInteractionSurface {
                    return true
                }
                view = currentView.superview
            }
            return false
        }
    }
}

private struct ShelfQuickLookHost<Content: View>: View {
    @State private var service = QuickLookService()
    @ViewBuilder let content: (QuickLookService) -> Content

    var body: some View {
        content(service)
            .quickLookPresenter(using: service)
    }
}
