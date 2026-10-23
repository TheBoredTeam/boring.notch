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

    var body: some View {
        HStack(spacing: 12) {
            FileShareView(dropInteraction: dropInteraction)
                .aspectRatio(1, contentMode: .fit)
            ShelfDropWell(
                dropInteraction: dropInteraction,
                animation: animation,
                showsShelvedItems: true
            )
        }
    }
}

/// The dashed drop target shared by the notch shelf and the floating panel.
/// The notch shows everything already on the shelf. The floating panel shows only what this drop added.
struct ShelfDropWell: View {
    let dropInteraction: DropInteractionState
    let animation: Animation?
    var showsShelvedItems: Bool
    /// Bumped each time the floating panel is shown, so the previous drop is not still sitting in the well.
    var appearanceSession: Int = 0

    @StateObject private var shelfState = ShelfStateViewModel.shared
    @State private var revealedIDs: Set<UUID> = []
    private let spacing: CGFloat = 8

    private var displayedItems: [ShelfItem] {
        let items = Defaults[.reverseShelfOrdering] ? Array(shelfState.items.reversed()) : shelfState.items
        guard !showsShelvedItems else { return items }
        return items.filter { revealedIDs.contains($0.id) }
    }

    var body: some View {
        ShelfQuickLookHost { quickLookService in
            dropChrome(quickLookService: quickLookService)
                .onChange(of: appearanceSession) {
                    revealedIDs = []
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
                        // The floating preview only displays the drop. Hit testing would let a
                        // right-click or drag-out pull the pointer out of the panel and close it.
                        .allowsHitTesting(showsShelvedItems)
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

        if !showsShelvedItems, displayedItems.count == 1, let item = displayedItems.first {
            ShelfItemView(
                item: item,
                quickLookService: quickLookService,
                dropInteraction: dropInteraction
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !displayedItems.isEmpty {
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
            .onDrop(of: ShelfDropService.supportedContentTypes, isTargeted: $interaction.dragDetectorTargeting) { providers in
                handleDrop(providers: providers)
            }
        } else {
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
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !ShelfSelectionModel.shared.isDragging else { return false }
        dropInteraction.dropEvent = true
        let showsPreview = !showsShelvedItems
        shelfState.load(providers) { matched in
            guard showsPreview else { return }
            revealedIDs = Set(matched.map(\.id))
        }
        // The notch does this when a drag enters it. A floating drop never opens the notch,
        // so the next hover would otherwise stay on the previous tab.
        BoringViewCoordinator.shared.currentView = .shelf
        return true
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
