//
//  ClipboardHistoryView.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import ImageIO
import SwiftUI

struct ClipboardHistoryView: View {
    @ObservedObject var manager: ClipboardHistoryManager
    @State private var query = ""
    @State private var selectedID: UUID?
    @State private var selectedIDs: Set<UUID> = []
    @State private var tileFrames: [UUID: CGRect] = [:]
    @State private var isPointerInteracting = false
    @State private var copiedID: UUID?
    @State private var previewID: UUID?
    @State private var copyFailed = false
    @State private var hostWindow: BoringNotchSkyLightWindow?
    @State private var hasKeyboardSession = false
    @State private var dragFailed = false
    @FocusState private var searchIsFocused: Bool
    @FocusState private var gridIsFocused: Bool

    init(manager: ClipboardHistoryManager? = nil) {
        self.manager = manager ?? .shared
    }

    private var results: [ClipboardHistoryItem] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return manager.items.filter { $0.matches(search) }
    }

    private var previewItem: ClipboardHistoryItem? {
        manager.items.first { $0.id == previewID }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let item = previewItem {
                ClipboardHistoryPreview(
                    item: item,
                    isCopied: copiedID == item.id,
                    copyFailed: copyFailed,
                    back: { previewID = nil },
                    copy: { copy(item) },
                    delete: {
                        manager.delete(item)
                        previewID = nil
                    }
                )
                .id(item.id)
            } else {
                VStack(spacing: 9) {
                    controls
                    if results.isEmpty {
                        emptyState
                    } else {
                        history
                    }
                    footer
                }
            }
        }
        .frame(height: 236)
        .background(ClipboardWindowAccessor { hostWindow = $0 })
        .onChange(of: hostWindow) { _, window in
            if hasKeyboardSession { window?.wantsKeyForTextInput = true }
        }
        .onChange(of: searchIsFocused) { _, focused in
            if focused { beginKeyboardSession() }
        }
        .onChange(of: query) { select(results.first.map { [$0.id] } ?? [], focus: false) }
        .onChange(of: manager.items.map(\.id)) {
            selectedIDs.formIntersection(Set(results.map(\.id)))
            if !results.contains(where: { $0.id == selectedID }) {
                selectedID = results.first?.id
            }
            if previewItem == nil { previewID = nil }
        }
        .onKeyPress(.downArrow) {
            guard previewID == nil else { return .ignored }
            if searchIsFocused {
                searchIsFocused = false
                gridIsFocused = true
                select(selectedID.map { [$0] } ?? results.first.map { [$0.id] } ?? [])
            } else {
                moveSelection(by: 4)
            }
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard previewID == nil else { return .ignored }
            moveSelection(by: -4)
            return .handled
        }
        .onKeyPress(.leftArrow) {
            guard gridIsFocused, previewID == nil else { return .ignored }
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard gridIsFocused, previewID == nil else { return .ignored }
            moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.return) {
            guard gridIsFocused, previewID == nil else { return .ignored }
            copySelected()
            return .handled
        }
        .onKeyPress(.space) {
            guard gridIsFocused, let item = results.first(where: { $0.id == selectedID }) else { return .ignored }
            preview(item)
            return .handled
        }
        .onExitCommand {
            if previewID != nil {
                previewID = nil
            } else {
                select([])
                searchIsFocused = false
                gridIsFocused = false
                endKeyboardSession()
            }
        }
        .onDisappear {
            searchIsFocused = false
            gridIsFocused = false
            endKeyboardSession()
        }
        .task(id: copiedID) {
            guard copiedID != nil else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            copiedID = nil
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.white.opacity(0.4))
                TextField("Search, or type an app name", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchIsFocused)
                    .simultaneousGesture(TapGesture().onEnded {
                        beginKeyboardSession()
                        searchIsFocused = true
                    })
                    .onSubmit { copySelected() }
                    .accessibilityLabel("Search clipboard history")
                if !query.isEmpty {
                    Button {
                        query = ""
                        searchIsFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                    .accessibilityLabel("Clear search")
                }
            }
            .font(.system(size: 11))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(.white.opacity(0.07), in: Capsule())

            Button {
                manager.setPaused(!manager.isPaused)
            } label: {
                Image(systemName: manager.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(manager.isPaused ? .orange : .white.opacity(0.65))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
            .help(manager.isPaused ? "Resume clipboard capture" : "Pause clipboard capture")
            .accessibilityLabel(manager.isPaused ? "Resume clipboard capture" : "Pause clipboard capture")

            Button("Clear") {
                manager.clearHistory()
                copiedID = nil
                copyFailed = false
            }
            .font(.system(size: 10, weight: .medium))
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(manager.items.isEmpty ? 0.25 : 0.7))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(.white.opacity(0.07), in: Capsule())
            .disabled(manager.items.isEmpty)
            .help("Delete all clipboard history; the current clipboard stays available")
        }
    }

    private var history: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 8), count: 4), spacing: 8) {
                    ForEach(results) { item in
                        ClipboardHistoryTile(
                            item: item,
                            isSelected: selectedIDs.contains(item.id),
                            isCopied: copiedID == item.id,
                            activate: {
                                if selectedIDs.contains(item.id) {
                                    select(selectedIDs.subtracting([item.id]))
                                } else {
                                    copy(item)
                                }
                            },
                            preview: { preview(item) },
                            copy: { copy(item) },
                            delete: { manager.delete(item) }
                        )
                        .id(item.id)
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: ClipboardTileFrames.self,
                                    value: [item.id: geometry.frame(in: .named("clipboardGrid"))]
                                )
                            }
                        }
                    }
                }
            }
            .coordinateSpace(name: "clipboardGrid")
            .onPreferenceChange(ClipboardTileFrames.self) { tileFrames = $0 }
            .overlay {
                ClipboardSelectionInteraction(
                    items: results,
                    tileFrames: tileFrames,
                    selectedIDs: selectedIDs,
                    selectionChanged: { select($0) },
                    clicked: { copy($0) },
                    interactionChanged: { active in
                        isPointerInteracting = active
                        if active {
                            dragFailed = false
                            SharingStateManager.shared.beginInteraction()
                        } else {
                            SharingStateManager.shared.endInteraction()
                        }
                    },
                    dragFailed: { dragFailed = true }
                )
            }
            .scrollIndicators(.automatic)
            .focusable()
            .focused($gridIsFocused)
            .focusEffectDisabled()
            .onAppear {
                if let selectedID { proxy.scrollTo(selectedID) }
            }
            .onChange(of: selectedID) {
                if !isPointerInteracting, let selectedID { proxy.scrollTo(selectedID) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 7) {
            Image(systemName: manager.items.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.white.opacity(0.3))
            Text(manager.items.isEmpty ? (manager.isPaused ? "Clipboard capture is paused" : "Your next copy starts here") : "No matching copies")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
            Text(manager.items.isEmpty ? "Text, links and images appear as you copy them." : "Try a different word or app name.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(manager.isPaused ? .orange : .white.opacity(0.35))
                .frame(width: 4, height: 4)
            Text(manager.isPaused ? "Capture paused" : "Stored until quit")
            Spacer()
            Text(footerMessage)
                .foregroundStyle(copyFailed || dragFailed ? .orange : .white.opacity(0.4))
        }
        .font(.system(size: 9))
        .foregroundStyle(.white.opacity(0.4))
        .accessibilityElement(children: .combine)
        .help("""
        History stays in memory. Dragging images creates temporary files for receiving apps; \
        mixed selections include text as an attachment. Copies marked sensitive and supported \
        password-manager apps are skipped. Unmarked secrets can still appear; pause capture before copying them.
        """)
    }

    private func beginKeyboardSession() {
        hostWindow?.wantsKeyForTextInput = true
        guard !hasKeyboardSession else { return }
        hasKeyboardSession = true
        // Key-window changes can cause a transient hover exit during the click.
        SharingStateManager.shared.beginInteraction()
    }

    private func endKeyboardSession() {
        guard hasKeyboardSession else { return }
        hasKeyboardSession = false
        hostWindow?.wantsKeyForTextInput = false
        if let window = hostWindow, !window.canBecomeKey, window.isKeyWindow {
            window.makeFirstResponder(nil)
            window.resignKey()
        }
        SharingStateManager.shared.endInteraction()
    }

    private var footerMessage: String {
        if dragFailed { return "Could not prepare files. Try again." }
        if copyFailed { return "Copy failed. Try again." }
        if selectedIDs.count > 1 { return "\(selectedIDs.count) selected · Drag out to drop" }
        if copiedID != nil { return "Copied · paste with ⌘V" }
        return "Drag across tiles to select · Drag out to drop"
    }

    private func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        let current = results.firstIndex { $0.id == selectedID } ?? (offset > 0 ? -offset : results.count - offset - 1)
        select([results[min(max(current + offset, 0), results.count - 1)].id])
    }

    private func copySelected() {
        guard let item = results.first(where: { $0.id == selectedID }) ?? results.first else { return }
        copy(item)
    }

    private func select(_ ids: Set<UUID>, focus: Bool = true) {
        selectedIDs = ids
        selectedID = results.first { ids.contains($0.id) }?.id
        if focus, !ids.isEmpty {
            searchIsFocused = false
            gridIsFocused = true
        }
    }

    private func preview(_ item: ClipboardHistoryItem) {
        select([item.id])
        previewID = item.id
        searchIsFocused = false
        gridIsFocused = false
        copyFailed = false
    }

    private func copy(_ item: ClipboardHistoryItem) {
        select([item.id])
        copyFailed = !manager.copy(item)
        copiedID = copyFailed ? nil : item.id
    }
}

private struct ClipboardHistoryTile: View {
    let item: ClipboardHistoryItem
    let isSelected: Bool
    let isCopied: Bool
    let activate: () -> Void
    let preview: () -> Void
    let copy: () -> Void
    let delete: () -> Void
    @State private var isHovered = false

    var body: some View {
        RoundedRectangle(cornerRadius: 11)
            .fill(.white.opacity(isHovered ? 0.18 : 0.13))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    ZStack {
                        Button(action: activate) {
                            tileContent(size: geometry.size)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(isSelected ? "Click to deselect; drag to move the selection" : "Copy from \(item.source.name); drag across cards to select")
                        .accessibilityLabel("\(item.content.preview), from \(item.source.name). \(isSelected ? "Deselect" : "Copy")")

                        VStack(spacing: 0) {
                            metadata
                            Spacer(minLength: 0)
                            actions
                        }
                        .padding(7)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(isSelected ? Color.accentColor : .white.opacity(0.06), lineWidth: isSelected ? 2 : 1)
                    .allowsHitTesting(false)
            }
            .onHover { isHovered = $0 }
            .contextMenu {
                Button("Preview", action: preview)
                Button("Copy", action: copy)
                Button("Delete from History", role: .destructive, action: delete)
            }
    }

    @ViewBuilder
    private func tileContent(size: CGSize) -> some View {
        switch item.content {
        case .image(_, _, let thumbnail):
            Image(nsImage: thumbnail)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .padding(.horizontal, 7)
                .padding(.top, 26)
                .padding(.bottom, 35)
                .frame(width: size.width, height: size.height)
        case .text(let value, _):
            Text(String(value.prefix(600)))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineSpacing(2)
                .lineLimit(6)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 10)
                .padding(.top, 30)
                .padding(.bottom, 35)
        }
    }

    private var metadata: some View {
        HStack(spacing: 4) {
            ClipboardSourceIcon(source: item.source)
                .frame(width: 13, height: 13)
            Text(item.source.name)
                .font(.system(size: 8, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(item.capturedAt, style: .time)
                .font(.system(size: 7, design: .monospaced))
                .fixedSize()
        }
        .foregroundStyle(.white.opacity(0.75))
        .allowsHitTesting(false)
    }

    private var actions: some View {
        HStack(spacing: 4) {
            Button(action: preview) {
                Label("Preview", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 9, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .help("Preview the complete copy")
            Button(action: copy) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(isCopied ? .green : .white)
                    .frame(width: 22)
            }
            .accessibilityLabel(isCopied ? "Copied" : "Copy")
            .help(isCopied ? "Copied · paste with ⌘V" : "Copy")
            Button(action: delete) {
                Image(systemName: "trash")
                    .frame(width: 22)
            }
            .accessibilityLabel("Delete copy from history")
            .help("Delete copy from history")
        }
        .font(.system(size: 10))
        .buttonStyle(ClipboardTileActionStyle())
    }
}

private struct ClipboardTileActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(height: 24)
            .foregroundStyle(.white.opacity(0.9))
            .background(.black.opacity(configuration.isPressed ? 0.7 : 0.4), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct ClipboardHistoryPreview: View {
    let item: ClipboardHistoryItem
    let isCopied: Bool
    let copyFailed: Bool
    let back: () -> Void
    let copy: () -> Void
    let delete: () -> Void
    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button(action: back) {
                    Label("Back", systemImage: "chevron.left")
                }
                .help("Back to clipboard grid")
                ClipboardSourceIcon(source: item.source)
                    .frame(width: 15, height: 15)
                Text(item.source.name)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Button(action: copy) {
                    Label(isCopied ? "Copied" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(isCopied ? .green : .white)
                }
                Button(action: delete) {
                    Label("Delete", systemImage: "trash")
                }
            }
            .font(.system(size: 11, weight: .medium))
            .buttonStyle(.plain)
            .frame(height: 28)

            previewContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack {
                Text(item.capturedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                Spacer()
                Text(copyFailed ? "Copy failed. Try again." : (isCopied ? "Copied · paste with ⌘V" : "Copy, then paste with ⌘V"))
                    .foregroundStyle(copyFailed ? .orange : .white.opacity(0.4))
            }
            .font(.system(size: 9))
            .foregroundStyle(.white.opacity(0.4))
        }
        .task(id: item.id) { loadPreviewImage() }
    }

    @ViewBuilder
    private var previewContent: some View {
        switch item.content {
        case .image(_, _, let thumbnail):
            Image(nsImage: image ?? thumbnail)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .padding(4)
                .accessibilityLabel("Full image preview")
        case .text(let value, _):
            ScrollView(.vertical) {
                Text(value)
                    .font(.system(size: 12))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(12)
            }
        }
    }

    private func loadPreviewImage() {
        guard case .image(let data, _, _) = item.content,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let preview = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 1200,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return }
        // Retina-sized preview; the original bytes stay ready for Copy.
        image = NSImage(cgImage: preview, size: .zero)
    }
}

private struct ClipboardSourceIcon: View {
    let source: ClipboardSourceApplication

    var body: some View {
        if let bundleIdentifier = source.bundleIdentifier {
            appIcon(for: bundleIdentifier)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "doc.on.clipboard")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white.opacity(0.5))
                .padding(2)
        }
    }
}

/// Resolves this view's panel without changing focus on hover or tab selection.
private struct ClipboardWindowAccessor: NSViewRepresentable {
    let onResolve: (BoringNotchSkyLightWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onResolve(view.window as? BoringNotchSkyLightWindow) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
