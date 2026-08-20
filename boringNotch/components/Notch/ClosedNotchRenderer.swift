import Defaults
import SwiftUI

struct ClosedNotchRenderer: View {
    let snapshot: ClosedNotchRenderSnapshot
    let albumArtNamespace: Namespace.ID
    let onActivitySelect: (() -> Void)?

    private var state: ClosedNotchPresentationState { snapshot.presentation }
    private var renderData: ClosedNotchRenderData { snapshot.renderData }

    var body: some View {
        VStack(alignment: .leading) {
            primaryContent
            supplementalContent
        }
        .conditionalModifier(requiresFixedSize) { view in
            view.fixedSize()
        }
        .zIndex(1)
    }

    private var requiresFixedSize: Bool {
        if case .extensionActivity = state.primary {
            return true
        }
        return state.supplemental != nil
    }

    @ViewBuilder
    private var primaryContent: some View {
        switch state.primary {
        case .batteryNotification:
            ClosedNotchLayout(metrics: state.metrics) {
                Text(LocalizedStringKey(renderData.battery.statusTextKey))
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } trailing: {
                BoringBatteryView(
                    batteryWidth: 30,
                    isCharging: renderData.battery.isCharging,
                    isInLowPowerMode: renderData.battery.isInLowPowerMode,
                    isPluggedIn: renderData.battery.isPluggedIn,
                    levelBattery: renderData.battery.level,
                    maxAdapterWatts: renderData.battery.maxAdapterWatts,
                    isForNotification: true
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

        case .inlineOSD:
            ClosedNotchLayout(metrics: state.metrics) {
                let sneakPeek = renderData.osd.wrappedValue
                InlineOSDLeadingView(
                    type: sneakPeek.type,
                    value: sneakPeek.value,
                    icon: sneakPeek.icon,
                    accent: sneakPeek.accent
                )
            } trailing: {
                InlineOSDTrailingView(
                    type: renderData.osd.type,
                    value: renderData.osd.value,
                    accent: renderData.osd.wrappedValue.accent
                )
            }
            .transition(.opacity)

        case .music:
            ClosedNotchLayout(metrics: state.metrics) {
                MusicLiveActivityLeadingView(
                    data: renderData.music,
                    albumArtNamespace: albumArtNamespace,
                    albumArtWidth: snapshot.albumArtWidth,
                    titleWidth: max(0, state.metrics.leadingWidth - snapshot.albumArtWidth),
                    cornerRadiusScaleFactor: snapshot.cornerRadiusScaleFactor,
                    expanded: state.musicExpanded
                )
            } trailing: {
                MusicLiveActivityTrailingView(
                    data: renderData.music,
                    artistWidth: max(0, state.metrics.trailingWidth - snapshot.spectrumWidth),
                    spectrumWidth: snapshot.spectrumWidth,
                    expanded: state.musicExpanded
                )
            }

        case .idleFace:
            ClosedNotchLayout(metrics: state.metrics) {
                EmptyView()
            } trailing: {
                IdleNotchFaceView(displayClosedNotchHeight: snapshot.displayHeight)
            }

        case .extensionActivity(let id):
            if let activity = snapshot.extensionActivities[id] {
                activity.content
                    .transition(extensionActivityTransition)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let onSelect = activity.onSelect {
                            onActivitySelect?()
                            onSelect()
                        }
                    }
            }

        case .idle:
            Color.clear
                .frame(width: state.metrics.totalWidth, height: state.metrics.height)
        }
    }

    private var extensionActivityTransition: AnyTransition {
        .opacity
            .combined(with: .scale(scale: 0.94, anchor: .top))
            .combined(with: .move(edge: .top))
            .animation(StandardAnimations.open)
    }

    @ViewBuilder
    private var supplementalContent: some View {
        switch state.supplemental {
        case .systemOSD:
            SystemEventIndicatorModifier(
                eventType: renderData.osd.type,
                value: renderData.osd.value,
                icon: renderData.osd.icon,
                accent: renderData.osd.accent,
                sendEventBack: updateSystemValue
            )
            .padding(.bottom, 10)
            .padding(.leading, 4)
            .padding(.trailing, 8)

        case .music:
            HStack(alignment: .center) {
                Image(systemName: "music.note")

                GeometryReader { geometry in
                    MarqueeText(
                        renderData.music.title + " - " + renderData.music.artist,
                        color: Defaults[.playerColorTinting]
                            ? Color(nsColor: renderData.music.tintColor)
                                .ensureMinimumBrightness(factor: 0.6)
                            : .gray,
                        delayDuration: 1,
                        frameWidth: geometry.size.width
                    )
                }
            }
            .foregroundStyle(.gray)
            .padding(.bottom, 10)

        case nil:
            EmptyView()
        }
    }

    private func updateSystemValue(_ newValue: CGFloat) {
        switch renderData.osd.wrappedValue.type {
        case .volume:
            VolumeManager.shared.setAbsolute(Float32(newValue))
        case .brightness:
            BrightnessManager.shared.setAbsolute(value: Float32(newValue))
        default:
            break
        }
    }
}
