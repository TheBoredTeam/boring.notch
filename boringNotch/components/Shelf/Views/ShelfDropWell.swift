//
//  ShelfDropWell.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import AppKit
import Defaults
import SwiftUI

/// The dashed drop target shared by the notch shelf and the floating panel.
/// The notch shows everything already on the shelf. The floating panel shows only what this drop added.
struct ShelfDropWell: View {
    let dropInteraction: DropInteractionState
    let animation: Animation?
    var showsShelvedItems: Bool
    /// Bumped each time the floating panel is shown, so the previous drop is not still sitting in the well.
    var appearanceSession: Int = 0
    /// Tracks floating preview identity across panel presentations. Nil on the notch shelf.
    var previewSession: FloatingDropTargetPreviewSession? = nil
    var onPreviewEvent: (@MainActor (FloatingDropTargetPreviewEvent) -> Void)? = nil

    @StateObject private var shelfState = ShelfStateViewModel.shared
    @State private var revealedIDs: Set<UUID> = []
    /// Session that produced `revealedIDs`. A newer presentation renders nothing until its own drop resolves.
    @State private var revealedDuring = -1
    @State private var reportedPreviewCount = 0
    private let spacing: CGFloat = 8

    private var displayedItems: [ShelfItem] {
        let items = Defaults[.reverseShelfOrdering] ? Array(shelfState.items.reversed()) : shelfState.items
        guard !showsShelvedItems else { return items }
        guard revealedDuring == appearanceSession else { return [] }
        return items.filter { revealedIDs.contains($0.id) }
    }

    var body: some View {
        ShelfQuickLookHost { quickLookService in
            dropChrome(quickLookService: quickLookService)
                .onChange(of: appearanceSession) {
                    revealedIDs = []
                    revealedDuring = -1
                    reportedPreviewCount = 0
                }
                .onChange(of: displayedItems.count) { _, count in
                    reportPreviewCount(count)
                }
        }
    }

    private func dropChrome(quickLookService: QuickLookService) -> some View {
        @Bindable var interaction = dropInteraction

        return RoundedRectangle(cornerRadius: 16)
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
            .onDrop(of: ShelfDropService.supportedContentTypes, isTargeted: $interaction.dragDetectorTargeting) { providers in
                handleDrop(providers: providers)
            }
            .onAppear {
                // The floating panel is created at launch. Validating bookmarks belongs to the notch shelf.
                guard showsShelvedItems else { return }
                shelfState.cleanupInvalidItems()
            }
    }

    @ViewBuilder
    private func content(quickLookService: QuickLookService) -> some View {
        @Bindable var interaction = dropInteraction

        if displayedItems.isEmpty {
            emptyDropContent
        } else if showsShelvedItems {
            ScrollView(.horizontal) {
                LazyHStack(spacing: spacing) {
                    itemViews(quickLookService: quickLookService)
                }
            }
            .padding(-spacing)
            .scrollIndicators(.never)
            .onDrop(of: ShelfDropService.supportedContentTypes, isTargeted: $interaction.dragDetectorTargeting) { providers in
                handleDrop(providers: providers)
            }
        } else if displayedItems.count > FloatingDropTargetPlacement.visibleItemLimit {
            ScrollView(.horizontal) {
                itemRow(quickLookService: quickLookService)
            }
            .scrollIndicators(.never)
        } else {
            itemRow(quickLookService: quickLookService)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func itemRow(quickLookService: QuickLookService) -> some View {
        HStack(spacing: spacing) {
            itemViews(quickLookService: quickLookService)
        }
        .animation(animation, value: displayedItems.map(\.id))
    }

    private func itemViews(quickLookService: QuickLookService) -> some View {
        ForEach(displayedItems) { item in
            ShelfItemView(
                item: item,
                quickLookService: quickLookService,
                dropInteraction: dropInteraction
            )
        }
    }

    private var emptyDropContent: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down")
                .symbolVariant(.fill)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white, .gray)
                .imageScale(.large)

            Text("Drop files here")
                .foregroundStyle(.gray)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !ShelfSelectionModel.shared.isDragging else { return false }
        dropInteraction.dropEvent = true
        if showsShelvedItems {
            shelfState.load(providers)
        } else {
            revealDroppedItems(from: providers)
        }
        return true
    }

    /// The floating well shows only this drop. A load that finishes after the panel is shown
    /// again, or after a newer drop, must not write into the well.
    private func revealDroppedItems(from providers: [NSItemProvider]) {
        guard let previewSession else { return }
        let token = previewSession.beginDrop()
        onPreviewEvent?(.started)
        shelfState.load(providers) { matched in
            guard previewSession.isCurrent(token) else { return }
            revealedIDs = Set(matched.map(\.id))
            revealedDuring = token.generation
            reportedPreviewCount = matched.count
            onPreviewEvent?(.resolved(itemCount: matched.count))
            // The notch selects the shelf when a drag enters it. A floating drop does not,
            // so select it here only when the shelf actually contains something.
            if !shelfState.isEmpty {
                BoringViewCoordinator.shared.currentView = .shelf
            }
        }
    }

    /// Removal changes the visible count after the drop has already resolved.
    /// The initial resolve reports its own count, so this only follows later changes.
    /// The notch is still closed, so an emptied shelf has to leave the shelf tab itself.
    private func reportPreviewCount(_ count: Int) {
        guard !showsShelvedItems,
              revealedDuring == appearanceSession,
              reportedPreviewCount > 0,
              count != reportedPreviewCount else {
            return
        }
        reportedPreviewCount = count
        onPreviewEvent?(.changed(itemCount: count))
        if shelfState.isEmpty {
            BoringViewCoordinator.shared.currentView = .home
        }
    }
}

private struct ShelfBackgroundInteractionView: NSViewRepresentable {
    func makeNSView(context: Context) -> BackgroundView {
        BackgroundView()
    }

    func updateNSView(_ nsView: BackgroundView, context: Context) {}

    static func dismantleNSView(_ nsView: BackgroundView, coordinator: ()) {
        nsView.stopMonitoring()
    }

    final class BackgroundView: NSView {
        private var eventMonitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()

            guard window != nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: .leftMouseDown
            ) { [weak self] event in
                self?.handle(event)
                return event
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        func stopMonitoring() {
            guard let eventMonitor else { return }
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }

        private func handle(_ event: NSEvent) {
            guard let window,
                  event.window === window,
                  bounds.contains(convert(event.locationInWindow, from: nil)),
                  let contentView = window.contentView
            else { return }

            let hitPoint = contentView.convert(event.locationInWindow, from: nil)
            guard !isShelfItemInteraction(contentView.hitTest(hitPoint)) else { return }

            ShelfSelectionModel.shared.clear()
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
