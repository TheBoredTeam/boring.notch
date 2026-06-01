//  NotchController.swift
//  IslandNotch
//
//  Purpose: Presents the floating notch UI. Wraps DynamicNotchKit so all of the
//           borderless / non-activating NSPanel + expand-collapse animation math
//           is delegated to a maintained package. On Macs without a notch the
//           package automatically falls back to a floating top-center style.
//
//  NOTE: DynamicNotchKit's public API can shift between major versions. This file
//        is the ONLY place that touches it — if the installed version differs,
//        adjust the calls here (everything else talks to NotchController, not the
//        package). Written against DynamicNotchKit 1.1.x:
//            let notch = DynamicNotch { expanded } compactLeading: { … } compactTrailing: { … }
//            await notch.expand()   /   await notch.compact()   /   await notch.hide()
//  Layer: Window

import AppKit
import DynamicNotchKit
import SwiftUI

@MainActor
final class NotchController {
    struct ShelfActions {
        var onCapture: (() -> Void)?
        var onCopyLatest: (() -> Void)?
        var onQuickLookLatest: (() -> Void)?
    }

    private let store: ScreenshotStore
    private let preferences: AppPreferences
    private var notch: DynamicNotch<AnyView, EmptyView, EmptyView>?
    private var isNotchVisible = false
    private(set) var isConstellagentRunning = false
    private var shelfActions = ShelfActions()
    private var collapseTask: Task<Void, Never>?
    private var hoverExpandTask: Task<Void, Never>?

    /// Whether the notch is currently expanded (open). Tracked locally because
    /// DynamicNotchKit does not expose its state publicly.
    private var isExpanded = false
    private var mouseMonitors: [Any] = []

    private let dragState = NotchDragState()
    private let shelfEnvironment = NotchShelfEnvironment()
    private let dropCatcher = DropCatcherWindow()

    init(store: ScreenshotStore, preferences: AppPreferences) {
        self.store = store
        self.preferences = preferences
    }

    func configureShelfActions(_ actions: ShelfActions) {
        shelfActions = actions
    }

    /// Builds the notch host and presents it immediately.
    func install() {
        guard notch == nil else { return }
        let store = store
        let preferences = preferences
        let dragState = dragState
        // boring.notch model: the notch opens on hover, but the half-screen screenSaver-level
        // panel must NOT block windows when the cursor is elsewhere. We drive both with a
        // global mouse-move monitor (`startHoverTracking`) that toggles `ignoresMouseEvents`
        // and expand/collapse based on whether the cursor is over the notch (or open shelf).
        // hoverBehavior stays empty so DynamicNotchKit's own hover logic never fights ours.
        let notch = DynamicNotch(hoverBehavior: []) {
            AnyView(
                NotchShelfView(
                    onCapture: { [weak self] in self?.shelfActions.onCapture?() },
                    onCopyLatest: { [weak self] in self?.shelfActions.onCopyLatest?() },
                    onQuickLookLatest: { [weak self] in self?.shelfActions.onQuickLookLatest?() },
                    onDropHoverChange: { [weak self] targeted in
                        self?.handleDropHover(targeted)
                    },
                    onDropAccepted: { [weak self] in
                        self?.handleDropAccepted()
                    }
                )
                .environment(store)
                .environment(preferences)
                .environment(dragState)
                .environment(self.shelfEnvironment)
            )
        } compactLeading: {
            EmptyView()
        } compactTrailing: {
            EmptyView()
        }
        // Drive the panel morph with our own motion vocabulary instead of DynamicNotchKit's
        // default `.bouncy(0.4)`, and — critically — set `skipIntermediateHides` so a
        // compact->expanded open no longer flashes through the hidden state with a 250ms
        // dead gap. The notch is opened dozens of times a day; this makes every open a
        // single continuous morph.
        notch.transitionConfiguration = Self.makeTransitionConfiguration()
        self.notch = notch
        configureDropCatcher()
        startHoverTracking()
        setNotchVisible(true)
    }

    /// Builds the panel-morph animation config. When the user prefers reduced motion we
    /// collapse the spring morph to a near-instant fade (movement dropped, the package's
    /// own window alpha cross-fade still provides a gentle comprehension cue).
    private static func makeTransitionConfiguration() -> DynamicNotchTransitionConfiguration {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            return DynamicNotchTransitionConfiguration(
                openingAnimation: Motion.notchReduced,
                closingAnimation: Motion.notchReduced,
                conversionAnimation: Motion.notchReduced,
                skipIntermediateHides: true
            )
        }
        return DynamicNotchTransitionConfiguration(
            openingAnimation: Motion.notchOpen,
            closingAnimation: Motion.notchClose,
            conversionAnimation: Motion.notchConvert,
            skipIntermediateHides: true
        )
    }

    /// One subtle alignment tap for a meaningful, one-shot event (capture taken, drop
    /// accepted). Kept to a single tap per event — never on the hover-open path, which
    /// fires constantly.
    private func performFeedbackTap() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// Toggles whether the DynamicNotchKit panel swallows mouse events. The panel is a
    /// half-screen, screenSaver-level window, so when the cursor is NOT over the notch it
    /// must be fully click-through or it blocks every window beneath it. The hover monitor
    /// flips this on the instant the cursor reaches the notch and off when it leaves.
    private func setNotchInteractive(_ interactive: Bool) {
        notch?.windowController?.window?.ignoresMouseEvents = !interactive
    }

    // MARK: Hover tracking (boring.notch model)

    /// Watches the global cursor position and (a) keeps the panel click-through unless the
    /// cursor is over the notch/open shelf, and (b) opens the notch on hover, closes it on
    /// leave. A passive mouse-move monitor — it never arms an overlay window, so windows
    /// drag freely everywhere except directly over the small notch hover target.
    private func startHoverTracking() {
        let handler: (NSEvent) -> Void = { [weak self] _ in
            Task { @MainActor in self?.evaluateHover() }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: { event in handler(event) }) {
            mouseMonitors.append(global)
        }
        // Local monitor covers the case where the cursor is over our own (interactive) panel.
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { event in
            handler(event)
            return event
        }) {
            mouseMonitors.append(local)
        }
    }

    private func evaluateHover() {
        guard isNotchVisible, !dragState.isInbound, let screen = NotchGeometry.targetScreen else { return }
        let region = isExpanded
            ? NotchGeometry.expandedHoverRect(on: screen)
            : NotchGeometry.notchHoverRect(on: screen)
        let over = region.contains(NSEvent.mouseLocation)
        // Interactive only while the cursor is over the notch/shelf — click-through otherwise.
        setNotchInteractive(over)
        if over {
            collapseTask?.cancel()
            if !isExpanded { scheduleHoverExpand() }
        } else {
            hoverExpandTask?.cancel()
            if isExpanded { scheduleIdleCollapse() }
        }
    }

    private func scheduleHoverExpand() {
        guard !isExpanded, hoverExpandTask == nil else { return }
        hoverExpandTask = Task { @MainActor in
            try? await Task.sleep(for: Motion.hoverOpenDelay)
            defer { hoverExpandTask = nil }
            guard !Task.isCancelled, isNotchVisible, let screen = NotchGeometry.targetScreen else { return }
            // Re-confirm the cursor is still on the notch before committing to open.
            guard NotchGeometry.notchHoverRect(on: screen).contains(NSEvent.mouseLocation) else { return }
            await expand()
        }
    }

    private func expand() async {
        guard let notch, isNotchVisible else { return }
        collapseTask?.cancel()
        setNotchInteractive(true)
        await notch.expand()
        setNotchInteractive(true)
        isExpanded = true
    }

    // MARK: AppKit drop catcher

    private func configureDropCatcher() {
        dropCatcher.catcher.onDragChange = { [weak self] active in
            Task { @MainActor in self?.setDragInbound(active) }
        }
        dropCatcher.catcher.onDropURLs = { [weak self] urls in
            Task { @MainActor in self?.importDropped(urls: urls) }
        }
        dropCatcher.catcher.onDropImage = { [weak self] image in
            Task { @MainActor in self?.importDropped(image: image) }
        }
    }

    private func positionDropCatcher() {
        guard let screen = NotchGeometry.targetScreen else { return }
        dropCatcher.setFrame(NotchGeometry.dragApproachRect(on: screen), display: false)
    }

    /// Driven by the AppKit drag session entering/leaving the catcher. A file drag over
    /// the notch expands the shelf so the user can drop on the notch or continue down onto
    /// the larger shelf target. (Mouse-move hover doesn't fire during a drag, so the
    /// catcher is what opens the notch for a photo drag.)
    private func setDragInbound(_ inbound: Bool) {
        guard isNotchVisible else { return }
        dragState.isInbound = inbound
        if inbound {
            hoverExpandTask?.cancel()
            collapseTask?.cancel()
            // Become interactive immediately (before the animation) so the drag can be
            // dropped onto the shelf the instant it expands.
            setNotchInteractive(true)
            Task { await self.expand() }
        } else {
            scheduleIdleCollapse()
        }
    }

    private func importDropped(urls: [URL]) {
        Task {
            var any = false
            for url in urls where await store.importImage(from: url) != nil { any = true }
            if any { handleDropAccepted() }
        }
    }

    private func importDropped(image: NSImage) {
        Task {
            let ok = await store.importImage(image) != nil
            if ok { handleDropAccepted() }
        }
    }

    private func scheduleIdleCollapse() {
        collapseTask?.cancel()
        collapseTask = Task { @MainActor in
            try? await Task.sleep(for: Motion.collapseDelay)
            guard !Task.isCancelled, isNotchVisible, self.notch != nil else { return }
            guard !dragState.isInbound else { return }
            // Don't collapse if the cursor wandered back over the open shelf in the meantime.
            if let screen = NotchGeometry.targetScreen,
               NotchGeometry.expandedHoverRect(on: screen).contains(NSEvent.mouseLocation) {
                return
            }
            await collapseToIdle()
        }
    }

    /// Presents the notch. Constellagent presence only affects the in-shelf badge.
    func setNotchVisible(_ visible: Bool) {
        isNotchVisible = visible
        guard notch != nil else { return }
        collapseTask?.cancel()
        if visible {
            positionDropCatcher()
            dropCatcher.orderFrontRegardless()
            Task { await presentIdle() }
        } else {
            dropCatcher.orderOut(nil)
            Task { await hide() }
        }
    }

    func setConstellagentRunning(_ running: Bool) {
        isConstellagentRunning = running
        shelfEnvironment.isConstellagentRunning = running
    }

    func flashNewCapture() {
        guard isNotchVisible else { return }
        performFeedbackTap()
        Task { await expandAndScheduleCollapse() }
    }

    func hide() async {
        collapseTask?.cancel()
        guard let notch else { return }
        await notch.hide()
    }

    // MARK: Private

    private var supportsCompactIdle: Bool {
        guard let screen = NotchGeometry.targetScreen else { return false }
        return NotchGeometry.hasNotch(screen)
    }

    private func presentIdle() async {
        guard let notch, isNotchVisible else { return }
        if supportsCompactIdle {
            await notch.compact()
        } else {
            await notch.hide()
        }
        isExpanded = false
        setNotchInteractive(false)
    }

    private func collapseToIdle() async {
        guard let notch, isNotchVisible else { return }
        if supportsCompactIdle {
            await notch.compact()
        } else {
            await notch.hide()
        }
        isExpanded = false
        setNotchInteractive(false)
    }

    /// A brief, NON-interactive peek (e.g. after a new capture). It stays click-through
    /// so it never blocks windows underneath — it's a glance, not an interaction.
    private func expandAndScheduleCollapse() async {
        guard let notch, isNotchVisible else { return }
        collapseTask?.cancel()
        setNotchInteractive(false)
        await notch.expand()
        // expand() can briefly recreate the window; re-assert click-through.
        setNotchInteractive(false)
        isExpanded = true
        collapseTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled, isNotchVisible, self.notch != nil else { return }
            guard !dragState.isInbound else { return }
            if let screen = NotchGeometry.targetScreen,
               NotchGeometry.expandedHoverRect(on: screen).contains(NSEvent.mouseLocation) {
                return
            }
            await collapseToIdle()
        }
    }

    /// Called from the shelf's SwiftUI `.onDrop` once a drag is over the expanded shelf,
    /// so we keep it expanded + interactive while the user lines up the drop.
    private func handleDropHover(_ targeted: Bool) {
        guard isNotchVisible else { return }
        dragState.isInbound = targeted
        if targeted {
            hoverExpandTask?.cancel()
            collapseTask?.cancel()
            setNotchInteractive(true)
            Task { await self.expand() }
        } else {
            scheduleIdleCollapse()
        }
    }

    private func handleDropAccepted() {
        guard isNotchVisible else { return }
        performFeedbackTap()
        dragState.isInbound = false
        Task { await expandAndScheduleCollapse() }
    }
}
