import Foundation
import IOKit.pwr_mgt
import Defaults

final class CaffeineManager: ObservableObject {
    static let shared = CaffeineManager()

    @Published private(set) var isActive: Bool = false

    private var assertionID: IOPMAssertionID = .init(0)
    private var hasAssertion: Bool = false
    private var safetyTimer: Timer?
    private var batteryObserverID: Int?

    private init() {
        setupBatteryObserver()
    }

    func activate() {
        guard !hasAssertion else { return }

        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Boring Notch Keep Awake" as CFString,
            &id
        )

        guard result == kIOReturnSuccess else { return }

        assertionID = id
        hasAssertion = true
        isActive = true
        startSafetyTimer()
    }

    func deactivate() {
        guard hasAssertion else { return }

        IOPMAssertionRelease(assertionID)
        assertionID = IOPMAssertionID(0)
        hasAssertion = false
        isActive = false

        safetyTimer?.invalidate()
        safetyTimer = nil
    }

    func toggle() {
        isActive ? deactivate() : activate()
    }

    private func startSafetyTimer() {
        safetyTimer?.invalidate()
        let timeout = Defaults[.caffeineSafetyTimeout].rawValue
        guard timeout > 0 else { return }

        // Must be on main thread since we're already there (called from UI)
        safetyTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            self?.deactivate()
        }
    }

    private func setupBatteryObserver() {
        batteryObserverID = BatteryActivityManager.shared.addObserver { [weak self] event in
            // BatteryActivityManager dispatches observer calls on DispatchQueue.main
            guard let self else { return }
            if case .batteryLevelChanged(let level) = event {
                self.checkBatteryThreshold(level: level)
            }
        }
    }

    private func checkBatteryThreshold(level: Float) {
        guard isActive, !BatteryStatusViewModel.shared.isPluggedIn else { return }
        if level <= Float(Defaults[.caffeineLowBatteryCutoff]) {
            deactivate()
        }
    }

    deinit {
        if let id = batteryObserverID {
            BatteryActivityManager.shared.removeObserver(byId: id)
        }
        // Release assertion directly — deinit may not be on main thread
        if hasAssertion {
            IOPMAssertionRelease(assertionID)
        }
    }
}
