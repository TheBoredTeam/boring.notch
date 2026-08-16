import SwiftUI

struct OpenNotchContentView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var coordinator = BoringViewCoordinator.shared

    let albumArtNamespace: Namespace.ID
    let horizontalMediaGestureFeedback: CGFloat
    @Binding var isHoveringMusicArea: Bool
    let gestureProgress: CGFloat

    var body: some View {
        VStack {
            switch selectedDestination {
            case .home:
                NotchHomeView(
                    albumArtNamespace: albumArtNamespace,
                    horizontalMediaGestureFeedback: horizontalMediaGestureFeedback,
                    isHoveringMusicArea: $isHoveringMusicArea
                )
            case .shelf:
                ShelfView()
            case nil:
                EmptyView()
            }
        }
        .transition(
            .scale(scale: 0.8, anchor: .top)
                .combined(with: .opacity)
                .animation(.smooth(duration: 0.35))
        )
        .zIndex(1)
        .allowsHitTesting(vm.notchState == .open)
        .opacity(gestureProgress == 0 ? 1 : 1 - min(abs(gestureProgress) * 0.1, 0.3))
    }

    private var selectedDestination: NotchViews? {
        let availableDestinations = NotchDestinationDescriptor.availableBuiltIn
        return availableDestinations.first {
            $0.destination == coordinator.currentView
        }?.destination ?? availableDestinations.first?.destination
    }
}
