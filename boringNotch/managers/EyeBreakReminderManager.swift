import AppKit
import Combine
import Defaults
import Foundation

struct EyeBreakBannerState: Equatable {
    var remainingSeconds: Int
    var breakDurationSeconds: Int
    var snoozeMinutes: Int
}

struct EyeBreakDebugState: Equatable {
    var activeSecondsAccumulated: Int = 0
    var duePending: Bool = false
    var snoozeUntil: Date? = nil
    var isSystemSleeping: Bool = false
    var isDisplaySleeping: Bool = false
    var isSessionActive: Bool = true
    var isAccruingActiveTime: Bool = false
    var bannerVisible: Bool = false
    var bannerRemainingSeconds: Int? = nil
}

@MainActor
final class EyeBreakReminderManager: ObservableObject {
    static let shared = EyeBreakReminderManager()

    @Published private(set) var banner: EyeBreakBannerState?
    @Published private(set) var debugState: EyeBreakDebugState = .init()

    private var activeSecondsAccumulated: TimeInterval = 0
    private var duePending: Bool = false
    private var snoozeUntil: Date?
    private var debugIgnoreActivityUntilDismiss: Bool = false
    private var lastMonitorDate: Date?
    private var didPauseMediaForReminder: Bool = false

    private var isSystemSleeping: Bool = false
    private var isDisplaySleeping: Bool = false
    private var isSessionActive: Bool = true

    private var monitorTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var mediaCommandTask: Task<Void, Never>?

    private var willSleepObserver: Any?
    private var didWakeObserver: Any?
    private var screensDidSleepObserver: Any?
    private var screensDidWakeObserver: Any?
    private var sessionResignObserver: Any?
    private var sessionBecomeObserver: Any?
    private var cancellables = Set<AnyCancellable>()

    private let accrualTickSeconds: TimeInterval = 5

    private init() {
        setupSystemStateObservers()
        setupDefaultsObservers()
        startMonitoringIfNeeded()
        updateDebugState()
    }

    deinit {
        monitorTask?.cancel()
        countdownTask?.cancel()
        mediaCommandTask?.cancel()

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        if let observer = willSleepObserver {
            workspaceCenter.removeObserver(observer)
        }
        if let observer = didWakeObserver {
            workspaceCenter.removeObserver(observer)
        }
        if let observer = screensDidSleepObserver {
            workspaceCenter.removeObserver(observer)
        }
        if let observer = screensDidWakeObserver {
            workspaceCenter.removeObserver(observer)
        }
        if let observer = sessionResignObserver {
            workspaceCenter.removeObserver(observer)
        }
        if let observer = sessionBecomeObserver {
            workspaceCenter.removeObserver(observer)
        }

        cancellables.removeAll()
    }

    func completeBreak() {
        guard banner != nil else { return }
        resetCycle()
    }

    func skipBreak() {
        guard banner != nil else { return }
        resetCycle()
    }

    func snoozeBreak() {
        guard banner != nil else { return }

        dismissBanner()
        resumeMediaIfNeeded()
        duePending = true
        snoozeUntil = Date().addingTimeInterval(TimeInterval(validSnoozeMinutes() * 60))
        updateDebugState()
    }

    func debugTriggerReminderNow() {
        snoozeUntil = nil
        duePending = true
        debugIgnoreActivityUntilDismiss = true
        presentBreakBanner(force: true)
        updateDebugState()
    }

    func debugResetState() {
        clearAllState()
    }

    private func setupDefaultsObservers() {
        Defaults.publisher(.eyeBreakEnabled)
            .receive(on: RunLoop.main)
            .sink { [weak self] change in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if !change.newValue {
                        self.clearAllState()
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func setupSystemStateObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter

        willSleepObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isSystemSleeping = true
                self.handleNonAccruingTransition()
            }
        }

        didWakeObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isSystemSleeping = false
            }
        }

        screensDidSleepObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isDisplaySleeping = true
                self.handleNonAccruingTransition()
            }
        }

        screensDidWakeObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isDisplaySleeping = false
            }
        }

        sessionResignObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isSessionActive = false
                self.handleNonAccruingTransition()
            }
        }

        sessionBecomeObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isSessionActive = true
            }
        }
    }

    private func startMonitoringIfNeeded() {
        guard monitorTask == nil else { return }

        monitorTask = Task { @MainActor [weak self] in
            guard let self = self else { return }

            while !Task.isCancelled {
                self.monitorTick()
                try? await Task.sleep(for: .seconds(self.accrualTickSeconds))
            }
        }
    }

    private func monitorTick() {
        let now = Date()
        let previousTick = lastMonitorDate ?? now
        let elapsedSinceLastTick = max(0, now.timeIntervalSince(previousTick))
        let clampedElapsed = min(elapsedSinceLastTick, accrualTickSeconds * 3)

        defer { updateDebugState() }
        defer { lastMonitorDate = now }

        guard Defaults[.eyeBreakEnabled] else {
            clearAllState()
            return
        }

        if banner != nil {
            if !debugIgnoreActivityUntilDismiss && !canCountActiveTimeNow() {
                resetCycle()
            }
            return
        }

        if let snoozeUntil, Date() < snoozeUntil {
            return
        }

        if snoozeUntil != nil {
            snoozeUntil = nil
            duePending = true
        }

        if duePending {
            if canCountActiveTimeNow() {
                presentBreakBanner()
            }
            return
        }

        guard canCountActiveTimeNow() else { return }

        activeSecondsAccumulated += clampedElapsed
        if activeSecondsAccumulated >= TimeInterval(validIntervalMinutes() * 60) {
            duePending = true
            presentBreakBanner()
        }
    }

    private func presentBreakBanner(force: Bool = false) {
        guard banner == nil else { return }
        if !force {
            guard canCountActiveTimeNow() else { return }
        }

        let breakSeconds = validBreakDurationSeconds()
        banner = EyeBreakBannerState(
            remainingSeconds: breakSeconds,
            breakDurationSeconds: breakSeconds,
            snoozeMinutes: validSnoozeMinutes()
        )

        pauseMediaIfNeeded()

        if Defaults[.eyeBreakSoundEnabled] {
            playReminderStartSound()
        }
        updateDebugState()

        countdownTask?.cancel()
        countdownTask = Task { @MainActor [weak self] in
            guard let self = self else { return }

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }

                guard var currentBanner = self.banner else { return }

                if !self.debugIgnoreActivityUntilDismiss && !self.canCountActiveTimeNow() {
                    self.resetCycle()
                    return
                }

                currentBanner.remainingSeconds -= 1

                if currentBanner.remainingSeconds <= 0 {
                    self.onCountdownCompleted()
                } else {
                    self.banner = currentBanner
                    self.updateDebugState()
                }
            }
        }
    }

    private func onCountdownCompleted() {
        if Defaults[.eyeBreakSoundEnabled] {
            playReminderFinishSound()
        }
        resetCycle()
    }

    private func handleNonAccruingTransition() {
        if banner != nil {
            resetCycle()
        }
    }

    private func resetCycle() {
        dismissBanner()
        resumeMediaIfNeeded()
        activeSecondsAccumulated = 0
        duePending = false
        snoozeUntil = nil
        debugIgnoreActivityUntilDismiss = false
        lastMonitorDate = Date()
        updateDebugState()
    }

    private func dismissBanner() {
        countdownTask?.cancel()
        countdownTask = nil
        banner = nil
        updateDebugState()
    }

    private func clearAllState() {
        dismissBanner()
        resumeMediaIfNeeded()
        activeSecondsAccumulated = 0
        duePending = false
        snoozeUntil = nil
        debugIgnoreActivityUntilDismiss = false
        lastMonitorDate = Date()
        updateDebugState()
    }

    private func updateDebugState() {
        let accruing = Defaults[.eyeBreakEnabled] && !duePending && banner == nil && canCountActiveTimeNow()

        debugState = EyeBreakDebugState(
            activeSecondsAccumulated: Int(activeSecondsAccumulated),
            duePending: duePending,
            snoozeUntil: snoozeUntil,
            isSystemSleeping: isSystemSleeping,
            isDisplaySleeping: isDisplaySleeping,
            isSessionActive: isSessionActive,
            isAccruingActiveTime: accruing,
            bannerVisible: banner != nil,
            bannerRemainingSeconds: banner?.remainingSeconds
        )
    }

    private func validIntervalMinutes() -> Int {
        max(5, Defaults[.eyeBreakIntervalMinutes])
    }

    private func validBreakDurationSeconds() -> Int {
        max(5, Defaults[.eyeBreakDurationSeconds])
    }

    private func validSnoozeMinutes() -> Int {
        max(1, Defaults[.eyeBreakSnoozeMinutes])
    }

    private func canCountActiveTimeNow() -> Bool {
        !isSystemSleeping && !isDisplaySleeping && isSessionActive
    }

    private func pauseMediaIfNeeded() {
        guard Defaults[.eyeBreakPauseMediaOnPopup] else { return }
        guard MusicManager.shared.isPlaying else { return }
        didPauseMediaForReminder = true
        enqueueMediaCommand {
            await MusicManager.shared.pauseAsync()
        }
    }

    private func resumeMediaIfNeeded() {
        guard didPauseMediaForReminder else { return }
        didPauseMediaForReminder = false
        enqueueMediaCommand {
            await MusicManager.shared.playAsync()
        }
    }

    private func enqueueMediaCommand(_ operation: @escaping @MainActor () async -> Void) {
        let previous = mediaCommandTask
        mediaCommandTask = Task { @MainActor in
            _ = await previous?.result
            guard !Task.isCancelled else { return }
            await operation()
        }
    }

    private func playReminderStartSound() {
        playSound(candidates: ["Pop", "Tink", "Glass"])
    }

    private func playReminderFinishSound() {
        playSound(candidates: ["Hero", "Pop", "Glass"])
    }

    private func playSound(candidates: [String]) {
        for candidate in candidates {
            if let sound = NSSound(named: NSSound.Name(candidate)) {
                sound.play()
                return
            }
        }
    }
}
