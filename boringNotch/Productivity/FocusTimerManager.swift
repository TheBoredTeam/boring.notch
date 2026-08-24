import AppKit
import Defaults
import Foundation

@MainActor
final class FocusTimerManager: ObservableObject {
    static let shared = FocusTimerManager()

    @Published private(set) var mode: FocusTimerMode
    @Published private(set) var remainingSeconds: TimeInterval
    @Published private(set) var isRunning: Bool
    @Published private(set) var completedFocusSessions: Int

    private var endDate: Date?
    private var tickerTask: Task<Void, Never>?

    var durationSeconds: TimeInterval {
        duration(for: mode)
    }

    var progress: Double {
        guard durationSeconds > 0 else { return 0 }
        return min(max(1 - remainingSeconds / durationSeconds, 0), 1)
    }

    var formattedRemaining: String {
        let totalSeconds = max(0, Int(remainingSeconds.rounded(.up)))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private init() {
        mode = Defaults[.focusTimerMode]
        remainingSeconds = Defaults[.focusTimerRemainingSeconds]
        isRunning = Defaults[.focusTimerIsRunning]
        completedFocusSessions = Defaults[.completedFocusSessions]
        endDate = Defaults[.focusTimerEndDate]

        if isRunning, let endDate {
            remainingSeconds = max(0, endDate.timeIntervalSinceNow)
            if remainingSeconds <= 0 {
                isRunning = false
                completeCurrentInterval()
            } else {
                startTicker()
            }
        } else if remainingSeconds <= 0 {
            remainingSeconds = duration(for: mode)
        }
    }

    deinit {
        tickerTask?.cancel()
    }

    func selectMode(_ newMode: FocusTimerMode, customMinutes: Int? = nil) {
        pause()
        mode = newMode
        if newMode == .custom, let customMinutes {
            let clampedMinutes = min(max(customMinutes, 1), 240)
            Defaults[.customTimerDurationMinutes] = clampedMinutes
            remainingSeconds = TimeInterval(clampedMinutes * 60)
        } else {
            remainingSeconds = duration(for: newMode)
        }
        persist()
    }

    func start() {
        guard !isRunning, remainingSeconds > 0 else { return }
        isRunning = true
        endDate = Date().addingTimeInterval(remainingSeconds)
        persist()
        startTicker()
    }

    func pause() {
        if let endDate, isRunning {
            remainingSeconds = max(0, endDate.timeIntervalSinceNow)
        }
        isRunning = false
        endDate = nil
        tickerTask?.cancel()
        tickerTask = nil
        persist()
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    func reset() {
        pause()
        remainingSeconds = duration(for: mode)
        persist()
    }

    func skip() {
        tickerTask?.cancel()
        tickerTask = nil
        isRunning = false
        remainingSeconds = 0
        completeCurrentInterval()
    }

    private func startTicker() {
        tickerTask?.cancel()
        tickerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, let endDate = self.endDate else { return }
                self.remainingSeconds = max(0, endDate.timeIntervalSinceNow)
                if self.remainingSeconds <= 0 {
                    self.isRunning = false
                    self.endDate = nil
                    self.completeCurrentInterval()
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func completeCurrentInterval() {
        NSSound.beep()
        BoringViewCoordinator.shared.toggleExpandingView(status: true, type: .timer)

        if mode == .focus {
            completedFocusSessions += 1
            Defaults[.completedFocusSessions] = completedFocusSessions
            mode = completedFocusSessions.isMultiple(of: 4) ? .longBreak : .shortBreak
            remainingSeconds = duration(for: mode)
            if Defaults[.autoStartFocusBreaks] {
                isRunning = true
                endDate = Date().addingTimeInterval(remainingSeconds)
                startTicker()
            }
        } else {
            mode = .focus
            remainingSeconds = duration(for: .focus)
        }
        persist()
    }

    private func duration(for mode: FocusTimerMode) -> TimeInterval {
        let minutes: Int
        switch mode {
        case .focus: minutes = Defaults[.focusDurationMinutes]
        case .shortBreak: minutes = Defaults[.shortBreakDurationMinutes]
        case .longBreak: minutes = Defaults[.longBreakDurationMinutes]
        case .custom: minutes = Defaults[.customTimerDurationMinutes]
        }
        return TimeInterval(min(max(minutes, 1), 240) * 60)
    }

    private func persist() {
        Defaults[.focusTimerMode] = mode
        Defaults[.focusTimerEndDate] = endDate
        Defaults[.focusTimerRemainingSeconds] = remainingSeconds
        Defaults[.focusTimerIsRunning] = isRunning
    }
}
