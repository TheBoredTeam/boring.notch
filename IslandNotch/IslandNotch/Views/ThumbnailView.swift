//  ThumbnailView.swift
//  IslandNotch
//
//  Purpose: One screenshot thumbnail. Left-click copies the payload (with a
//           "Copied" flash); right-click offers Quick Look / Reveal / Copy.
//  Layer: View

import AppKit
import SwiftUI

struct ThumbnailView: View {
    let entry: ScreenshotEntry
    @Environment(ScreenshotStore.self) private var store

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var image: NSImage?
    @State private var isHovered = false
    private let side: CGFloat = 56

    private var url: URL { entry.url(in: store.folderURL) }
    private var justCopied: Bool { store.lastCopiedFileID == entry.id }

    private var scale: CGFloat {
        if reduceMotion { return 1 }
        return isHovered ? 1.05 : 1
    }

    var body: some View {
        Button {
            store.copyToClipboard(entry)
        } label: {
            thumbnailContent
        }
        .buttonStyle(ThumbnailButtonStyle())
        .acceptClickThrough()
        .help("Left-click: copy • Right-click: more")
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Quick Look") { QuickLookService.shared.preview(url) }
            Button("Copy for \(store.preferences.activeAgent.displayName)") {
                store.copyToClipboard(entry)
            }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            Divider()
            Button("Delete", role: .destructive) {
                Task { await store.delete(entry) }
            }
        }
        .animation(Motion.hover, value: isHovered)
        .animation(Motion.shelfItem, value: justCopied)
        .animation(Motion.easeOut, value: image != nil)
        .task(id: entry.id) { await loadImage() }
    }

    private var thumbnailContent: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.25))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(Motion.transition(.opacity, reduceMotion: reduceMotion))
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
            if justCopied {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.black.opacity(0.45))
                    .overlay {
                        Label("Copied", systemImage: "checkmark.circle.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .labelStyle(.iconOnly)
                            .imageScale(.large)
                    }
                    .transition(Motion.transition(Motion.overlay, reduceMotion: reduceMotion))
            }

            if isHovered {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            Task { await store.delete(entry) }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(.black.opacity(0.55)))
                        }
                        .buttonStyle(.plain)
                        .acceptClickThrough()
                        .help("Delete screenshot")
                    }
                    Spacer()
                }
                .padding(4)
                .transition(Motion.transition(
                    .scale(scale: 0.92).combined(with: .opacity), reduceMotion: reduceMotion
                ))
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(isHovered ? 0.28 : 0.12), lineWidth: 1)
        )
        .scaleEffect(scale)
        .contentShape(Rectangle())
    }

    private func loadImage() async {
        let fileURL = url
        let data = await Task.detached(priority: .utility) {
            try? Data(contentsOf: fileURL)
        }.value
        if let data { image = NSImage(data: data) }
    }
}

/// Press scale on the thumbnail button; hover scale stays on the label wrapper.
private struct ThumbnailButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(
                configuration.isPressed && !reduceMotion ? 0.96 : 1,
                anchor: .center
            )
            .animation(Motion.press, value: configuration.isPressed)
    }
}
