//
//  ScreenTimeManager.swift
//  boringNotch
//
//  Self-tracking screen-time engine. Follows the frontmost application via NSWorkspace
//  and accumulates per-app foreground time locally (no Screen Time entitlement / Full
//  Disk Access). The deterministic accounting lives in ScreenTimeModels (pure, tested);
//  this type owns the AppKit wiring, persistence, and lifecycle.
//

import AppKit
import Combine
import Defaults
import Foundation

/// All work happens on the main run loop (observers use `queue: .main`), matching the
/// app's other ObservableObject managers; no actor isolation is needed.
final class ScreenTimeManager: ObservableObject {
    static let shared = ScreenTimeManager()

    /// Today's usage (logical day per the configured reset time). Drives the UI.
    @Published private(set) var today: DailyUsage

    private var store: UsageStore
    private let now: () -> Date
    private let calendar: Calendar

    // Current foreground segment.
    private var currentBundleID: String?
    private var currentName: String = ""
    private var segmentStart: Date?
    private var isPaused = false
    private var started = false

    private var flushTimer: Timer?
    private var lastSave: Date = .distantPast
    private var observers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []

    private let flushInterval: TimeInterval = 20
    private let minSaveInterval: TimeInterval = 5

    private init(now: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
        self.store = Defaults[.screenTimeStore]
        let key = ScreenTimeManager.dayStart(now(), calendar: calendar)
        self.today = self.store.daily(for: key) ?? DailyUsage(dayStart: key)
    }

    // MARK: Lifecycle

    func start() {
        guard !started, Defaults[.screenTimeEnabled] else { return }
        started = true

        prune()
        refreshToday()

        let wsCenter = NSWorkspace.shared.notificationCenter
        observers.append(wsCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.handleActivation(app)
        })
        observers.append(wsCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.pause() })
        observers.append(wsCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.resume() })

        let dnc = DistributedNotificationCenter.default()
        distributedObservers.append(dnc.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in self?.pause() })
        distributedObservers.append(dnc.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in self?.resume() })

        beginSegment(for: NSWorkspace.shared.frontmostApplication)

        let timer = Timer(timeInterval: flushInterval, repeats: true) { [weak self] _ in
            self?.flushSegment()
        }
        RunLoop.main.add(timer, forMode: .common)
        flushTimer = timer
    }

    /// Flush and tear down. Call on app termination.
    func stop() {
        guard started else { return }
        flushSegment()
        save(force: true)
        flushTimer?.invalidate()
        flushTimer = nil
        let wsCenter = NSWorkspace.shared.notificationCenter
        observers.forEach { wsCenter.removeObserver($0) }
        observers.removeAll()
        let dnc = DistributedNotificationCenter.default()
        distributedObservers.forEach { dnc.removeObserver($0) }
        distributedObservers.removeAll()
        started = false
    }

    // MARK: Event handling

    private func handleActivation(_ app: NSRunningApplication?) {
        // Attribute the time spent in the previous app before switching.
        flushSegment()
        guard let app, let bundleID = app.bundleIdentifier else {
            currentBundleID = nil
            segmentStart = nil
            return
        }
        if Defaults[.screenTimeIgnoredApps].contains(bundleID) {
            // Don't track or count switches into ignored apps.
            currentBundleID = nil
            currentName = ""
            segmentStart = isPaused ? nil : now()
            return
        }
        // A real switch into a tracked app.
        store.recordSwitch(on: dayStartForNow())
        beginSegment(for: app)
        refreshToday()
        save(force: false)
    }

    private func beginSegment(for app: NSRunningApplication?) {
        guard !isPaused, let app, let bundleID = app.bundleIdentifier,
              !Defaults[.screenTimeIgnoredApps].contains(bundleID) else {
            currentBundleID = nil
            currentName = ""
            segmentStart = isPaused ? nil : now()
            return
        }
        currentBundleID = bundleID
        currentName = app.localizedName ?? bundleID
        segmentStart = now()
    }

    /// Fold the live segment into the store (splitting across day boundaries) and reset
    /// the segment start to now so time keeps accruing for the same app.
    private func flushSegment() {
        defer { refreshToday() }
        guard !isPaused, let bundleID = currentBundleID, let start = segmentStart else { return }
        let end = now()
        guard end > start else { return }
        ScreenTimeMath.attribute(
            from: start, to: end,
            bundleID: bundleID, displayName: currentName,
            into: &store,
            resetHour: Defaults[.screenTimeResetHour],
            resetMinute: Defaults[.screenTimeResetMinute],
            calendar: calendar
        )
        segmentStart = end
        prune()
        save(force: false)
    }

    private func pause() {
        guard !isPaused else { return }
        flushSegment()
        isPaused = true
        segmentStart = nil
        save(force: true)
    }

    private func resume() {
        guard isPaused else { return }
        isPaused = false
        beginSegment(for: NSWorkspace.shared.frontmostApplication)
    }

    // MARK: Helpers

    private func dayStartForNow() -> Date {
        ScreenTimeManager.dayStart(now(), calendar: calendar)
    }

    private static func dayStart(_ date: Date, calendar: Calendar) -> Date {
        ScreenTimeMath.dayStart(
            for: date,
            resetHour: Defaults[.screenTimeResetHour],
            resetMinute: Defaults[.screenTimeResetMinute],
            calendar: calendar
        )
    }

    private func refreshToday() {
        let key = dayStartForNow()
        today = store.daily(for: key) ?? DailyUsage(dayStart: key)
    }

    private func prune() {
        store.prune(retentionDays: Defaults[.screenTimeRetentionDays], now: now(), calendar: calendar)
    }

    private func save(force: Bool) {
        let t = now()
        if !force && t.timeIntervalSince(lastSave) < minSaveInterval { return }
        lastSave = t
        Defaults[.screenTimeStore] = store
    }

    // MARK: UI-facing reads

    /// A resolver built from the user's current category overrides.
    func makeResolver() -> CategoryResolver {
        CategoryResolver(overrides: Defaults[.screenTimeCategoryOverrides])
    }

    /// Today's usage grouped into category slices for the donut, sorted descending.
    func categorySlices(using resolver: CategoryResolver) -> [(category: AppCategory, seconds: TimeInterval)] {
        ScreenTimeMath.categoryTotals(for: today) { resolver.category(for: $0) }
    }
}
