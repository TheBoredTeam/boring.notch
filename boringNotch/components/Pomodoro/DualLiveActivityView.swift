import SwiftUI

struct DualLiveActivityView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var pomodoroManager = PomodoroManager.shared
    @EnvironmentObject var vm: BoringViewModel
    var albumArtNamespace: Namespace.ID

    var body: some View {
        HStack {
            Image(nsImage: musicManager.albumArt)
                .resizable()
                .clipped()
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed)
                )
                .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                .frame(
                    width: max(0, vm.effectiveClosedNotchHeight - 12),
                    height: max(0, vm.effectiveClosedNotchHeight - 12)
                )
            
            Spacer()
            
            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .font(.system(size: 10))
                Text(pomodoroManager.formattedTime)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .foregroundColor(.white)
            .padding(.trailing, 8)
        }
        .frame(height: max(0, vm.effectiveClosedNotchHeight - 12))
    }
}
