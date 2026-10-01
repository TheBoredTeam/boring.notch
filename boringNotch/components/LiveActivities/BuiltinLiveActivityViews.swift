// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

import Defaults
import SwiftUI

private struct ActivityAlbumArtNamespaceKey: EnvironmentKey {
    static var defaultValue: Namespace.ID? { nil }
}

extension EnvironmentValues {
    var notchActivityAlbumArtNamespace: Namespace.ID? {
        get { self[ActivityAlbumArtNamespaceKey.self] }
        set { self[ActivityAlbumArtNamespaceKey.self] = newValue }
    }
}

private struct ActivityAlbumArtMatch: ViewModifier {
    let namespace: Namespace.ID?

    @ViewBuilder func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: "albumArt", in: namespace)
        } else {
            content
        }
    }
}

struct BuiltinMusicLeading: View {
    @ObservedObject private var music = MusicManager.shared
    @ObservedObject private var coordinator = BoringViewCoordinator.shared
    @Environment(\.notchActivityAlbumArtNamespace) private var albumArtNamespace
    @Default(.cornerRadiusScaling) private var cornerRadiusScaling
    @Default(.coloredSpectrogram) private var coloredSpectrogram
    @Default(.sneakPeekStyles) private var sneakPeekStyle
    let context: LiveActivityViewContext

    private var scale: CGFloat { cornerRadiusScaling ? context.height / 38 : 1 }
    private var artSize: CGFloat { max(0, context.height - 12 * scale) }
    private var showsPeek: Bool {
        coordinator.expandingView.show && coordinator.expandingView.type == .music && sneakPeekStyle == .inline
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: music.albumArt)
                .resizable().scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: max(0, MusicPlayerImageSizes.cornerRadiusInset.closed * scale)))
                .modifier(ActivityAlbumArtMatch(namespace: albumArtNamespace))
                .frame(width: artSize, height: artSize)
            if showsPeek {
                let labelWidth = min(110, max(0, context.maximumSideWidth - artSize - 8))
                MarqueeText(
                    music.songTitle,
                    color: coloredSpectrogram ? Color(nsColor: music.avgColor) : .gray,
                    delayDuration: 0.4,
                    frameWidth: labelWidth
                )
                // MarqueeText uses GeometryReader internally; expose its
                // viewport width so intrinsic host measurement sees it too.
                .frame(width: labelWidth)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Now playing: \(music.songTitle)"))
    }
}

struct BuiltinMusicTrailing: View {
    @ObservedObject private var music = MusicManager.shared
    @ObservedObject private var coordinator = BoringViewCoordinator.shared
    @Default(.coloredSpectrogram) private var coloredSpectrogram
    @Default(.sneakPeekStyles) private var sneakPeekStyle
    let context: LiveActivityViewContext

    private var visualizerWidth: CGFloat { max(0, context.height - 12 + context.gestureProgress / 2) }
    private var showsPeek: Bool {
        coordinator.expandingView.show && coordinator.expandingView.type == .music && sneakPeekStyle == .inline
    }

    var body: some View {
        HStack(spacing: 8) {
            if showsPeek {
                Text(music.artistName)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: min(110, max(0, context.maximumSideWidth - visualizerWidth - 8)), alignment: .trailing)
                    .foregroundStyle(coloredSpectrogram ? Color(nsColor: music.avgColor) : .gray)
            }
            MusicVisualizer(
                isPlaying: music.isPlaying,
                tintColor: coloredSpectrogram ? Color(nsColor: music.avgColor).ensureMinimumBrightness(factor: 0.5) : .gray
            )
            .frame(width: 18, height: 12)
            .frame(width: visualizerWidth, height: max(0, context.height - 12))
            .accessibilityHidden(true)
        }
    }
}

struct BuiltinNotificationLeading: View {
    @ObservedObject private var notifications = SystemNotificationManager.shared
    let notificationID: String
    let context: LiveActivityViewContext

    var body: some View {
        if let notification = notifications.activeNotification, notification.id == notificationID {
            NotificationSourceIcon(bundleID: notification.bundleID, size: max(0, context.height - 12))
                .accessibilityLabel(Text(notification.appName ?? "Notification"))
        }
    }
}

struct BuiltinBatteryLeading: View {
    @ObservedObject private var battery = BatteryStatusViewModel.shared

    var body: some View {
        Text(battery.statusText)
            .font(.subheadline)
            .foregroundStyle(.white)
            .lineLimit(1)
    }
}

struct BuiltinBatteryTrailing: View {
    @ObservedObject private var battery = BatteryStatusViewModel.shared

    var body: some View {
        BoringBatteryView(
            batteryWidth: 30,
            isCharging: battery.isCharging,
            isInLowPowerMode: battery.isInLowPowerMode,
            isPluggedIn: battery.isPluggedIn,
            levelBattery: battery.levelBattery,
            maxAdapterWatts: battery.maxAdapterWatts,
            isForNotification: true
        )
    }
}

struct BuiltinOSDLeading: View {
    @ObservedObject private var coordinator = BoringViewCoordinator.shared
    let context: LiveActivityViewContext

    var body: some View {
        let state = coordinator.sneakPeekState(for: context.displayID)
        InlineOSDLeading(
            type: state.type, value: state.value, icon: state.icon, accent: state.accent,
            width: min(context.maximumSideWidth, max(0, 100 - (context.isHovered ? 0 : 12) + context.gestureProgress / 2)),
            height: context.height
        )
    }
}

struct BuiltinOSDTrailing: View {
    @ObservedObject private var coordinator = BoringViewCoordinator.shared
    let context: LiveActivityViewContext

    var body: some View {
        let binding = coordinator.binding(for: context.displayID)
        InlineOSDTrailing(
            type: binding.wrappedValue.type, value: binding.value, accent: binding.wrappedValue.accent,
            width: min(context.maximumSideWidth, max(0, 100 - (context.isHovered ? 0 : 12) + context.gestureProgress / 2)),
            height: context.height
        )
    }
}
