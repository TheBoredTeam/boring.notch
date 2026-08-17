import SwiftUI

struct OpenNotchContentView: View {
    private static let permissionViewportHeight = max(0, openNotchSize.height - 12)

    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var coordinator = BoringViewCoordinator.shared

    let albumArtNamespace: Namespace.ID
    let horizontalMediaGestureFeedback: CGFloat
    @Binding var isHoveringMusicArea: Bool
    let gestureProgress: CGFloat
    let permissionNotification: CodexJobNotification?
    let dismissPermissionRequest: () -> Void

    var body: some View {
        VStack {
            if let permissionNotification {
                CodexPermissionApprovalView(
                    notification: permissionNotification,
                    onDismiss: dismissPermissionRequest
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: Self.permissionViewportHeight, alignment: .topLeading)
            } else {
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
        }
        .frame(
            maxWidth: permissionNotification == nil ? nil : .infinity,
            alignment: .topLeading
        )
        .frame(
            height: permissionNotification == nil ? nil : Self.permissionViewportHeight,
            alignment: .topLeading
        )
        .transition(contentTransition)
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

    private var contentTransition: AnyTransition {
        if permissionNotification != nil {
            return .opacity
                .combined(with: .scale(scale: 0.9, anchor: .top))
        }
        return .scale(scale: 0.8, anchor: .top)
            .combined(with: .opacity)
            .animation(.smooth(duration: 0.35))
    }
}
