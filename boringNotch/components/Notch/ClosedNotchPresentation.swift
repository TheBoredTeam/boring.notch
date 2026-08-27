import Foundation

enum ClosedNotchPresentation: Equatable {
    case batteryNotification
    case inlineOSD
    case music
    case idleFace
    case extensionActivity(String)
    case idle

    var priority: ClosedNotchPresentationPriority {
        switch self {
        case .batteryNotification: .critical
        case .inlineOSD: .system
        case .music: .activity
        case .idleFace: .ambient
        case .extensionActivity: .activity
        case .idle: .idle
        }
    }
}

enum ClosedNotchPresentationPriority: Int, Comparable {
    case idle
    case ambient
    case activity
    case system
    case critical

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ClosedNotchPresentationCandidate: Equatable {
    let presentation: ClosedNotchPresentation
    let isVisible: Bool
    let priority: ClosedNotchPresentationPriority
    let updatedAt: Date
    let metrics: ClosedNotchLayoutMetrics?

    init(
        _ presentation: ClosedNotchPresentation,
        isVisible: Bool,
        priority: ClosedNotchPresentationPriority? = nil,
        updatedAt: Date = .distantPast,
        metrics: ClosedNotchLayoutMetrics? = nil
    ) {
        self.presentation = presentation
        self.isVisible = isVisible
        self.priority = priority ?? presentation.priority
        self.updatedAt = updatedAt
        self.metrics = metrics
    }
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
    let candidates: [ClosedNotchPresentationCandidate]
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
        let selectedCandidate = PriorityResolver.select(
            from: input.candidates,
            isVisible: { $0.isVisible },
            priority: { $0.priority.rawValue },
            updatedAt: { $0.updatedAt }
        )
        let primary = selectedCandidate?.presentation ?? .idle

        if case .extensionActivity = primary,
           let metrics = selectedCandidate?.metrics {
            return .init(
                primary: primary,
                supplemental: nil,
                musicExpanded: false,
                metrics: metrics
            )
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

        case .extensionActivity:
            layout = (0, 0, 0, 0, cornerRadiusInsets.closed.bottom)

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
