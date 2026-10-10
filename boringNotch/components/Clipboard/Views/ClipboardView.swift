//
//  ClipboardView.swift
//  boringNotch
//

import AppKit
import Defaults
import SwiftUI

struct ClipboardView: View {
    @EnvironmentObject var vm: BoringViewModel
    @StateObject private var store = ClipboardStore.shared
    @Default(.clipboardHistoryEnabled) private var isEnabled

    /// Cards are wider than the Shelf's 105pt because text is the dominant kind here and four
    /// readable lines is the whole point.
    private let cardWidth: CGFloat = 150
    private let spacing: CGFloat = 8

    @State private var confirmingClear = false
    @State private var clearConfirmTask: Task<Void, Never>?

    var body: some View {
        panel
            .transaction { $0.animation = vm.animation }
    }

    private var panel: some View {
        RoundedRectangle(cornerRadius: 16)
            // Solid fill rather than the Shelf's dashed stroke: dashes read as "drop target",
            // and this panel accepts no drops.
            .fill(Color.white.opacity(0.05))
            .overlay {
                content
                    .padding(12)
            }
            .overlay(alignment: .topTrailing) {
                if !store.isEmpty {
                    clearAllButton
                        .padding(8)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if !isEnabled {
            disabledState
        } else if store.isEmpty {
            emptyState
        } else {
            ScrollView(.horizontal) {
                LazyHStack(spacing: spacing) {
                    ForEach(store.items) { item in
                        ClipboardItemCard(item: item, width: cardWidth)
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clipboard")
                .symbolVariant(.fill)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white, .gray)
                .imageScale(.large)

            Text("Copied items will appear here")
                .foregroundStyle(.gray)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.medium)
        }
    }

    private var disabledState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clipboard")
                .symbolVariant(.fill)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white, .gray)
                .imageScale(.large)

            Text("Clipboard history is off")
                .foregroundStyle(.gray)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.medium)

            Button("Open Settings") {
                DispatchQueue.main.async {
                    SettingsWindowController.shared.showWindow()
                }
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(Color.effectiveAccent)
        }
    }

    /// Two-stage inline confirm. A `.confirmationDialog` would be orphaned here — the notch
    /// closes on mouse-exit and would leave the dialog stranded.
    private var clearAllButton: some View {
        Button {
            if confirmingClear {
                clearConfirmTask?.cancel()
                confirmingClear = false
                ClipboardActionService.clearAll()
            } else {
                confirmingClear = true
                clearConfirmTask?.cancel()
                clearConfirmTask = Task {
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    withAnimation { confirmingClear = false }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "trash")
                Text(confirmingClear ? "Confirm?" : "Clear All")
            }
            .font(.caption2)
            .foregroundStyle(confirmingClear ? Color.red : Color.gray)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: confirmingClear)
    }
}

// MARK: - Card

private struct ClipboardItemCard: View {
    let item: ClipboardItem
    let width: CGFloat

    @Default(.enableHaptics) private var enableHaptics

    @State private var thumbnail: NSImage?
    @State private var isHovering = false
    @State private var justCopied = false
    @State private var copyFeedback = false
    @State private var resetCopiedTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            content(for: item.kind)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(8)
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background(background)
        .overlay {
            if justCopied {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.black.opacity(0.55))
                    .overlay {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.effectiveAccent)
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .scaleEffect(justCopied ? 0.96 : 1)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovering = hovering }
        }
        .onTapGesture(perform: copy)
        .contextMenu { contextMenu }
        .sensoryFeedback(.success, trigger: copyFeedback)
        .animation(.easeInOut(duration: 0.15), value: justCopied)
        .task(id: item.id) {
            thumbnail = await ClipboardThumbnailCache.shared.thumbnail(for: item)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 4) {
            Image(systemName: item.iconSymbolName)
                .font(.system(size: 10))
                .foregroundStyle(.gray)

            if isHovering {
                Spacer(minLength: 0)
                Button {
                    ClipboardActionService.delete(item)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.gray)
                }
                .buttonStyle(.plain)
            } else {
                Text(item.createdAt, style: .relative)
                    .font(.system(size: 9))
                    .foregroundStyle(.gray)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .frame(height: 14)
    }

    // MARK: Body

    @ViewBuilder
    private func content(for kind: ClipboardItemKind) -> some View {
        switch kind {
        case .text:
            Text(item.previewText)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(4)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)

        case .link(let url):
            VStack(alignment: .leading, spacing: 1) {
                Text(url.host ?? url.absoluteString)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                if !url.path.isEmpty && url.path != "/" {
                    Text(url.path)
                        .font(.system(size: 10))
                        .foregroundStyle(.gray)
                        .lineLimit(2)
                }
            }

        case .image:
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "photo")
                        .imageScale(.large)
                        .foregroundStyle(.gray)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

        case .files(let refs):
            HStack(spacing: 6) {
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "doc").imageScale(.large).foregroundStyle(.gray)
                    }
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 1) {
                    Text(refs.first?.name ?? "")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(2)
                        .truncationMode(.middle)
                    if refs.count > 1 {
                        Text("+\(refs.count - 1) more")
                            .font(.system(size: 9))
                            .foregroundStyle(.gray)
                    }
                }
            }
        }
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.white.opacity(isHovering ? 0.12 : 0.06))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isHovering ? Color.effectiveAccent.opacity(0.6) : .clear,
                        lineWidth: 1
                    )
            }
    }

    // MARK: Context menu

    @ViewBuilder
    private var contextMenu: some View {
        Button("Copy") { copy() }

        if case .link = item.kind {
            Button("Open Link") { ClipboardActionService.openLink(item) }
        }

        if case .files = item.kind {
            Button("Reveal in Finder") { ClipboardActionService.revealInFinder(item) }
            Button("Copy Path") { ClipboardActionService.copyPath(item) }
        }

        Divider()

        Button("Delete", role: .destructive) { ClipboardActionService.delete(item) }
    }

    // MARK: Actions

    /// Deliberately does not reorder the list. Move-to-front would make alternating pastes of
    /// two entries shuffle under the cursor.
    private func copy() {
        ClipboardActionService.copy(item)

        if enableHaptics { copyFeedback.toggle() }

        justCopied = true
        resetCopiedTask?.cancel()
        resetCopiedTask = Task {
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            justCopied = false
        }
    }
}
