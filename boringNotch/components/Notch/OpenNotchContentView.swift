import SwiftUI

struct OpenNotchContentView: View {
    private static let permissionViewportHeight = max(0, openNotchSize.height - 12)

    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var coordinator = BoringViewCoordinator.shared

    let albumArtNamespace: Namespace.ID
    let horizontalMediaGestureFeedback: CGFloat
    @Binding var isHoveringMusicArea: Bool
    let gestureProgress: CGFloat
    let detailNotification: CodexJobNotification?
    @Binding var responseKeyboardFocused: Bool
    let onDismissDetail: () -> Void

    private var responseMaximumHeight: CGFloat {
        let screen = vm.screenUUID.flatMap { NSScreen.screen(withUUID: $0) } ?? NSScreen.main
        return min(maximumResponseNotchHeight, max(120, (screen?.frame.height ?? 800) - 40))
    }

    private var permissionTopInset: CGFloat {
        let screen = vm.screenUUID.flatMap { NSScreen.screen(withUUID: $0) } ?? NSScreen.main
        return max(0, screen?.safeAreaInsets.top ?? 0)
    }

    var body: some View {
        VStack {
            if let notification = detailNotification, notification.responsePreview != nil {
                CodexResponseDetailView(
                    notification: notification,
                    maximumHeight: responseMaximumHeight - permissionTopInset - 12,
                    onHeightChange: { height in
                        let totalHeight = min(responseMaximumHeight, height + permissionTopInset + 12)
                        guard abs(vm.notchSize.height - totalHeight) > 0.5 else { return }
                        withAnimation(StandardAnimations.open) {
                            vm.resizeOpenNotch(height: totalHeight)
                        }
                    },
                    onKeyboardFocusChange: { responseKeyboardFocused = $0 },
                    onDismiss: onDismissDetail
                )
                .id(CodexNotificationPresentationToken(notification))
                .padding(.top, permissionTopInset)
            } else if let permissionNotification = detailNotification {
                CodexPermissionApprovalView(
                    notification: permissionNotification
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: max(0, Self.permissionViewportHeight - permissionTopInset), alignment: .topLeading)
                .clipped()
                .padding(.top, permissionTopInset)
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
            maxWidth: detailNotification == nil ? nil : .infinity,
            alignment: .topLeading
        )
        .frame(
            height: detailNotification == nil ? nil : (detailNotification?.responsePreview == nil
                ? Self.permissionViewportHeight : max(0, vm.notchSize.height - 12)),
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
        if detailNotification != nil {
            return .opacity
                .combined(with: .scale(scale: 0.9, anchor: .top))
        }
        return .scale(scale: 0.8, anchor: .top)
            .combined(with: .opacity)
            .animation(.smooth(duration: 0.35))
    }
}
