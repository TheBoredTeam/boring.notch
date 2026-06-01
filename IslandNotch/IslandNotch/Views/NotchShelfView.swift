//  NotchShelfView.swift
//  IslandNotch
//
//  Purpose: The expanded notch content — a horizontal strip of recent shots that
//           grows on hover, plus the drag/throw drop target for adding images.
//  Layer: View

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NotchShelfView: View {
    @Environment(ScreenshotStore.self) private var store
    @Environment(NotchDragState.self) private var dragState
    @Environment(NotchShelfEnvironment.self) private var shelfEnvironment

    var onCapture: (() -> Void)?
    var onCopyLatest: (() -> Void)?
    var onQuickLookLatest: (() -> Void)?
    var onDropHoverChange: ((Bool) -> Void)?
    var onDropAccepted: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isExpanded = false
    @State private var isDropTargeted = false
    @State private var acceptedPop = false

    private let maxVisible = 8

    private var showingDropZone: Bool { isDropTargeted || dragState.isInbound }

    var body: some View {
        ZStack {
            Group {
                if store.entries.isEmpty {
                    emptyDropHint
                } else {
                    shelf
                }
            }
            .opacity(showingDropZone ? 0.12 : 1)

            if showingDropZone {
                DropZoneView()
                    .transition(Motion.transition(Motion.overlay, reduceMotion: reduceMotion))
            }
        }
        .frame(minWidth: showingDropZone ? 260 : 0, minHeight: showingDropZone ? 92 : 0)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.black.opacity(0.85))
        )
        .overlay(alignment: .topTrailing) {
            if !shelfEnvironment.isConstellagentRunning {
                Image(systemName: "circle")
                    .font(.system(size: 5))
                    .foregroundStyle(.orange.opacity(0.8))
                    .padding(6)
                    .help("Constellagent is not running")
            }
        }
        .scaleEffect(acceptedPop && !reduceMotion ? 1.04 : 1.0)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .acceptClickThrough()
        .onHover { hovering in
            // Optimistic local expand before DynamicNotchKit catches up.
            isExpanded = hovering
        }
        .onDrop(of: NotchDropHandling.types, isTargeted: $isDropTargeted) { providers in
            guard !providers.isEmpty else { return false }
            Log.store.debug("shelf onDrop FIRED (\(providers.count) providers)")
            Task { @MainActor in
                let ok = await NotchDropHandling.handle(providers, store: store)
                if ok {
                    playAcceptedPop()
                    onDropAccepted?()
                }
            }
            return true
        }
        .onChange(of: isDropTargeted) { _, targeted in
            Log.store.debug("shelf isDropTargeted=\(targeted)")
            onDropHoverChange?(targeted)
        }
        .contextMenu {
            Button("Capture Screenshot") { onCapture?() }
            if let latest = store.entries.first {
                Button("Copy Latest for \(store.preferences.activeAgent.displayName)") {
                    onCopyLatest?()
                }
                Button("Quick Look Latest") {
                    onQuickLookLatest?()
                }
                .disabled(!FileManager.default.fileExists(atPath: latest.url(in: store.folderURL).path))
            }
        }
        .animation(Motion.notchOpen, value: isExpanded)
        .animation(Motion.easeOut, value: showingDropZone)
        .animation(Motion.shelfItem, value: store.entries.map(\.id))
        .animation(Motion.shelfItem, value: acceptedPop)
    }

    private func playAcceptedPop() {
        acceptedPop = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            acceptedPop = false
        }
    }

    private var emptyDropHint: some View {
        Label("Drop images here", systemImage: "square.and.arrow.down")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.65))
            .padding(.horizontal, 4)
    }

    private var shelf: some View {
        HStack(spacing: 8) {
            ForEach(visibleEntries) { entry in
                ThumbnailView(entry: entry)
                    .transition(Motion.transition(Motion.thumbnail, reduceMotion: reduceMotion))
            }
            if !isExpanded && store.entries.count > visibleEntries.count {
                Text("+\(store.entries.count - visibleEntries.count)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .contentTransition(.numericText())
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 28)
            }
        }
    }

    private var visibleEntries: [ScreenshotEntry] {
        let limit = isExpanded ? maxVisible : 3
        return Array(store.entries.prefix(limit))
    }
}
