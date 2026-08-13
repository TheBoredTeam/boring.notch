//
//  ScreenMediaBar.swift
//  boringNotch
//

import AppKit
import Combine
import Defaults
import SwiftUI

@MainActor
final class ScreenMediaBarController: NSObject, NSWindowDelegate {
    static let shared = ScreenMediaBarController()

    private let barSize = CGSize(width: 620, height: 88)
    private var panel: NSPanel?
    private var cancellables = Set<AnyCancellable>()
    private var isApplyingPosition = false
    private var visibilityTransitionID = UUID()

    private override init() {
        super.init()

        let musicManager = MusicManager.shared
        Publishers.MergeMany([
            musicManager.$isPlaying.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            musicManager.$isPlayerIdle.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            musicManager.$songTitle.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.screenMediaBarEnabled).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.screenMediaBarAlwaysOnTop).map { _ in () }.eraseToAnyPublisher(),
        ])
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in
            self?.updateVisibility()
        }
        .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.ensureVisiblePosition()
            }
            .store(in: &cancellables)

        updateVisibility()
    }

    func resetPosition() {
        Defaults[.screenMediaBarOriginX] = -100_000
        Defaults[.screenMediaBarOriginY] = -100_000
        guard let panel else { return }
        applyPosition(defaultOrigin(for: panel.frame.size))
    }

    func stop() {
        cancellables.removeAll()
        visibilityTransitionID = UUID()
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    private func updateVisibility() {
        updateWindowLevel()
        let shouldShow = Defaults[.screenMediaBarEnabled]
            && (MusicManager.shared.isPlaying || !MusicManager.shared.isPlayerIdle)
            && !MusicManager.shared.songTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if shouldShow {
            show()
        } else {
            hide()
        }
    }

    private func show() {
        let panel = panel ?? makePanel()
        guard !panel.isVisible else {
            panel.alphaValue = 1
            return
        }

        ensureVisiblePosition()
        let transitionID = UUID()
        visibilityTransitionID = transitionID
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.20
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor in
                guard self?.visibilityTransitionID == transitionID else { return }
                panel?.alphaValue = 1
            }
        }
    }

    private func hide() {
        guard let panel, panel.isVisible else { return }
        let transitionID = UUID()
        visibilityTransitionID = transitionID

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor in
                guard self?.visibilityTransitionID == transitionID else { return }
                panel?.orderOut(nil)
                panel?.alphaValue = 1
            }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = ScreenMediaPanel(
            contentRect: NSRect(origin: .zero, size: barSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.identifier = NSUserInterfaceItemIdentifier("DanShenScreenMediaBar")
        panel.contentView = NSHostingView(rootView: ScreenMediaBarView())
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = Defaults[.screenMediaBarAlwaysOnTop]
        panel.hidesOnDeactivate = false
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        configureWindowLevel(panel)
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.delegate = self
        self.panel = panel

        applyPosition(restoredOrigin(for: panel.frame.size) ?? defaultOrigin(for: panel.frame.size))
        return panel
    }

    private func updateWindowLevel() {
        guard let panel else { return }
        configureWindowLevel(panel)
    }

    private func configureWindowLevel(_ panel: NSPanel) {
        let staysOnTop = Defaults[.screenMediaBarAlwaysOnTop]
        panel.isFloatingPanel = staysOnTop
        panel.level = staysOnTop ? .floating : .normal
        panel.collectionBehavior = staysOnTop
            ? [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            : [.managed, .ignoresCycle]
    }

    private func ensureVisiblePosition() {
        guard let panel else { return }
        if !isUsablyVisible(panel.frame) {
            applyPosition(defaultOrigin(for: panel.frame.size))
        }
    }

    private func restoredOrigin(for size: CGSize) -> CGPoint? {
        let x = Defaults[.screenMediaBarOriginX]
        let y = Defaults[.screenMediaBarOriginY]
        guard x > -99_999, y > -99_999 else { return nil }

        let origin = CGPoint(x: x, y: y)
        let frame = NSRect(origin: origin, size: size)
        return isUsablyVisible(frame) ? origin : nil
    }

    private func defaultOrigin(for size: CGSize) -> CGPoint {
        let preferredScreen = NSScreen.screen(withUUID: BoringViewCoordinator.shared.selectedScreenUUID)
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let visibleFrame = preferredScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return CGPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.minY + 24
        )
    }

    private func isUsablyVisible(_ frame: NSRect) -> Bool {
        NSScreen.screens.contains { screen in
            let intersection = screen.visibleFrame.intersection(frame)
            return intersection.width >= 120 && intersection.height >= 40
        }
    }

    private func applyPosition(_ origin: CGPoint) {
        guard let panel else { return }
        isApplyingPosition = true
        panel.setFrameOrigin(origin)
        isApplyingPosition = false
    }

    func windowDidMove(_ notification: Notification) {
        guard !isApplyingPosition, let panel else { return }
        Defaults[.screenMediaBarOriginX] = panel.frame.origin.x
        Defaults[.screenMediaBarOriginY] = panel.frame.origin.y
    }
}

private final class ScreenMediaPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct ScreenMediaBarView: View {
    @ObservedObject private var musicManager = MusicManager.shared
    @Default(.enableLyrics) private var enableLyrics
    @Default(.screenMediaBarShowsLyrics) private var showsLyrics

    var body: some View {
        HStack(spacing: 12) {
            artwork

            VStack(alignment: .leading, spacing: 3) {
                Text(musicManager.songTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(musicManager.artistName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if enableLyrics, showsLyrics {
                    TimelineView(.periodic(from: .now, by: 0.35)) { timeline in
                        let snapshot = musicManager.lyricDisplaySnapshot(
                            at: musicManager.estimatedElapsedTime(at: timeline.date)
                        )
                        HStack(spacing: 5) {
                            Image(systemName: "quote.bubble.fill")
                                .font(.system(size: 9, weight: .semibold))
                            Text(snapshot.current)
                                .lineLimit(1)
                                .help(snapshot.current)
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(snapshot.isPlaceholder ? .tertiary : .secondary)
                        .animation(.easeInOut(duration: 0.18), value: snapshot.current)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                controlButton("backward.fill", help: "上一首") {
                    musicManager.previousTrack()
                }
                controlButton(musicManager.isPlaying ? "pause.fill" : "play.fill", help: "播放或暂停", prominent: true) {
                    musicManager.togglePlay()
                }
                controlButton("forward.fill", help: "下一首") {
                    musicManager.nextTrack()
                }
                controlButton("music.note", help: "打开播放器") {
                    musicManager.openMusicApp()
                }
                controlButton("xmark", help: "隐藏屏幕媒体条") {
                    Defaults[.screenMediaBarEnabled] = false
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 620, height: 88)
        .background {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            Color.black.opacity(0.24)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
    }

    private var artwork: some View {
        Image(nsImage: musicManager.albumArt)
            .resizable()
            .aspectRatio(1, contentMode: .fill)
            .frame(width: 58, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture {
                musicManager.openMusicApp()
            }
    }

    private func controlButton(
        _ symbolName: String,
        help: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: prominent ? 14 : 12, weight: .semibold))
                .frame(width: prominent ? 38 : 32, height: 32)
                .background(Color.white.opacity(prominent ? 0.16 : 0.07))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
