//
//  TimeActivityManager.swift
//  boringNotch
//
//  Adapted from Cris2907/not-so-boring-notch.
//

import AppKit
import Defaults
import Foundation

@MainActor
final class TimeActivityManager: ObservableObject {
    static let shared = TimeActivityManager()

    @Published private(set) var snapshot: TimeActivitySnapshot?

    var hasSession: Bool { snapshot != nil }

    private let defaults: UserDefaults
    private let now: () -> Date
    private let playCompletionSound: () -> Void
    private let persistenceKey = "timeActivitySnapshot"
    private var completionTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        observeLifecycle: Bool = true,
        playCompletionSound: @escaping () -> Void = {
            guard Defaults[.timerCompletionSound] else { return }
            if let sound = NSSound(named: NSSound.Name("Glass")) {
                sound.play()
            } else {
                NSSound.beep()
            }
        }
    ) {
        self.defaults = defaults
        self.now = now
        self.playCompletionSound = playCompletionSound
        restore()
        if observeLifecycle {
            installObservers()
        }
        reconcile()
    }

    @discardableResult
    func startTimer(duration: TimeInterval) -> Bool {
        guard snapshot == nil,
              let newSnapshot = TimeActivitySnapshot.timer(duration: duration, startedAt: now())
        else { return false }

        update(newSnapshot)
        return true
    }

    @discardableResult
    func startStopwatch() -> Bool {
        guard snapshot == nil else { return false }
        update(.stopwatch(startedAt: now()))
        return true
    }

    func pause() {
        guard var current = snapshot else { return }
        let date = now()
        if current.kind == .timer,
           current.phase == .running,
           current.remaining(at: date) <= 0 {
            reconcile()
            return
        }
        current.pause(at: date)
        update(current)
    }

    func resume() {
        guard var current = snapshot else { return }
        current.resume(at: now())
        update(current)
    }

    func reset() {
        completionTask?.cancel()
        completionTask = nil
        snapshot = nil
        persist()
    }

    func dismissCompletion() {
        guard snapshot?.phase == .finished else { return }
        reset()
    }

    func reconcile() {
        guard var current = snapshot else { return }

        if current.kind == .timer,
           current.phase == .running,
           current.remaining(at: now()) <= 0 {
            current.finish()
        }

        if current.phase == .finished && !current.completionSoundPlayed {
            playCompletionSound()
            current.completionSoundPlayed = true
        }

        update(current)
    }

    private func update(_ newSnapshot: TimeActivitySnapshot) {
        snapshot = newSnapshot
        persist()
        scheduleCompletionIfNeeded()
    }

    private func restore() {
        guard let data = defaults.data(forKey: persistenceKey),
              let restored = try? JSONDecoder().decode(TimeActivitySnapshot.self, from: data)
        else { return }
        snapshot = restored
    }

    private func persist() {
        guard let snapshot else {
            defaults.removeObject(forKey: persistenceKey)
            return
        }

        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: persistenceKey)
        }
    }

    private func scheduleCompletionIfNeeded() {
        completionTask?.cancel()
        completionTask = nil

        guard let snapshot,
              snapshot.kind == .timer,
              snapshot.phase == .running
        else { return }

        let delay = snapshot.remaining(at: now())
        guard delay > 0 else {
            reconcile()
            return
        }

        completionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.reconcile()
        }
    }

    private func installObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleLifecycleChange(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLifecycleChange(_:)),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func handleLifecycleChange(_ notification: Notification) {
        reconcile()
    }
}
