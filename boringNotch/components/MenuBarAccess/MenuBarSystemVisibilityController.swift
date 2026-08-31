//
//  MenuBarSystemVisibilityController.swift
//  boringNotch
//
//  Implements a Hidden Bar-style menu bar section. The user places items to
//  the left of our divider once with Command-drag; changing the divider length
//  then reveals or pushes that whole section out of the visible menu bar.
//

import AppKit
import Combine
import Defaults

@MainActor
final class MenuBarSystemVisibilityController: ObservableObject {
    static let shared = MenuBarSystemVisibilityController()

    @Published private(set) var isCollapsed: Bool
    @Published private(set) var isArranging = false
    @Published private(set) var hasCompletedSetup: Bool

    private let dividerStatusItem: NSStatusItem
    private let dividerAutosaveName = "BoringNotchHiddenItemsDivider"
    private let expandedDividerLength: CGFloat = 18
    private var screenParametersObserver: NSObjectProtocol?
    private var delayedRestoreTask: Task<Void, Never>?
    private var hasStarted = false

    private init() {
        isCollapsed = Defaults[.menuBarHiddenSectionCollapsed]
        hasCompletedSetup = Defaults[.menuBarHiddenSectionSetupCompleted]
        dividerStatusItem = NSStatusBar.system.statusItem(withLength: expandedDividerLength)

        dividerStatusItem.autosaveName = dividerAutosaveName
        dividerStatusItem.isVisible = true
        if let button = dividerStatusItem.button {
            button.image = Self.makeDividerImage()
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            button.appearsDisabled = false
            button.cell?.isEnabled = true
            button.toolTip = String(
                localized: "Boring Notch hidden items divider — Command-drag to reposition"
            )
        }

        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applyCurrentState()
            }
        }

        // Never trust the item identifiers saved by the former automatic move
        // implementation. They do not describe the actual side of the divider.
        // Existing users therefore start expanded and explicitly arrange once.
        if !hasCompletedSetup {
            isCollapsed = false
            Defaults[.menuBarHiddenSectionCollapsed] = false
        }
        applyCurrentState()
    }

    deinit {
        delayedRestoreTask?.cancel()
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
        }
    }

    func start() {
        dividerStatusItem.isVisible = true
        guard !hasStarted else {
            applyCurrentState()
            return
        }
        hasStarted = true

        // Let macOS restore the divider's autosaved position before applying a
        // potentially very wide collapsed length. Applying it during launch can
        // cause the status item to be restored at an unexpected position.
        dividerStatusItem.length = expandedDividerLength
        delayedRestoreTask?.cancel()
        delayedRestoreTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self, !self.isArranging else { return }
            self.applyCurrentState()
        }
    }

    func beginArrangement() {
        delayedRestoreTask?.cancel()
        isArranging = true
        setCollapsed(false)
        dividerStatusItem.isVisible = true
        dividerStatusItem.length = expandedDividerLength
    }

    func finishArrangement(collapse: Bool) {
        hasCompletedSetup = true
        Defaults[.menuBarHiddenSectionSetupCompleted] = true
        isArranging = false
        setCollapsed(collapse)
    }

    func resetArrangement() {
        hasCompletedSetup = false
        Defaults[.menuBarHiddenSectionSetupCompleted] = false
        isArranging = true
        setCollapsed(false)
    }

    func toggleCollapsed() {
        guard hasCompletedSetup, !isArranging else { return }
        setCollapsed(!isCollapsed)
    }

    func setCollapsed(_ collapsed: Bool) {
        guard !collapsed || hasCompletedSetup else {
            beginArrangement()
            return
        }
        isCollapsed = collapsed
        Defaults[.menuBarHiddenSectionCollapsed] = collapsed
        applyCurrentState()
    }

    private func applyCurrentState() {
        dividerStatusItem.isVisible = true
        dividerStatusItem.length = isCollapsed && hasCompletedSetup && !isArranging
            ? collapsedDividerLength
            : expandedDividerLength
    }

    private var collapsedDividerLength: CGFloat {
        // Status items are replicated across attached displays. Hidden Bar uses
        // the widest full display frame, then clamps the result to avoid both
        // leaking items on a wider display and macOS's 10,000-point limit.
        let widestDisplay = NSScreen.screens.map(\.frame.width).max() ?? 1728
        return max(500, min(widestDisplay * 2, 10_000))
    }

    private static func makeDividerImage() -> NSImage {
        let image = NSImage(
            size: NSSize(width: 5, height: 16),
            flipped: false
        ) { rect in
            NSColor.black.setFill()
            NSBezierPath(
                roundedRect: NSRect(
                    x: rect.midX - 0.75,
                    y: 1,
                    width: 1.5,
                    height: rect.height - 2
                ),
                xRadius: 0.75,
                yRadius: 0.75
            ).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
