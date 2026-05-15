import SwiftUI

struct OrbieShell: View {
    @EnvironmentObject var controller: OrbieController

    private var isExpanded: Bool {
        if case .expanded = controller.mode { return true }
        return false
    }

    var body: some View {
        ZStack {
            // Solid background (always present, visible in expanded mode)
            RoundedRectangle(cornerRadius: controller.currentSize.cornerRadius, style: .continuous)
                .fill(Kairo.Palette.background)

            // Orb gradient (fades out when expanded)
            RoundedRectangle(cornerRadius: controller.currentSize.cornerRadius, style: .continuous)
                .fill(RadialGradient(
                    colors: [Kairo.Palette.orbCore, Kairo.Palette.orbDeep, .black],
                    center: UnitPoint(x: 0.3, y: 0.3), startRadius: 4, endRadius: 80
                ))
                .opacity(isExpanded ? 0 : 1)

            // Border
            RoundedRectangle(cornerRadius: controller.currentSize.cornerRadius, style: .continuous)
                .stroke(Kairo.Palette.hairline, lineWidth: 1)

            // Content
            contentOverlay
        }
        .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
        .animation(Kairo.Motion.spring, value: controller.currentSize)
        .animation(Kairo.Motion.spring, value: isExpanded)
    }

    private var shadowColor: Color {
        isExpanded ? .black.opacity(0.5) : Kairo.Palette.orbCore.opacity(0.4)
    }

    private var shadowRadius: CGFloat {
        controller.currentSize == .orb ? 30 : 40
    }

    private var shadowY: CGFloat {
        controller.currentSize == .orb ? 0 : 20
    }

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
