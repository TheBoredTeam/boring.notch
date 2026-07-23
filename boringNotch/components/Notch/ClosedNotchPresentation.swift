import Foundation

enum ClosedNotchPresentation: Equatable {
    case batteryNotification
    case inlineOSD
    case music
    case idleFace
    case idle
}

enum ClosedNotchSupplementalPresentation: Equatable {
    case systemOSD
    case music
}

struct ClosedNotchLayoutMetrics: Equatable {
    let exclusionWidth: CGFloat
    let leadingWidth: CGFloat
    let trailingWidth: CGFloat
    let leadingExclusionMargin: CGFloat
    let trailingExclusionMargin: CGFloat
    let horizontalChromeInset: CGFloat
    let height: CGFloat

    var totalWidth: CGFloat {
        leadingWidth
            + leadingExclusionMargin
            + exclusionWidth
            + trailingExclusionMargin
            + trailingWidth
    }
}

struct ClosedNotchPresentationInput: Equatable {
    let closedNotchWidth: CGFloat
    let height: CGFloat
    let idleHeight: CGFloat
    let inlineOSDHeight: CGFloat
    let inlineSideWidth: CGFloat
    let albumArtWidth: CGFloat
    let spectrumWidth: CGFloat
    let expandedMusicCenterWidth: CGFloat
    let idleFaceTrailingWidth: CGFloat
    let batteryLeadingWidth: CGFloat
    let batteryNotificationVisible: Bool
    let inlineOSDVisible: Bool
    let musicVisible: Bool
    let idleFaceVisible: Bool
    let musicExpanded: Bool
    let supplemental: ClosedNotchSupplementalPresentation?
}

struct ClosedNotchPresentationState: Equatable {
    let primary: ClosedNotchPresentation
    let supplemental: ClosedNotchSupplementalPresentation?
    let musicExpanded: Bool
    let metrics: ClosedNotchLayoutMetrics
}

enum ClosedNotchPresentationResolver {
    static func resolve(_ input: ClosedNotchPresentationInput) -> ClosedNotchPresentationState {
        let primary: ClosedNotchPresentation

        if input.batteryNotificationVisible {
            primary = .batteryNotification
        } else if input.inlineOSDVisible {
            primary = .inlineOSD
        } else if input.musicVisible {
            primary = .music
        } else if input.idleFaceVisible {
            primary = .idleFace
        } else {
            primary = .idle
        }

        let layout: (
            leadingWidth: CGFloat,
            trailingWidth: CGFloat,
            leadingMargin: CGFloat,
            trailingMargin: CGFloat,
            chromeInset: CGFloat
        )
        switch primary {
        case .batteryNotification:
            layout = (
                input.batteryLeadingWidth,
                76,
                0,
                10,
                cornerRadiusInsets.closed.bottom
            )

        case .inlineOSD:
            layout = (input.inlineSideWidth, input.inlineSideWidth, 0, 0, 12)

        case .music:
            if input.musicExpanded {
                let textSideWidth = max(
                    0,
                    (input.expandedMusicCenterWidth - input.closedNotchWidth) / 2
                )
                layout = (
                    input.albumArtWidth + textSideWidth,
                    textSideWidth + input.spectrumWidth,
                    0,
                    0,
                    cornerRadiusInsets.closed.bottom
                )
            } else {
                let centralizedEdgeMargin = max(0, liveActivityEdgeMargin - 2)
                layout = (
                    input.albumArtWidth,
                    input.spectrumWidth,
                    centralizedEdgeMargin,
                    centralizedEdgeMargin,
                    cornerRadiusInsets.closed.bottom
                )
            }

        case .idleFace:
            layout = (
                0,
                input.idleFaceTrailingWidth,
                0,
                8,
                cornerRadiusInsets.closed.bottom
            )

        case .idle:
            layout = (0, 0, 0, 0, 4)
        }

        let resolvedHeight: CGFloat
        switch primary {
        case .idle:
            resolvedHeight = input.idleHeight
        case .inlineOSD:
            resolvedHeight = input.inlineOSDHeight
        default:
            resolvedHeight = input.height
        }

        return .init(
            primary: primary,
            supplemental: input.supplemental,
            musicExpanded: primary == .music && input.musicExpanded,
            metrics: .init(
                exclusionWidth: input.closedNotchWidth,
                leadingWidth: layout.leadingWidth,
                trailingWidth: layout.trailingWidth,
                leadingExclusionMargin: layout.leadingMargin,
                trailingExclusionMargin: layout.trailingMargin,
                horizontalChromeInset: layout.chromeInset,
                height: resolvedHeight
            )
        )
    }
}
