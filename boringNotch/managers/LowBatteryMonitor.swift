//
//  LowBatteryMonitor.swift
//  boringNotch
//

import Combine
import Defaults
import Foundation

/// Shows a one-shot low-battery warning in the notch when the battery crosses into the
/// configured low range.
///
/// Monitoring is entirely event driven: it rides on `BatteryActivityManager`'s existing
/// `IOPSNotificationCreateRunLoopSource` subscription, which the system also fires on
/// wake, so there is no timer and no polling here.
@MainActor
final class LowBatteryMonitor: ObservableObject {
    nonisolated static let shared = LowBatteryMonitor()

    /// Level to show in the warning, 0...100.
    @Published private(set) var level: Int = 0

    private var state = LowBatteryState()
    private let batteryManager = BatteryActivityManager.shared
    private var observerId: Int?
    private var cancellables = Set<AnyCancellable>()

    private var isPluggedIn: Bool = false

    nonisolated private init() {}

    func start() {
        guard observerId == nil else { return }

        let info = batteryManager.initializeBatteryInfo()
        level = Int(info.currentCapacity.rounded())
        isPluggedIn = info.isPluggedIn

        observerId = batteryManager.addObserver { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }

        // Re-evaluate when the user changes the setting, so a newly lowered threshold or a
        // freshly enabled warning takes effect without waiting for the next battery event.
        Defaults.publisher(.lowBatteryWarning, options: [])
            .sink { [weak self] _ in Task { @MainActor in self?.evaluate() } }
            .store(in: &cancellables)

        Defaults.publisher(.lowBatteryThreshold, options: [])
            .sink { [weak self] _ in Task { @MainActor in self?.evaluate() } }
            .store(in: &cancellables)

        // Seed from the current reading. A Mac launched already below the threshold still
        // deserves to be told once.
        evaluate()
    }

    func stop() {
        if let observerId {
            batteryManager.removeObserver(byId: observerId)
            self.observerId = nil
        }
        cancellables.removeAll()
    }

    private func handle(_ event: BatteryActivityManager.BatteryEvent) {
        switch event {
        case .batteryLevelChanged(let newLevel):
            level = Int(newLevel.rounded())
            evaluate()
        case .powerSourceChanged(let pluggedIn):
            isPluggedIn = pluggedIn
            evaluate()
        case .isChargingChanged:
            evaluate()
        default:
            break
        }
    }

    private func evaluate() {
        let input = LowBatteryState.Input(
            hasBattery: batteryManager.hasBattery,
            isPluggedIn: isPluggedIn,
            level: level,
            threshold: Defaults[.lowBatteryThreshold],
            enabled: Defaults[.lowBatteryWarning]
        )

        let shouldWarn = state.update(input)

        // Plugging in mid-warning should take the warning down rather than leave a stale
        // "running low" message on screen.
        if isPluggedIn || !state.isWarningActive {
            let coordinator = BoringViewCoordinator.shared
            if coordinator.expandingView.show, coordinator.expandingView.type == .lowBattery {
                coordinator.toggleExpandingView(status: false, type: .lowBattery)
            }
        }

        guard shouldWarn else { return }

        NSLog("🔋 Low battery warning at \(level)% (threshold \(input.threshold)%)")
        BoringViewCoordinator.shared.toggleExpandingView(
            status: true,
            type: .lowBattery,
            value: CGFloat(level)
        )
    }
}
