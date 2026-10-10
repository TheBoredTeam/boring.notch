//
//  ClipboardHistoryView.swift
//  boringNotch
//
//  Created by Claude on 2026-07-05.
//

import AppKit
import Defaults
import SwiftUI

struct ClipboardHistoryView: View {
    @EnvironmentObject var vm: BoringViewModel
    @StateObject private var viewModel = ClipboardHistoryViewModel.shared
    private let spacing: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white.opacity(0.1), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .overlay {
                content
                    .padding()
            }
    }

    private var content: some View {
        Group {
            if viewModel.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.on.clipboard")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white, .gray)
                        .imageScale(.large)
                    Text("Copy something to see it here")
                        .foregroundStyle(.gray)
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.medium)
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: spacing) {
                        ForEach(viewModel.items) { item in
                            ClipboardItemCard(item: item) {
                                copy(item)
                            }
                        }
                    }
                }
                .padding(-spacing)
                .scrollIndicators(.never)
            }
        }
    }

    private func copy(_ item: ClipboardItem) {
        viewModel.copyToPasteboard(item)
        if Defaults[.clipboardAutoCloseOnCopy] {
            vm.close()
        }
    }
}

private struct ClipboardItemCard: View {
    let item: ClipboardItem
    let onCopy: () -> Void

    @ObservedObject private var viewModel = ClipboardHistoryViewModel.shared
    @State private var isHovering = false
    @State private var justCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: kindIcon)
                    .font(.caption2)
                    .foregroundStyle(Color.effectiveAccent)
                Text(item.date, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.gray)
                Spacer(minLength: 0)
                if item.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.gray)
                }
            }

            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(8)
        .frame(width: 140)
        .frame(maxHeight: .infinity)
        .background(
            Color(nsColor: .secondarySystemFill).opacity(isHovering ? 1 : 0.6),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay {
            if justCopied {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.6))
                    .overlay {
                        Label("Copied", systemImage: "checkmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                    }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            onCopy()
            withAnimation(.smooth(duration: 0.2)) { justCopied = true }
            Task {
                try? await Task.sleep(for: .milliseconds(800))
                withAnimation { justCopied = false }
            }
        }
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .contextMenu {
            Button("Copy") { onCopy() }
            Button(item.pinned ? "Unpin" : "Pin") {
                viewModel.togglePin(item)
            }
            Divider()
            Button("Delete", role: .destructive) {
                viewModel.delete(item)
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch item.kind {
        case .image:
            if let fileName = item.imageFileName,
               let image = ClipboardPersistenceService.shared.loadImage(fileName: fileName)
            {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.gray)
            }
        case .text, .link, .fileURL:
            Text(item.previewText)
                .font(.caption)
                .foregroundStyle(item.kind == .link ? Color.effectiveAccent : .white)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
        }
    }

    private var kindIcon: String {
        switch item.kind {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .image: return "photo"
        case .fileURL: return "doc"
        }
    }
}

#Preview {
    ClipboardHistoryView()
        .environmentObject(BoringViewModel())
        .frame(width: 500, height: 160)
        .background(.black)
}
