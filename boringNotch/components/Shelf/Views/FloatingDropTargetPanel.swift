//
//  FloatingDropTargetPanel.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import AppKit
import Combine
import Defaults
import Observation
import SwiftUI

enum FloatingDropTargetPreviewEvent {
    case started
    case resolved(itemCount: Int)
    case changed(itemCount: Int)
}

@MainActor
final class FloatingDropTargetPreviewSession {
    struct Token: Equatable {
        let generation: Int
        let serial: Int
    }

    private var generation = 0
    private var serial = 0

    func beginPresentation(generation: Int) {
        self.generation = generation
        serial = 0
    }

    func beginDrop() -> Token {
        serial += 1
        return Token(generation: generation, serial: serial)
    }

    func isCurrent(_ token: Token) -> Bool {
        token.generation == generation && token.serial == serial
    }
}

/// Drop target shown beside the pointer. It must be allowed to become key:
/// a nonactivating panel that refuses key status never receives an in-progress drag.
@MainActor
final class FloatingDropTargetPanel: NSPanel {
    let dropInteraction = DropInteractionState()
    var onPreviewEvent: (@MainActor (FloatingDropTargetPreviewEvent) -> Void)?
    private let presentation = FloatingDropTargetPresentation()
    private let previewSession = FloatingDropTargetPreviewSession()
    private var pointerExitTask: Task<Void, Never>?
    private var onPointerExit: (@MainActor () -> Void)?
    private var shelfDragCancellable: AnyCancellable?
    private var fadeGeneration = 0
    private let shelfAnimation = BoringAnimations().animation
    var isWaitingForPointerExit: Bool { onPointerExit != nil }

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: FloatingDropTargetPlacement.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configureWindow()
        contentView = FirstMouseHostingView(
            rootView: FloatingDropTargetChrome(
                dropInteraction: dropInteraction,
                presentation: presentation,
                shelfAnimation: shelfAnimation,
                onHoverChanged: { [weak self] in self?.handlePointerHover($0) },
                previewSession: previewSession,
                onPreviewEvent: { [weak self] event in self?.onPreviewEvent?(event) },
                onLayoutSize: { [weak self] size in self?.matchWindow(to: size) }
            )
        )
        roundContentCorners()
        shelfDragCancellable = ShelfSelectionModel.shared.$isDragging
            .removeDuplicates()
            .sink { [weak self] isDragging in
                self?.handleShelfDragChanged(isDragging)
            }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func resetAppearance() {
        cancelPointerExitDismissal()
        dropInteraction.reset()
    }

    /// The content scales in SwiftUI; the window alpha fades separately because the
    /// window shadow does not follow SwiftUI content as it scales.
    func show(growingFrom anchor: CGPoint) {
        cancelPointerExitDismissal()
        dropInteraction.reset()
        fadeGeneration += 1
        presentation.panelSize = FloatingDropTargetPlacement.panelSize
        presentation.previewItemCount = 0
        presentation.anchor = UnitPoint(x: anchor.x, y: anchor.y)
        ignoresMouseEvents = false
        if !isVisible {
            alphaValue = 0
        }
        presentation.generation += 1
        previewSession.beginPresentation(generation: presentation.generation)
        orderFrontRegardless()
        withAnimation(StandardAnimations.open) {
            presentation.isShown = true
        }
        fade(to: 1, completion: nil)
    }

    func showPreview(itemCount: Int) {
        guard itemCount > 0 else { return }
        presentation.previewItemCount = itemCount
        let size = FloatingDropTargetPlacement.previewSize(itemCount: itemCount)
        // The item row uses this same spring. The window follows the resulting layout
        // instead of running a second, non-spring frame animation.
        withAnimation(shelfAnimation) {
            presentation.panelSize = size
        }
    }

    private func matchWindow(to size: CGSize) {
        guard size.width > 1, size.height > 1, let screen else { return }
        let next = FloatingDropTargetPlacement.frame(
            matching: size,
            currentFrame: frame,
            screenFrame: screen.frame
        )
        guard abs(next.width - frame.width) > 0.5 || abs(next.minX - frame.minX) > 0.5 else { return }
        setFrame(next, display: true)
    }

    func hide(completion: @escaping () -> Void) {
        cancelPointerExitDismissal()
        ignoresMouseEvents = true
        fadeGeneration += 1
        let generation = fadeGeneration
        withAnimation(StandardAnimations.close) {
            presentation.isShown = false
        }
        fade(to: 0) { [weak self] in
            // A show() during the fade takes the panel back, so it must stay on screen.
            guard let self, self.fadeGeneration == generation else { return }
            self.orderOut(nil)
            completion()
        }
    }

    func dismissWhenPointerLeaves(_ action: @escaping @MainActor () -> Void) {
        onPointerExit = action
        handlePointerHover(frame.contains(NSEvent.mouseLocation))
    }

    /// A newer drop has to stay up until its own preview resolves.
    func suspendPointerExit() {
        cancelPointerExitDismissal()
    }

    private func handlePointerHover(_ inside: Bool) {
        pointerExitTask?.cancel()
        pointerExitTask = nil
        guard !inside,
              onPointerExit != nil,
              !ShelfSelectionModel.shared.isDragging else {
            return
        }
        pointerExitTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(hoverExitDelayMilliseconds))
            guard !Task.isCancelled,
                  let self,
                  !self.frame.contains(NSEvent.mouseLocation),
                  let onPointerExit = self.onPointerExit else {
                return
            }
            self.onPointerExit = nil
            self.pointerExitTask = nil
            onPointerExit()
        }
    }

    private func handleShelfDragChanged(_ isDragging: Bool) {
        pointerExitTask?.cancel()
        pointerExitTask = nil
        guard !isDragging, onPointerExit != nil else { return }
        handlePointerHover(frame.contains(NSEvent.mouseLocation))
    }

    private func cancelPointerExitDismissal() {
        pointerExitTask?.cancel()
        pointerExitTask = nil
        onPointerExit = nil
    }

    private func fade(to alpha: CGFloat, completion: (@MainActor () -> Void)?) {
        let duration = Defaults[.enableOpeningAnimation] ? 0.2 / Defaults[.animationSpeedMultiplier] : 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            animator().alphaValue = alpha
        } completionHandler: {
            MainActor.assumeIsolated {
                completion?()
            }
        }
    }

    private func configureWindow() {
        isOpaque = false
        hasShadow = true
        backgroundColor = .clear
        isMovable = false
        hidesOnDeactivate = false
        // One level above the notch window. `.floating` is underneath that window, so a
        // drop on the overlapping square would hit the notch instead. `.screenSaver`
        // draws the panel, but the drag passes through it.
        level = BoringNotchSkyLightWindow.windowLevel + 1
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // Borderless windows have no visible title, so VoiceOver would otherwise announce an unnamed window.
        setAccessibilityTitle(String(localized: "Drop target"))
    }

    /// Clip the window while its frame animates. A SwiftUI clip animates separately from
    /// that frame and briefly becomes square.
    private func roundContentCorners() {
        contentView?.wantsLayer = true
        contentView?.layer?.cornerRadius = cornerRadiusInsets.opened.bottom
        contentView?.layer?.masksToBounds = true
    }
}

@Observable
private final class FloatingDropTargetPresentation {
    var isShown = false
    var anchor: UnitPoint = .top
    var generation = 0
    var panelSize = FloatingDropTargetPlacement.panelSize
    var previewItemCount = 0
}

/// Clicks on the shelf background also count, so a grab does not require a focus click first.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct FloatingDropTargetLayoutSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

private struct FloatingDropTargetChrome: View {
    let dropInteraction: DropInteractionState
    let presentation: FloatingDropTargetPresentation
    let shelfAnimation: Animation
    let onHoverChanged: (Bool) -> Void
    let previewSession: FloatingDropTargetPreviewSession
    let onPreviewEvent: @MainActor (FloatingDropTargetPreviewEvent) -> Void
    let onLayoutSize: (CGSize) -> Void

    var body: some View {
        ShelfDropWell(
            dropInteraction: dropInteraction,
            animation: shelfAnimation,
            showsShelvedItems: false,
            appearanceSession: presentation.generation,
            previewSession: previewSession,
            onPreviewEvent: onPreviewEvent
        )
            // Same inset the notch uses around the shelf row.
            .padding(12)
            .frame(width: presentation.panelSize.width, height: presentation.panelSize.height)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: FloatingDropTargetLayoutSizeKey.self, value: proxy.size)
                }
            }
            .background(.black)
            .onPreferenceChange(FloatingDropTargetLayoutSizeKey.self, perform: onLayoutSize)
            .scaleEffect(presentation.isShown ? 1 : 0.9, anchor: presentation.anchor)
            .onHover(perform: onHoverChanged)
            .overlay(alignment: .bottomTrailing) {
                if presentation.previewItemCount > FloatingDropTargetPlacement.visibleItemLimit {
                    Text("\(presentation.previewItemCount) items")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.7), in: Capsule())
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }
    }
}
