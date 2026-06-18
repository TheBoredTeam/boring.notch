//
//  SpotifyQueueView.swift
//  boringNotch
//

import AppKit
import SwiftUI

private enum SpotifyQueuePopoverStyle {
    static let background = Color(white: 0.11)
    static let queueMaxHeight: CGFloat = 220
}

struct SpotifyQueuePopoverContent: View {
    @ObservedObject private var musicManager = MusicManager.shared
    var onSongSelected: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Queue")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                if musicManager.queueAuthState == .authenticated {
                    Button {
                        musicManager.refreshQueue()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                    .disabled(musicManager.isLoadingQueue)
                }
            }

            content
        }
        .frame(width: 280)
        .padding(12)
        .background(SpotifyQueuePopoverStyle.background)
        .colorScheme(.dark)
        .task {
            await musicManager.syncSpotifyQueueAuth()
            if musicManager.queueAuthState == .authenticated {
                musicManager.refreshQueue()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch musicManager.queueAuthState {
        case .unauthenticated:
            unauthenticatedView
        case .authenticating:
            ProgressView("Connecting to Spotify…")
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
        case .authenticated:
            queueListView
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                if musicManager.queueSupported {
                    connectButton
                }
            }
        }
    }

    private var unauthenticatedView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connect Spotify to view your up next queue.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
            if musicManager.queueSupported {
                connectButton
            } else {
                Text("Add a Spotify client ID in the boringNotch target build settings (SPOTIFY_CLIENT_ID), then rebuild.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
    }

    private var connectButton: some View {
        Button("Connect Spotify") {
            musicManager.connectSpotifyQueue()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    }

    @ViewBuilder
    private var queueListView: some View {
        let visibleQueueItems = musicManager.queueItems.reconciledWithCurrentPlayback(
            title: musicManager.songTitle,
            subtitle: musicManager.artistName,
            artworkURL: nil
        )

        if musicManager.isLoadingQueue && visibleQueueItems.isEmpty {
            ProgressView("Syncing queue…")
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(height: SpotifyQueuePopoverStyle.queueMaxHeight)
        } else if let error = musicManager.queueErrorMessage, visibleQueueItems.isEmpty {
            Text(error)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
        } else if visibleQueueItems.isEmpty {
            Text("Queue is empty")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
        } else {
            if let error = musicManager.queueErrorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(visibleQueueItems) { item in
                        SpotifyQueueRowView(item: item) {
                            musicManager.playQueueItem(item)
                            onSongSelected?()
                        }
                    }
                }
            }
            .frame(maxHeight: SpotifyQueuePopoverStyle.queueMaxHeight)
            .overlay(alignment: .topTrailing) {
                if musicManager.isLoadingQueue {
                    syncingQueueBadge
                }
            }
        }
    }

    private var syncingQueueBadge: some View {
        HStack(spacing: 5) {
            ProgressView()
                .controlSize(.small)
            Text("Syncing")
                .font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(SpotifyQueuePopoverStyle.background.opacity(0.9))
        )
        .foregroundStyle(.white.opacity(0.7))
    }
}

private struct SpotifyQueueRowView: View {
    let item: SpotifyQueueItem
    let onPlay: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 10) {
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.subheadline.weight(item.isCurrentlyPlaying ? .semibold : .regular))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if item.isCurrentlyPlaying {
                    Image(systemName: "waveform")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                } else if item.canPlay {
                    Image(systemName: "play.fill")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(isHovering ? 0.9 : 0.45))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(rowBackground)
            )
        }
        .buttonStyle(.plain)
        .disabled(!item.canPlay)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { isHovering = $0 }
    }

    private var rowBackground: Color {
        if item.isCurrentlyPlaying {
            return Color.white.opacity(0.14)
        }
        if isHovering && item.canPlay {
            return Color.white.opacity(0.12)
        }
        return Color.clear
    }

    @ViewBuilder
    private var artwork: some View {
        SpotifyQueueArtworkView(url: item.artworkURL)
    }
}

private struct SpotifyQueueArtworkView: View {
    let url: URL?

    @State private var image: NSImage?

    private static let cache = NSCache<NSURL, NSImage>()

    init(url: URL?) {
        self.url = url
        _image = State(initialValue: url.flatMap { Self.cache.object(forKey: $0 as NSURL) })
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholderArtwork
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: url) {
            await loadImage()
        }
    }

    private var placeholderArtwork: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.white.opacity(0.12))
            .overlay {
                Image(systemName: "music.note")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
    }

    private func loadImage() async {
        guard let url else {
            image = nil
            return
        }

        let cacheKey = url as NSURL
        if let cachedImage = Self.cache.object(forKey: cacheKey) {
            image = cachedImage
            return
        }

        guard let data = try? await ImageService.shared.fetchImageData(from: url),
              let loadedImage = NSImage(data: data) else {
            return
        }

        Self.cache.setObject(loadedImage, forKey: cacheKey)
        image = loadedImage
    }
}

struct SpotifyQueueControlButton: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var musicManager = MusicManager.shared
    @State private var showQueuePopover = false

    var body: some View {
        HoverButton(icon: "line.3.horizontal") {
            showQueuePopover.toggle()
        }
        .popover(isPresented: $showQueuePopover, arrowEdge: .bottom) {
            SpotifyQueuePopoverContent {
                vm.isDismissingMusicQueueForPlayback = true
                showQueuePopover = false
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    vm.isDismissingMusicQueueForPlayback = false
                }
            }
            .presentationBackground(SpotifyQueuePopoverStyle.background)
            .popoverOutsideClickDismiss(isPresented: $showQueuePopover)
        }
        .onChange(of: showQueuePopover) { _, isPresented in
            vm.isMusicQueuePopoverActive = isPresented
            if isPresented {
                Task {
                    await musicManager.syncSpotifyQueueAuth()
                    if musicManager.queueAuthState == .authenticated {
                        musicManager.refreshQueue()
                    }
                }
            }
        }
    }
}

// MARK: - Dismiss popover on outside click (borderless notch window)

private extension View {
    func popoverOutsideClickDismiss(isPresented: Binding<Bool>) -> some View {
        background(
            PopoverOutsideClickDismisser(isPresented: isPresented)
        )
    }
}

private struct PopoverOutsideClickDismisser: NSViewRepresentable {
    @Binding var isPresented: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(hostView: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(
            isPresented: $isPresented,
            hostView: nsView
        )
    }

    final class Coordinator {
        private var localMonitor: Any?
        private var globalMonitor: Any?
        private var appDeactivationObserver: Any?
        private weak var popoverWindow: NSWindow?
        private var isPresented: Binding<Bool>?

        func attach(hostView: NSView) {
            DispatchQueue.main.async { [weak self, weak hostView] in
                self?.popoverWindow = hostView?.window
            }
        }

        func update(isPresented: Binding<Bool>, hostView: NSView) {
            self.isPresented = isPresented
            popoverWindow = hostView.window

            if isPresented.wrappedValue {
                installMonitors()
            } else {
                removeMonitors()
            }
        }

        private func installMonitors() {
            guard localMonitor == nil else { return }

            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                guard let self else { return event }
                if self.shouldDismiss(for: event) {
                    DispatchQueue.main.async { self.dismiss() }
                }
                return event
            }

            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                guard let self else { return }
                DispatchQueue.main.async {
                    if self.shouldDismissForScreenPoint(NSEvent.mouseLocation) {
                        self.dismiss()
                    }
                }
            }

            appDeactivationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.dismiss()
            }
        }

        fileprivate func removeMonitors() {
            [localMonitor, globalMonitor].forEach { monitor in
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                }
            }
            localMonitor = nil
            globalMonitor = nil

            if let appDeactivationObserver {
                NotificationCenter.default.removeObserver(appDeactivationObserver)
            }
            appDeactivationObserver = nil
        }

        private func shouldDismiss(for event: NSEvent) -> Bool {
            if let popoverWindow, event.window === popoverWindow {
                return false
            }
            return shouldDismissForScreenPoint(NSEvent.mouseLocation)
        }

        private func shouldDismissForScreenPoint(_ screenPoint: CGPoint) -> Bool {
            if let popoverWindow {
                return !popoverWindow.frame.contains(screenPoint)
            }
            return true
        }

        private func dismiss() {
            isPresented?.wrappedValue = false
        }

        deinit {
            removeMonitors()
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitors()
    }
}
