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
                    .constant(music.songTitle),
                    textColor: coloredSpectrogram ? Color(nsColor: music.avgColor) : .gray,
                    minDuration: 0.4,
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
    @Default(.useMusicVisualizer) private var useMusicVisualizer
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
            Group {
                if useMusicVisualizer {
                    Rectangle()
                        .fill(coloredSpectrogram
                              ? Color(nsColor: music.avgColor).ensureMinimumBrightness(factor: 0.5).gradient
                              : Color.gray.gradient)
                        .mask {
                            AudioSpectrumView(isPlaying: $music.isPlaying)
                                .frame(width: 16, height: 12)
                        }
                } else {
                    LottieAnimationContainer()
                }
            }
            .frame(width: visualizerWidth, height: max(0, context.height - 12))
            .accessibilityHidden(true)
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
            maxCapacity: battery.maxCapacity,
            timeToFullCharge: battery.timeToFullCharge,
            isForNotification: true
        )
    }
}

struct BuiltinOSDLeading: View {
    @ObservedObject private var coordinator = BoringViewCoordinator.shared
    let context: LiveActivityViewContext

    var body: some View {
        let state = coordinator.sneakPeek
        InlineHUDLeading(
            type: state.type, value: state.value, icon: state.icon,
            width: min(context.maximumSideWidth, max(0, 100 - (context.isHovered ? 0 : 12) + context.gestureProgress / 2)),
            height: context.height
        )
    }
}

struct BuiltinOSDTrailing: View {
    @ObservedObject private var coordinator = BoringViewCoordinator.shared
    let context: LiveActivityViewContext

    var body: some View {
        InlineHUDTrailing(
            type: coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value,
            width: min(context.maximumSideWidth, max(0, 100 - (context.isHovered ? 0 : 12) + context.gestureProgress / 2)),
            height: context.height
        )
    }
}
