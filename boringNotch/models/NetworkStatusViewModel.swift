import Foundation
import SwiftUI

class NetworkStatusViewModel: ObservableObject {

    @ObservedObject var coordinator = BoringViewCoordinator.shared

    @Published private(set) var state = NetworkActivityManager.NetworkState(
        status: .disconnected,
        isConstrained: false,
        isExpensive: false
    )

    private let networkManager = NetworkActivityManager.shared
    private var networkManagerId: Int?

    static let shared = NetworkStatusViewModel()

    private init() {
        setupMonitor()
    }

    var statusText: String {
        switch state.status {
        case .connected:
            return "Wi-Fi Connected"
        case .disconnected:
            return "Wi-Fi Disconnected"
        case .requiresConnection:
            return "Wi-Fi Unavailable"
        }
    }

    var symbolName: String {
        switch state.status {
        case .connected:
            return "wifi"
        case .disconnected, .requiresConnection:
            return "wifi.slash"
        }
    }

    var isConnected: Bool {
        state.status == .connected
    }

    var preferredNotificationWidth: CGFloat {
        textWidth + 76 + 16
    }

    var textWidth: CGFloat {
        switch state.status {
        case .connected:
            return 190
        case .disconnected:
            return 235
        case .requiresConnection:
            return 210
        }
    }

    private func setupMonitor() {
        networkManagerId = networkManager.addObserver { [weak self] event in
            self?.handleNetworkEvent(event)
        }
    }

    private func handleNetworkEvent(_ event: NetworkActivityManager.NetworkEvent) {
        switch event {
        case .stateChanged(let newState, let isInitial):
            if isInitial {
                state = newState
                return
            }

            withAnimation {
                state = newState
            }

            notifyImportantChangeStatus()
        }
    }

    private func notifyImportantChangeStatus(delay: Double = 0.0) {
        Task {
            try? await Task.sleep(for: .seconds(delay))
            coordinator.toggleExpandingView(status: true, type: .network)
        }
    }

    deinit {
        guard let networkManagerId else { return }
        let manager = networkManager
        Task { @MainActor in
            manager.removeObserver(byId: networkManagerId)
        }
    }
}
