import AppKit
import Defaults
import SwiftUI

struct ClosedNotchMusicRenderData {
    let albumArt: NSImage
    let title: String
    let artist: String
    let tintColor: NSColor
    let isPlaying: Bool
}

struct MusicLiveActivityLeadingView: View {
    let data: ClosedNotchMusicRenderData
    let albumArtNamespace: Namespace.ID
    let albumArtWidth: CGFloat
    let titleWidth: CGFloat
    let cornerRadiusScaleFactor: CGFloat?
    let expanded: Bool

    var body: some View {
        HStack(spacing: 0) {
            albumArt

            if showsExpandedText {
                MarqueeText(
                    data.title,
                    color: Defaults[.coloredSpectrogram]
                        ? Color(nsColor: data.tintColor)
                        : .gray,
                    delayDuration: 0.4,
                    frameWidth: titleWidth
                )
                .frame(width: titleWidth)
            }
        }
    }

    private var albumArt: some View {
        Image(nsImage: data.albumArt)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: closedCornerRadius))
            .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
            .frame(width: albumArtWidth, height: albumArtWidth)
    }

    private var showsExpandedText: Bool {
        expanded && titleWidth > 0
    }

    private var closedCornerRadius: CGFloat {
        let base = MusicPlayerImageSizes.cornerRadiusInset.closed
        guard let cornerRadiusScaleFactor else { return base }
        return max(0, base * cornerRadiusScaleFactor)
    }
}

struct MusicLiveActivityTrailingView: View {
    let data: ClosedNotchMusicRenderData
    let artistWidth: CGFloat
    let spectrumWidth: CGFloat
    let expanded: Bool

    var body: some View {
        HStack(spacing: 0) {
            if showsExpandedText {
                Text(data.artist)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(
                        Defaults[.coloredSpectrogram]
                            ? Color(nsColor: data.tintColor)
                            : .gray
                    )
                    .frame(width: artistWidth, alignment: .trailing)
            }

            spectrum
        }
    }

    private var spectrum: some View {
        AudioSpectrumView(
            isPlaying: data.isPlaying,
            tintColor: Defaults[.coloredSpectrogram]
                ? Color(nsColor: data.tintColor).ensureMinimumBrightness(factor: 0.5)
                : .gray
        )
        .frame(width: 18, height: 12)
        .frame(width: spectrumWidth, alignment: .center)
    }

    private var showsExpandedText: Bool {
        expanded && artistWidth > 0
    }
}
