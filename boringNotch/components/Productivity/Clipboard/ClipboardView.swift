//
//  ClipboardView.swift
//  boringNotch
//
//  Clipboard history tab: search, filter, click to copy, ⌥-click to delete.
//

import SwiftUI

struct ClipboardView: View {
    @ObservedObject var clipboard = ClipboardManager.shared
    @State private var searchText = ""
    @State private var filter: ClipboardItem.Kind?
    @State private var copiedID: UUID?

    private var filteredItems: [ClipboardItem] {
        clipboard.items.filter { item in
            (filter == nil || item.kind == filter)
                && (searchText.isEmpty || item.searchableText.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            toolbar
            if filteredItems.isEmpty {
                emptyState
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(filteredItems) { item in
                            ClipboardCard(item: item, isCopied: copiedID == item.id)
                                .onTapGesture {
                                    if NSEvent.modifierFlags.contains(.option) {
                                        withAnimation(.smooth) { clipboard.delete(item) }
                                    } else {
                                        clipboard.copy(item)
                                        withAnimation(.smooth) { copiedID = item.id }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                            if copiedID == item.id {
                                                withAnimation(.smooth) { copiedID = nil }
                                            }
                                        }
                                    }
                                }
                                .contextMenu {
                                    Button("Copy") { clipboard.copy(item) }
                                    Button("Delete", role: .destructive) { clipboard.delete(item) }
                                }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.gray)
                TextField("Search clipboard", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .frame(maxWidth: 200)

            filterButton(nil, icon: "square.grid.2x2", help: "All")
            filterButton(.text, icon: "text.alignleft", help: "Text")
            filterButton(.link, icon: "link", help: "Links")
            filterButton(.image, icon: "photo", help: "Images")
            filterButton(.file, icon: "doc", help: "Files")

            Spacer()

            if !clipboard.items.isEmpty {
                Button {
                    withAnimation(.smooth) { clipboard.clearAll() }
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.gray)
                }
                .buttonStyle(.plain)
                .help("Clear history")
            }
        }
        .font(.caption)
    }

    private func filterButton(_ kind: ClipboardItem.Kind?, icon: String, help: String) -> some View {
        Button {
            withAnimation(.smooth) { filter = kind }
        } label: {
            Image(systemName: icon)
                .frame(width: 22, height: 22)
                .foregroundStyle(filter == kind ? .white : .gray)
                .background(Circle().fill(filter == kind ? Color.white.opacity(0.15) : .clear))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "doc.on.clipboard")
                .font(.title2)
            Text(clipboard.items.isEmpty ? "Copy something and it shows up here" : "No matching clips")
                .font(.caption)
        }
        .foregroundStyle(.gray)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ClipboardCard: View {
    let item: ClipboardItem
    let isCopied: Bool
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack(spacing: 4) {
                if let bundleID = item.sourceBundleID {
                    AppIcon(for: bundleID)
                        .resizable()
                        .frame(width: 12, height: 12)
                }
                Text(isCopied ? "Copied" : item.date.formatted(.relative(presentation: .named)))
                    .lineLimit(1)
                    .foregroundStyle(isCopied ? .green : .gray)
            }
            .font(.system(size: 9))
        }
        .padding(8)
        .frame(width: 130, height: 96)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(isHovering ? 0.12 : 0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isCopied ? Color.green.opacity(0.6) : .clear, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onHover { isHovering = $0 }
        .help("Click to copy · ⌥-click to delete")
    }

    @ViewBuilder
    private var preview: some View {
        switch item.kind {
        case .text:
            Text(item.text ?? "")
                .font(.system(size: 11))
                .foregroundStyle(.white)
                .lineLimit(4)
        case .link:
            VStack(alignment: .leading, spacing: 2) {
                Image(systemName: "link")
                    .foregroundStyle(Color.accentColor)
                Text(URL(string: item.text ?? "")?.host() ?? item.text ?? "")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Text(item.text ?? "")
                    .font(.system(size: 9))
                    .foregroundStyle(.gray)
                    .lineLimit(2)
            }
            .foregroundStyle(.white)
        case .image:
            if let data = item.imageData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        case .file:
            let paths = item.filePaths ?? []
            HStack(spacing: 6) {
                if let first = paths.first {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: first))
                        .resizable()
                        .frame(width: 28, height: 28)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(paths.first.map { ($0 as NSString).lastPathComponent } ?? "")
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(2)
                    if paths.count > 1 {
                        Text("+\(paths.count - 1) more")
                            .font(.system(size: 9))
                            .foregroundStyle(.gray)
                    }
                }
            }
            .foregroundStyle(.white)
        }
    }
}
