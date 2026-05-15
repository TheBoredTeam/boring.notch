import SwiftUI

struct NowPlayingData: Hashable {
    let title: String
    let artist: String
    let artworkURL: URL?
    let isPlaying: Bool
}

/// Compact pill-sized view — appears when Orbie surfaces "now playing"
/// during a track change or media event. Artwork + title/artist +
/// animated audio bars.
struct NowPlayingView: View {
    let data: NowPlayingData

    var body: some View {
        HStack(spacing: Kairo.Space.md) {
            artwork
            VStack(alignment: .leading, spacing: Kairo.Space.xxs) {
                Text(data.title)
                    .font(Kairo.Typography.bodyEmphasis)
                    .foregroundStyle(Kairo.Palette.text)
                    .lineLimit(1)
                Text(data.artist)
                    .font(Kairo.Typography.bodySmall)
                    .foregroundStyle(Kairo.Palette.textDim)
                    .lineLimit(1)
            }
            Spacer()
            AudioBars(playing: data.isPlaying)
        }
        .padding(.horizontal, Kairo.Space.lg)
        .padding(.vertical, Kairo.Space.md)
    }

    private var artwork: some View {
        AsyncImage(url: data.artworkURL) { img in
            img.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            ZStack {
                Kairo.Palette.surfaceHi
                Image(systemName: "music.note")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Kairo.Palette.textFaint)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: Kairo.Radius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Kairo.Radius.sm, style: .continuous)
                .strokeBorder(Kairo.Palette.hairline, lineWidth: 0.5)
        }
    }
}

// MARK: - Audio bars

private struct AudioBars: View {
    let playing: Bool
    @State private var phase: CGFloat = 0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(Kairo.Palette.accent)
                    .frame(width: 3, height: barHeight(for: i))
                    .animation(
                        .easeInOut(duration: 0.4)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.1),
                        value: phase
                    )
            }
        }
        .frame(width: 28, height: 24)
        .onAppear { if playing { phase = 1 } }
        .onChange(of: playing) { _, isOn in phase = isOn ? 1 : 0 }
    }

    private func barHeight(for i: Int) -> CGFloat {
        guard playing else { return 6 }
        let heights: [CGFloat] = [14, 22, 10, 18]
        return heights[i] * (phase == 0 ? 0.4 : 1.0)
    }
}
