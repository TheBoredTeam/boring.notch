import SwiftUI

/// Glass-backed shell that hosts every Orbie state. When idle/listening,
/// shows the orb presence with a radial gradient. When expanded, shows
/// the registered view for the current OrbieViewID with a thin-material
/// glass surface underneath.
///
/// Reuses Phase 1 tokens (Kairo.Palette / .Motion / .Elevation /
/// .Radius) and the .kairoElevation modifier.
struct OrbieShell: View {
    @EnvironmentObject var controller: OrbieController

    private var isExpanded: Bool {
        if case .expanded = controller.mode { return true }
        return false
    }

    var body: some View {
        ZStack {
            background
            border
            contentOverlay
        }
        .kairoElevation(isExpanded ? Kairo.Elevation.modal : Kairo.Elevation.popover)
        .animation(Kairo.Motion.morph, value: controller.currentSize)
        .animation(Kairo.Motion.morph, value: isExpanded)
    }

    // MARK: - Background

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(
            cornerRadius: controller.currentSize.cornerRadius,
            style: .continuous
        )

        ZStack {
            // 1. Glass material — visible whenever expanded
            shape
                .fill(.regularMaterial)
                .opacity(isExpanded ? 1 : 0)

            // 2. Glass tint layer — barely-there warmth on top of the material
            shape
                .fill(Kairo.Palette.glassTint)
                .opacity(isExpanded ? 1 : 0)

            // 3. Orb radial gradient — the dominant fill in compact states
            shape
                .fill(RadialGradient(
                    colors: [Kairo.Palette.orbCore, Kairo.Palette.orbDeep, .black],
                    center: UnitPoint(x: 0.3, y: 0.3),
                    startRadius: 4,
                    endRadius: 80
                ))
                .opacity(isExpanded ? 0 : 1)
        }
    }

    private var border: some View {
        RoundedRectangle(
            cornerRadius: controller.currentSize.cornerRadius,
            style: .continuous
        )
        .strokeBorder(
            isExpanded ? Kairo.Palette.glassStroke : Kairo.Palette.hairline,
            lineWidth: 0.5
        )
    }

    // MARK: - Content

    @ViewBuilder
    private var contentOverlay: some View {
        ZStack {
            if case .idle = controller.mode {
                OrbPresence(voiceState: controller.voiceState)
            } else if case .listening = controller.mode {
                OrbPresence(voiceState: controller.voiceState)
            }

            if case .expanded(let id, let payload) = controller.mode {
                expandedContent(id: id, payload: payload)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 8))
                            .animation(.easeOut(duration: 0.25).delay(0.18)),
                        removal: .opacity.animation(.easeIn(duration: 0.15))
                    ))
                    .id(id)
            }
        }
        .foregroundStyle(Kairo.Palette.text)
    }

    @ViewBuilder
    private func expandedContent(id: OrbieViewID, payload: AnyHashable?) -> some View {
        switch id {
        case .weather:
            if let d = payload as? WeatherData { WeatherView(data: d) }
        case .nowPlaying:
            if let d = payload as? NowPlayingData { NowPlayingView(data: d) }
        case .searchResults:
            if let d = payload as? SearchResultsData { SearchResultsView(data: d) }
        case .cameraFeed:
            if let d = payload as? CameraFeedData { CameraFeedView(data: d) }
        case .notification:
            if let d = payload as? NotificationData { NotificationView(data: d) }
        case .quickAnswer:
            if let d = payload as? QuickAnswerData { QuickAnswerView(data: d) }
        case .textResponse:
            if let d = payload as? TextResponseData { TextResponseView(data: d) }
        }
    }
}
