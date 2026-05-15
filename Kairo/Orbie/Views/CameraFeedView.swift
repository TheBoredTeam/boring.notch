import SwiftUI
import AVKit

struct CameraFeedData: Hashable {
    let label: String
    let streamURL: URL
}

struct CameraFeedView: View {
    let data: CameraFeedData

    var body: some View {
        ZStack(alignment: .topLeading) {
            VideoPlayer(player: AVPlayer(url: data.streamURL))
                .clipShape(RoundedRectangle(cornerRadius: Kairo.Radius.xl, style: .continuous))

            HStack(spacing: 6) {
                Circle().fill(Kairo.Palette.danger).frame(width: 8, height: 8)
                Text("LIVE").font(.system(size: 11, weight: .bold)).tracking(1.0)
                Text("·").foregroundColor(Kairo.Palette.textDim)
                Text(data.label).font(.system(size: 11, weight: .medium))
                    .foregroundColor(Kairo.Palette.textDim)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(.black.opacity(0.5)))
            .padding(12)
        }
        .foregroundColor(Kairo.Palette.text)
    }
}
