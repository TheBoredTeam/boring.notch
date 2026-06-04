import Foundation
import Network

@MainActor
final class NetworkActivityManager {

    struct NetworkState: Equatable {
        enum Status: Equatable {
            case connected
            case disconnected
            case requiresConnection
        }

        let status: Status
        let isConstrained: Bool
        let isExpensive: Bool

        static func == (lhs: NetworkState, rhs: NetworkState) -> Bool {
            lhs.status == rhs.status
        }
    }

    enum NetworkEvent {
        case stateChanged(NetworkState, isInitial: Bool)
    }

    static let shared = NetworkActivityManager()

    private let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
    private let monitorQueue = DispatchQueue(label: "com.boringnotch.network-activity")
    private var observers: [Int: (NetworkEvent) -> Void] = [:]
    private var nextObserverId = 0
    private var latestState: NetworkState?

    private init() {
        startMonitoring()
    }

    func addObserver(_ observer: @escaping (NetworkEvent) -> Void) -> Int {
        let id = nextObserverId
        nextObserverId += 1
        observers[id] = observer

        if let latestState {
            observer(.stateChanged(latestState, isInitial: true))
        }

        return id
    }

    func removeObserver(byId id: Int) {
        observers.removeValue(forKey: id)
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.handlePathUpdate(path)
            }
        }
        monitor.start(queue: monitorQueue)
    }

    private func handlePathUpdate(_ path: NWPath) {
        let newState = normalizedState(from: path)
        let isInitial = latestState == nil

        guard isInitial || latestState != newState else { return }

        latestState = newState
        notifyObservers(event: .stateChanged(newState, isInitial: isInitial))
    }

    private func normalizedState(from path: NWPath) -> NetworkState {
        let status: NetworkState.Status

        switch path.status {
        case .satisfied:
            status = path.usesInterfaceType(.wifi) ? .connected : .disconnected
        case .requiresConnection:
            status = .requiresConnection
        case .unsatisfied:
            status = .disconnected
        @unknown default:
            status = .disconnected
        }

        return NetworkState(
            status: status,
            isConstrained: path.isConstrained,
            isExpensive: path.isExpensive
        )
    }

    private func notifyObservers(event: NetworkEvent) {
        observers.values.forEach { observer in
            observer(event)
        }
    }
}
