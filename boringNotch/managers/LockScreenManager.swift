//
//  LockScreenManager.swift
//  boringNotch
//

import AppKit
import Combine
import Defaults
import Foundation
import IOKit.pwr_mgt

/// How long to keep the display awake, when the user asks for it.
enum KeepAwakeMode: String, CaseIterable, Identifiable, Defaults.Serializable {
    case off
    case minutes15
    case minutes30
    case hour1
    case indefinite

    var id: String { rawValue }

    /// Nil means "no time limit"; the assertion is held until switched off.
    var duration: TimeInterval? {
        switch self {
        case .off: return 0
        case .minutes15: return 15 * 60
        case .minutes30: return 30 * 60
        case .hour1: return 60 * 60
        case .indefinite: return nil
        }
    }

    var localizedString: String {
        switch self {
        case .off: return NSLocalizedString("Off", comment: "Keep awake: disabled")
        case .minutes15: return NSLocalizedString("15 minutes", comment: "Keep awake duration")
        case .minutes30: return NSLocalizedString("30 minutes", comment: "Keep awake duration")
        case .hour1: return NSLocalizedString("1 hour", comment: "Keep awake duration")
        case .indefinite: return NSLocalizedString("Indefinitely", comment: "Keep awake duration")
        }
    }
}

/// Tracks screen lock and screen saver state, and owns the optional keep-awake
/// power assertion and lock/unlock sounds.
///
/// ## What macOS does not allow
/// Replacing or restyling the real lock screen is not possible with public APIs, and
/// neither is knowing *how* the user unlocked (password, Touch ID, Watch). What is
/// reliable is observing the lock/unlock and screen-saver notifications below, and
/// holding a documented power assertion.
@MainActor
final class LockScreenManager: ObservableObject {
    nonisolated static let shared = LockScreenManager()

    @Published private(set) var isLocked: Bool = false
    @Published private(set) var isScreenSaverActive: Bool = false

    /// Whether the screen is covered by something the user cannot see past — a lock, or a
    /// screen saver they asked the notch to survive. This is the single flag the window
    /// layer reacts to.
    @Published private(set) var isObscured: Bool = false

    /// Fired *after* `isObscured` is assigned.
    ///
    /// Deliberately not `$isObscured`: `@Published` fires in `willSet`, so a subscriber that
    /// re-reads the property inside its sink would see the stale value. Window placement
    /// depends on reading a committed state, so it gets a subject instead.
    let obscuredStateChanged = PassthroughSubject<Bool, Never>()

    private var observers: [Any] = []
    private var cancellables = Set<AnyCancellable>()

    private var assertionID: IOPMAssertionID = IOPMAssertionID(0)
    private var hasAssertion = false
    private var assertionExpiryTask: Task<Void, Never>?

    nonisolated private init() {}

    func start() {
        guard observers.isEmpty else { return }

        let center = DistributedNotificationCenter.default()
        let names = [
            "com.apple.screenIsLocked",
            "com.apple.screenIsUnlocked",
            "com.apple.screensaver.didstart",
            "com.apple.screensaver.didstop",
        ]

        for name in names {
            let observer = center.addObserver(
                forName: Notification.Name(name), object: nil, queue: .main
            ) { [weak self] notification in
                Task { @MainActor in self?.handle(notification.name.rawValue) }
            }
            observers.append(observer)
        }

        Defaults.publisher(.keepAwakeMode, options: [])
            .sink { [weak self] _ in Task { @MainActor in self?.applyKeepAwake() } }
            .store(in: &cancellables)

        // Turning the screen-saver option off while the saver is up must un-obscure.
        Defaults.publisher(.showOnScreenSaver, options: [])
            .sink { [weak self] _ in Task { @MainActor in self?.recomputeObscured() } }
            .store(in: &cancellables)

        applyKeepAwake()
    }

    func stop() {
        let center = DistributedNotificationCenter.default()
        observers.forEach { center.removeObserver($0) }
        observers.removeAll()
        cancellables.removeAll()
        assertionExpiryTask?.cancel()
        assertionExpiryTask = nil
        releaseAssertion()
    }

    private func handle(_ name: String) {
        switch name {
        case "com.apple.screenIsLocked":
            isLocked = true
            playSound(Defaults[.playSoundOnLock] ? Defaults[.lockSoundName] : nil)
            // Only tear the activities down when the user has NOT asked to see the notch
            // while locked. Doing it unconditionally emptied exactly the content the
            // setting exists to show.
            if !Defaults[.showOnLockScreen] { suspendActivities() }
        case "com.apple.screenIsUnlocked":
            isLocked = false
            playSound(Defaults[.playSoundOnUnlock] ? Defaults[.unlockSoundName] : nil)
        case "com.apple.screensaver.didstart":
            isScreenSaverActive = true
            if !Defaults[.showOnScreenSaver] { suspendActivities() }
        case "com.apple.screensaver.didstop":
            isScreenSaverActive = false
        default:
            break
        }

        recomputeObscured()
    }

    /// Derived rather than toggled, so the interleaving of screensaver and lock
    /// notifications cannot leave the flag stuck. `didstop` arriving after
    /// `screenIsUnlocked`, or a lock landing while the saver is already up, both collapse
    /// to the right answer.
    private func recomputeObscured() {
        let obscured = isLocked || (isScreenSaverActive && Defaults[.showOnScreenSaver])
        guard obscured != isObscured else { return }
        isObscured = obscured
        obscuredStateChanged.send(obscured)
    }

    /// Take down anything transient so it is not sitting there stale on return. The
    /// notch's persistent content is derived live, so nothing needs restoring.
    private func suspendActivities() {
        let coordinator = BoringViewCoordinator.shared
        if coordinator.expandingView.show {
            coordinator.toggleExpandingView(status: false, type: coordinator.expandingView.type)
        }
        coordinator.hideAllSneakPeeks()
    }

    private func playSound(_ name: String?) {
        guard let name, !name.isEmpty else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    // MARK: - Keep awake

    private func applyKeepAwake() {
        assertionExpiryTask?.cancel()
        assertionExpiryTask = nil

        let mode = Defaults[.keepAwakeMode]
        guard mode != .off else {
            releaseAssertion()
            return
        }

        guard createAssertion() else { return }

        // A timed mode releases itself; .indefinite has a nil duration and just stays.
        if let duration = mode.duration, duration > 0 {
            assertionExpiryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(duration))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    Defaults[.keepAwakeMode] = .off
                    self?.releaseAssertion()
                }
            }
        }
    }

    @discardableResult
    private func createAssertion() -> Bool {
        guard !hasAssertion else { return true }

        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Boring Notch keep awake" as CFString,
            &id
        )

        guard result == kIOReturnSuccess else {
            NSLog("⚠️ Could not create keep-awake assertion (\(result))")
            return false
        }

        assertionID = id
        hasAssertion = true
        return true
    }

    private func releaseAssertion() {
        guard hasAssertion else { return }
        IOPMAssertionRelease(assertionID)
        hasAssertion = false
        assertionID = IOPMAssertionID(0)
    }
}
