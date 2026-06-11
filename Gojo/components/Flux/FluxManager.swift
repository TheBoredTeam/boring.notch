//
//  FluxManager.swift
//  Gojo
//
//  Orchestrates the Flux night shift feature: evaluates the schedule on a
//  timer, smoothly transitions the display white point, and exposes manual
//  toggle/pause controls.
//

import AppKit
import Combine
import Defaults
import Foundation

final class FluxManager: ObservableObject {
    static let shared = FluxManager()

    @Published private(set) var currentKelvin: Double = FluxColorMath.maxKelvin
    @Published private(set) var currentPhase: FluxPhase = .day
    @Published private(set) var pausedUntil: Date?

    private let gamma = GammaController()
    private var refreshTimer: Timer?
    private var transitionTimer: Timer?
    private var resumeTimer: Timer?
    private var appliedKelvin: Double = FluxColorMath.maxKelvin
    private var transitionTarget: Double?
    private var cancellables: Set<AnyCancellable> = []
    private var started = false

    var isEnabled: Bool { Defaults[.fluxEnabled] }

    var isPaused: Bool {
        guard let pausedUntil else { return false }
        return pausedUntil > Date()
    }

    var isActive: Bool { isEnabled && !isPaused }

    private init() {}

    @MainActor
    func start() {
        guard !started else { return }
        started = true

        if Defaults[.fluxStartAtLogin], !Defaults[.fluxEnabled] {
            Defaults[.fluxEnabled] = true
        }

        let fluxKeys: [Defaults._AnyKey] = [
            .fluxEnabled, .fluxDayKelvin, .fluxSunsetKelvin, .fluxBedtimeKelvin,
            .fluxBedtimeMinutes, .fluxWindDownMinutes, .fluxLocation,
        ]
        Defaults.publisher(keys: fluxKeys, options: [])
            .sink { [weak self] in self?.refresh() }
            .store(in: &cancellables)

        // .common mode so the schedule keeps ticking during menu/drag tracking
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleScreensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        refresh()
    }

    func shutdown() {
        refreshTimer?.invalidate()
        transitionTimer?.invalidate()
        resumeTimer?.invalidate()
        gamma.restore()
    }

    func toggle() {
        Defaults[.fluxEnabled].toggle()
    }

    /// Temporarily disables flux (default: one hour), like f.lux's
    /// "disable for an hour".
    func pause(for interval: TimeInterval = 3600) {
        resumeTimer?.invalidate()
        DispatchQueue.main.async {
            self.pausedUntil = Date().addingTimeInterval(interval)
            let timer = Timer(timeInterval: interval + 1, repeats: false) { [weak self] _ in
                self?.resume()
            }
            RunLoop.main.add(timer, forMode: .common)
            self.resumeTimer = timer
            self.refresh()
        }
    }

    func resume() {
        resumeTimer?.invalidate()
        DispatchQueue.main.async {
            self.pausedUntil = nil
            self.refresh()
        }
    }

    func refresh() {
        DispatchQueue.main.async {
            self.refreshOnMain()
        }
    }

    /// Today's solar events for the stored location, nil when no location is set.
    static func solarEventsToday(at date: Date = Date()) -> SolarDayEvents? {
        guard let location = Defaults[.fluxLocation] else { return nil }
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return nil
        }
        return SolarCalculator.events(
            year: year, month: month, day: day,
            latitude: location.latitude, longitude: location.longitude,
            timeZoneOffsetMinutes: Double(TimeZone.current.secondsFromGMT(for: date)) / 60
        )
    }

    /// The schedule configuration as currently stored in Defaults.
    static var currentConfig: FluxScheduleConfig {
        FluxScheduleConfig(
            dayKelvin: Defaults[.fluxDayKelvin],
            sunsetKelvin: Defaults[.fluxSunsetKelvin],
            bedtimeKelvin: Defaults[.fluxBedtimeKelvin],
            bedtimeMinutes: Double(Defaults[.fluxBedtimeMinutes]),
            windDownMinutes: Double(Defaults[.fluxWindDownMinutes])
        )
    }

    static func evaluateSchedule(at date: Date = Date()) -> (kelvin: Double, phase: FluxPhase) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let nowMinutes = Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
        return FluxScheduleEngine.evaluate(
            nowMinutes: nowMinutes, solar: solarEventsToday(at: date), config: currentConfig)
    }

    private func refreshOnMain() {
        let targetKelvin: Double
        if isActive {
            let evaluation = Self.evaluateSchedule()
            currentPhase = evaluation.phase
            targetKelvin = evaluation.kelvin
        } else {
            currentPhase = .day
            targetKelvin = FluxColorMath.maxKelvin
        }
        moveToward(targetKelvin)
    }

    private func moveToward(_ target: Double) {
        if transitionTimer?.isValid == true, let inFlight = transitionTarget {
            // A periodic refresh re-derived the target we're already easing
            // toward — let the ease finish instead of snapping to the end.
            if abs(target - inFlight) < 1 {
                return
            }
            // The target moved while easing (slider scrubbing) — track it live.
            transitionTimer?.invalidate()
            transitionTarget = nil
            apply(target)
            return
        }

        transitionTimer?.invalidate()
        let start = appliedKelvin
        let delta = target - start

        // Small periodic drift applies directly; bigger one-shot jumps (toggle,
        // phase boundary) ease in over a second.
        guard abs(delta) > 25 else {
            apply(target)
            return
        }

        let steps = 30
        var step = 0
        transitionTarget = target
        // .common mode so the ease keeps animating during menu/drag tracking
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            step += 1
            let progress = Double(step) / Double(steps)
            let eased = 0.5 - cos(progress * .pi) / 2
            self.apply(start + delta * eased)
            if step >= steps {
                timer.invalidate()
                self.transitionTarget = nil
                self.apply(target)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        transitionTimer = timer
    }

    private func apply(_ kelvin: Double) {
        appliedKelvin = kelvin
        currentKelvin = kelvin
        if kelvin >= FluxColorMath.maxKelvin - 1 {
            gamma.restore()
        } else {
            gamma.apply(FluxColorMath.whitePoint(kelvin: kelvin))
        }
    }

    @objc private func handleWake() {
        refresh()
    }

    @objc private func handleScreensChanged() {
        // Newly connected displays come up with a clean gamma table
        if gamma.isModified {
            gamma.apply(FluxColorMath.whitePoint(kelvin: appliedKelvin))
        }
    }
}
