import SwiftUI
import AVKit

struct CameraFeedData: Hashable {
    let label: String
    let streamURL: URL
}

/// Card-sized live camera feed. AVKit video player fills the card.
/// LIVE pill + camera label overlay in the top-left with a soft scrim.
struct CameraFeedView: View {
    let data: CameraFeedData

    var body: some View {
        ZStack(alignment: .topLeading) {
            VideoPlayer(player: AVPlayer(url: data.streamURL))
                .clipShape(RoundedRectangle(cornerRadius: Kairo.Radius.xl, style: .continuous))

            // Top scrim — darkens the area behind the pill so it's legible
            // against any feed brightness.
            LinearGradient(
                colors: [Color.black.opacity(0.45), Color.clear],
                startPoint: .top,
                endPoint: .center
            )
            .frame(height: 64)
            .allowsHitTesting(false)

            HStack(spacing: Kairo.Space.sm) {
                KairoPill("LIVE", icon: "dot.radiowaves.left.and.right", tone: .danger)
                Text(data.label)
                    .font(Kairo.Typography.captionStrong)
                    .foregroundStyle(Color.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.6), radius: 3, x: 0, y: 1)
            }
            .padding(Kairo.Space.md)
        }
    }
}
