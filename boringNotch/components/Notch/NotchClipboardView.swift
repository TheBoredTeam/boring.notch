import SwiftUI
import Defaults
import AppKit

struct NotchClipboardView: View {
    @ObservedObject private var clipboard = ClipboardManager.shared
    @Default(.enableClipboardHistory) private var historyEnabled
    @State private var selection = Set<UUID>()
    @State private var recentlyCopiedID: UUID?
    @State private var copyResetWorkItem: DispatchWorkItem?

    private var items: [ClipboardItem] {
        clipboard.filteredItems
    }

    var body: some View {
        content
            .overlay(disabledOverlay)
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
    }

    private var content: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(items) { item in
                    ClipboardCard(
                        item: item,
                        isSelected: selection.contains(item.id),
                        allowEditing: historyEnabled,
                        isCopied: recentlyCopiedID == item.id,
                        onDelete: {
                            clipboard.delete(id: item.id)
                            selection.remove(item.id)
                        },
                        onTogglePin: {
                            clipboard.toggleFavorite(for: item.id)
                        },
                        onCopy: {
                            handleCopy(item)
                        }
                    )
                    .onTapGesture {
                        handleSelection(for: item.id, commandPressed: NSEvent.modifierFlags.contains(.command))
                        handleCopy(item)
                    }
                    .contextMenu {
                        Button(item.isFavorite ? "Unpin" : "Pin") {
                            clipboard.toggleFavorite(for: item.id)
                        }
                        Button("Copy") {
                            clipboard.recopyToPasteboard(item)
                        }
                        Divider()
                        Button(role: .destructive) {
                            clipboard.delete(id: item.id)
                            selection.remove(item.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .disabled(!historyEnabled)
        .overlay(alignment: .center) {
            if items.isEmpty {
                emptyState
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(historyEnabled ? "Copy something to start building history." : "Clipboard history is disabled.")
                .foregroundStyle(.secondary)
            if !historyEnabled {
                Button("Enable history") {
                    historyEnabled = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    private var disabledOverlay: some View {
        Group {
            if !historyEnabled {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.black.opacity(0.45))
            }
        }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 180, maximum: .infinity), spacing: 8, alignment: .top)]
    }

    private func handleSelection(for id: UUID, commandPressed: Bool) {
        guard historyEnabled else { return }
        if commandPressed {
            if selection.contains(id) {
                selection.remove(id)
            } else {
                selection.insert(id)
            }
        } else {
            selection = [id]
        }
    }

    private func deleteSelection() {
        guard !selection.isEmpty else { return }
        clipboard.delete(ids: selection)
        selection.removeAll()
    }

    private func handleCopy(_ item: ClipboardItem) {
        clipboard.recopyToPasteboard(item)
        recentlyCopiedID = item.id

        copyResetWorkItem?.cancel()
        let workItem = DispatchWorkItem { [recentlyCopiedIDSetter = { self.recentlyCopiedID = $0 }] in
            DispatchQueue.main.async {
                recentlyCopiedIDSetter(nil)
            }
        }
        copyResetWorkItem = workItem
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1.5, execute: workItem)
    }
}

private struct ClipboardCard: View {
    let item: ClipboardItem
    let isSelected: Bool
    let allowEditing: Bool
    let isCopied: Bool
    let onDelete: () -> Void
    let onTogglePin: () -> Void
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            preview

            HStack(spacing: 8) {
                Spacer()
                Button(action: onCopy) {
                    Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(isCopied ? Color.green : Color.primary)
                }
                .buttonStyle(.plain)
                .help(isCopied ? "Copied" : "Copy")

                Button(action: onTogglePin) {
                    Image(systemName: item.isFavorite ? "pin.fill" : "pin")
                        .font(.caption)
                        .foregroundStyle(item.isFavorite ? .yellow : .primary)
                }
                .buttonStyle(.plain)
                .help(item.isFavorite ? "Unpin" : "Pin")

                if allowEditing {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Delete")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 180, height: 100, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(isSelected ? 0.16 : 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.white.opacity(0.08), lineWidth: isSelected ? 2 : 1)
        )
    }

    private var preview: some View {
        Group {
            switch item.kind {
            case .text, .html:
                if let string = String(data: item.data, encoding: .utf8) {
                    Text(string)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                }
            case .rtf:
                Text("Rich text snippet")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
            case .image:
                if let image = NSImage(data: item.data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            case .fileURL:
                Text(item.preview)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
        }
    }

    private var fallbackPreview: some View {
        Text(item.preview)
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}

private extension ClipboardKind {
    var title: String {
        switch self {
        case .text: return "Text"
        case .image: return "Image"
        case .fileURL: return "File"
        case .rtf: return "RTF"
        case .html: return "HTML"
        }
    }

    var iconName: String {
        switch self {
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .fileURL: return "doc"
        case .rtf: return "doc.richtext"
        case .html: return "curlybraces"
        }
    }
}
