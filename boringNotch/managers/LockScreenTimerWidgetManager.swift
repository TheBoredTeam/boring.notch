//
//  LockScreenTimerWidgetManager.swift
//  boringNotch
//

import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI

@MainActor
final class LockScreenTimerWidgetManager: ObservableObject {
    static let shared = LockScreenTimerWidgetManager()

    @Published private(set) var remainingTime: TimeInterval = 0
    @Published private(set) var isTimerActive = false
    @Published private(set) var isPaused = false

    private let panel = LockScreenWidgetPanel(allowsInteraction: true)
    private var deadline: Date?
    private var pausedRemainingTime: TimeInterval = 0
    private var ticker: Timer?
    private var isLocked = false
    private var cancellables = Set<AnyCancellable>()

    private init() {
        Defaults.publisher(.enableLockScreenTimerWidget)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        Defaults.publisher(.showOnLockScreen)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        Defaults.publisher(.lockScreenTimerVerticalOffset)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        Defaults.publisher(.lockScreenTimerWidgetWidth)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    func screenDidLock() {
        isLocked = true
        refresh()
    }

    func screenDidUnlock() {
        isLocked = false
        panel.hide()
    }

    func start(minutes: Double) {
        let duration = max(1, minutes * 60)
        pausedRemainingTime = duration
        remainingTime = duration
        deadline = Date().addingTimeInterval(duration)
        isPaused = false
        isTimerActive = true
        startTicker()
        refresh()
    }

    func togglePause() {
        guard isTimerActive else { return }

        if isPaused {
            deadline = Date().addingTimeInterval(pausedRemainingTime)
            isPaused = false
            startTicker()
        } else {
            pausedRemainingTime = remainingTime
            deadline = nil
            isPaused = true
            stopTicker()
        }
        refresh()
    }

    func cancel() {
        stopTicker()
        deadline = nil
        pausedRemainingTime = 0
        remainingTime = 0
        isPaused = false
        isTimerActive = false
        refresh()
    }

    var formattedRemainingTime: String {
        let seconds = max(0, Int(remainingTime.rounded(.up)))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainder = seconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%02d:%02d", minutes, remainder)
    }

    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if let ticker {
            RunLoop.main.add(ticker, forMode: .common)
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard let deadline else { return }
        remainingTime = max(0, deadline.timeIntervalSinceNow)
        if remainingTime == 0 {
            cancel()
        }
    }

    private var shouldDisplay: Bool {
        isLocked
            && isTimerActive
            && Defaults[.showOnLockScreen]
            && Defaults[.enableLockScreenTimerWidget]
    }

    private func refresh() {
        guard shouldDisplay, let context = LockScreenDisplayContextProvider.shared.snapshot() else {
            panel.hide()
            return
        }

        let width = min(max(CGFloat(Defaults[.lockScreenTimerWidgetWidth]), 260), 520)
        let size = CGSize(width: width, height: 72)
        let frame = LockScreenWidgetLayout.timer(
            in: context.frame,
            size: size,
            offset: CGFloat(Defaults[.lockScreenTimerVerticalOffset])
        )
        panel.show(LockScreenTimerWidgetView(), frame: frame, cornerRadius: 24)
    }
}

private struct LockScreenTimerWidgetView: View {
    @ObservedObject private var timer = LockScreenTimerWidgetManager.shared

    var body: some View {
        LockScreenWidgetCard {
            HStack(spacing: 14) {
                Image(systemName: "timer")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 30)

                Text(timer.formattedRemainingTime)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: timer.togglePause) {
                    Image(systemName: timer.isPaused ? "play.fill" : "pause.fill")
                        .frame(width: 30, height: 30)
                        .background(.primary.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(timer.isPaused
                    ? LockScreenText.value("Resume timer", "继续计时")
                    : LockScreenText.value("Pause timer", "暂停计时"))

                Button(action: timer.cancel) {
                    Image(systemName: "xmark")
                        .frame(width: 30, height: 30)
                        .background(.primary.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LockScreenText.value("Cancel timer", "取消计时"))
            }
            .padding(.horizontal, 16)
            .frame(height: 72)
        }
    }
}
