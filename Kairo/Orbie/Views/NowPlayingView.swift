import SwiftUI

struct NowPlayingData: Hashable {
    let title: String
    let artist: String
    let artworkURL: URL?
    let isPlaying: Bool
}

struct NowPlayingView: View {
    let data: NowPlayingData

    var body: some View {
        HStack(spacing: 14) {
            AsyncImage(url: data.artworkURL) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Kairo.Palette.surfaceHi
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(data.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(data.artist).font(.system(size: 12))
                    .foregroundColor(Kairo.Palette.textDim).lineLimit(1)
            }
            Spacer()
            AudioBars(playing: data.isPlaying)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .foregroundColor(Kairo.Palette.text)
    }
}

private struct AudioBars: View {
    let playing: Bool
    @State private var phase: CGFloat = 0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { i in
                Capsule().fill(Kairo.Palette.accent)
                    .frame(width: 3, height: barHeight(for: i))
                    .animation(.easeInOut(duration: 0.4).repeatForever().delay(Double(i) * 0.1), value: phase)
            }
        }
        .frame(width: 28, height: 24)
        .onAppear { if playing { phase = 1 } }
    }

    private func barHeight(for i: Int) -> CGFloat {
        guard playing else { return 6 }
        let heights: [CGFloat] = [14, 22, 10, 18]
        return heights[i] * (phase == 0 ? 0.4 : 1.0)
    }
}
