//
//  ClipboardView.swift
//  boringNotch
//
//  Created by boringNotch contributors on 2026-04-19.
//

import SwiftUI

struct ClipboardView: View {
    @ObservedObject var clipboardManager = ClipboardManager.shared
    @State private var copiedItemID: UUID?

    var body: some View {
        VStack(spacing: 8) {
            // Search bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.gray)
                    .font(.caption)
                TextField("Search clipboard...", text: $clipboardManager.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.caption)
                if !clipboardManager.searchQuery.isEmpty {
                    Button {
                        clipboardManager.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.gray)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .secondarySystemFill).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            if clipboardManager.filteredItems.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(clipboardManager.filteredItems) { item in
                            ClipboardItemRow(
                                item: item,
                                isCopied: copiedItemID == item.id,
                                onSelect: {
                                    clipboardManager.selectItem(item)
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        copiedItemID = item.id
                                    }
                                    // Reset after brief feedback
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                        withAnimation {
                                            copiedItemID = nil
                                        }
                                    }
                                },
                                onPin: {
                                    withAnimation(.smooth) {
                                        clipboardManager.togglePin(item)
                                    }
                                },
                                onDelete: {
                                    withAnimation(.smooth) {
                                        clipboardManager.removeItem(item)
                                    }
                                }
                            )
                        }
                    }
                }
            }

            // Footer
            HStack {
                Text("\(clipboardManager.items.count) items")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if !clipboardManager.items.isEmpty {
                    Button("Clear") {
                        withAnimation(.smooth) {
                            clipboardManager.clearHistory()
                        }
                    }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: "clipboard")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(
                clipboardManager.searchQuery.isEmpty
                    ? "Clipboard history is empty" : "No matching items"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Text("Copy something to get started")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let isCopied: Bool
    let onSelect: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                // Source app icon
                if let icon = item.sourceAppIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "app")
                        .frame(width: 16, height: 16)
                        .foregroundStyle(.secondary)
                }

                // Content preview
                contentPreview
                    .lineLimit(2)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Pin indicator
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundColor(.effectiveAccent)
                }

                // Copied feedback
                if isCopied {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                        .transition(.scale.combined(with: .opacity))
                }

                // Time ago
                Text(item.timestamp.timeAgo())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovering ? Color.white.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button { onSelect() } label: {
                Label("Copy to Clipboard", systemImage: "doc.on.clipboard")
            }
            Button { onPin() } label: {
                Label(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin")
            }
            Divider()
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var contentPreview: some View {
        switch item.type {
        case .text:
            Text(item.textContent ?? "")
        case .image:
            if let image = item.imageContent {
                HStack(spacing: 4) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    Text("Image (\(Int(image.size.width))x\(Int(image.size.height)))")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Image")
            }
        case .fileURL:
            HStack(spacing: 4) {
                Image(systemName: "doc")
                    .foregroundStyle(.secondary)
                Text(item.fileURL?.lastPathComponent ?? "File")
            }
        }
    }
}

// MARK: - Time Ago Helper
extension Date {
    func timeAgo() -> String {
        let interval = Date().timeIntervalSince(self)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }
}
