//
//  SteadyCheckInScheduler.swift
//  spruceNotch
//

import AppKit
import Defaults
import Foundation

@MainActor
final class SteadyCheckInScheduler {
    static let shared = SteadyCheckInScheduler()

    private var workItem: DispatchWorkItem?
    private var screenLocked = false
    private var pendingPromptAfterUnlock = false
    private var observers: [NSObjectProtocol] = []

    private init() {}

    func register() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.schedulePrompt(after: Defaults[.steadyCheckInDelaySeconds]) }
        })

        let dist = DistributedNotificationCenter.default()
        observers.append(dist.addObserver(
            forName: NSNotification.Name(rawValue: "com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.screenLocked = true }
        })
        observers.append(dist.addObserver(
            forName: NSNotification.Name(rawValue: "com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleUnlock() }
        })
    }

    private func handleUnlock() {
        screenLocked = false
        if pendingPromptAfterUnlock {
            pendingPromptAfterUnlock = false
            schedulePrompt(after: Defaults[.steadyCheckInDelaySeconds])
        }
    }

    /// Call once at launch (e.g. first session of the day).
    func scheduleSessionStartPrompt() {
        schedulePrompt(after: Defaults[.steadyCheckInDelaySeconds])
    }

    private func schedulePrompt(after delay: TimeInterval) {
        guard Defaults[.steadyCheckInEnabled] else { return }

        workItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.fireScheduledPrompt() }
        }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func fireScheduledPrompt() {
        guard Defaults[.steadyCheckInEnabled] else { return }
        guard Self.isWeekday() else { return }

        let today = SteadyCheckInManager.dayString()
        if !Defaults[.steadyCheckInLastCompletedDay].isEmpty,
           Defaults[.steadyCheckInLastCompletedDay] == today
        {
            return
        }
        if !Defaults[.steadyCheckInLastIgnoredDay].isEmpty,
           Defaults[.steadyCheckInLastIgnoredDay] == today
        {
            return
        }
        if Defaults[.steadyCheckInScheduledPromptDay] == today {
            return
        }

        if screenLocked {
            pendingPromptAfterUnlock = true
            return
        }

        Defaults[.steadyCheckInScheduledPromptDay] = today
        SpruceViewCoordinator.shared.currentView = .steadyCheckIn
        SteadyCheckInManager.shared.beginScheduledFlow()
    }

    private static func isWeekday() -> Bool {
        let w = Calendar.current.component(.weekday, from: Date())
        return (2...6).contains(w)
    }
}
