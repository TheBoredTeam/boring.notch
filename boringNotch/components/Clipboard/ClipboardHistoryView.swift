//
//  ClipboardHistoryView.swift
//  boringNotch
//
//  Created on 2026-04-13.
//

import SwiftUI

struct ClipboardHistoryView: View {
    @StateObject private var clipboardManager = ClipboardHistoryManager.shared
    @State private var copiedItemID: UUID?

    var body: some View {
        Group {
            if clipboardManager.items.isEmpty {
                emptyState
            } else {
                clipboardList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clipboard")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white, .gray)
                .imageScale(.large)
                .font(.title)

            Text("No clipboard history")
                .foregroundStyle(.gray)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.medium)

            Text("Copy something to get started")
                .foregroundStyle(.gray.opacity(0.6))
                .font(.caption)
        }
    }

    private var clipboardList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Clipboard History")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    withAnimation(.smooth) {
                        clipboardManager.clearHistory()
                    }
                } label: {
                    Text("Clear")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.bottom, 8)

            ScrollView(.vertical) {
                VStack(spacing: 6) {
                    ForEach(clipboardManager.items) { item in
                        ClipboardItemRow(
                            item: item,
                            isCopied: copiedItemID == item.id
                        ) {
                            clipboardManager.copyAndPaste(item)
                            withAnimation(.easeInOut(duration: 0.2)) {
                                copiedItemID = item.id
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                withAnimation {
                                    if copiedItemID == item.id {
                                        copiedItemID = nil
                                    }
                                }
                            }
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .padding()
    }
}

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let isCopied: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                itemIcon

                VStack(alignment: .leading, spacing: 2) {
                    itemPreview
                    Text(item.timestamp, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.gray.opacity(0.7))
                }

                Spacer()

                if isCopied {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isCopied ? Color.green.opacity(0.1) : Color.white.opacity(0.05))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    @ViewBuilder
    private var itemIcon: some View {
        switch item.kind {
        case .image(let image):
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        default:
            Image(systemName: item.icon)
                .font(.system(size: 14))
                .foregroundStyle(.gray)
                .frame(width: 28, height: 28)
        }
    }

    @ViewBuilder
    private var itemPreview: some View {
        switch item.kind {
        case .text:
            Text(item.preview)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(2)
        case .image:
            Text("Image")
                .font(.caption)
                .foregroundStyle(.white)
        case .fileURL:
            Text(item.preview)
                .font(.caption)
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }
}
