//  BrightnessManager.swift
//  boringNotch
//
//  Created by JeanLouis on 08/22/24.

import AppKit

final class BrightnessManager: ObservableObject {
	static let shared = BrightnessManager()

	@Published private(set) var rawBrightness: Float = 0
	@Published private(set) var animatedBrightness: Float = 0
	@Published private(set) var lastChangeAt: Date = .distantPast

	private let visibleDuration: TimeInterval = 1.2
	private let client = XPCHelperClient.shared

	/// Key repeats arriving while an XPC call is in flight accumulate here so
	/// no press is lost — each press used to trigger its own 3-RPC sequence
	/// (adjust + read + display lookup), and they would queue behind each other.
	private var pendingDelta: Float = 0
	private var flushTask: Task<Void, Never>?

	/// The brightness target display only changes with the display set.
	private var cachedTargetUUID: String?
	private var screenParametersObserver: (any NSObjectProtocol)?

	private init() {
		refresh()
		screenParametersObserver = NotificationCenter.default.addObserver(
			forName: NSApplication.didChangeScreenParametersNotification,
			object: nil,
			queue: .main
		) { [weak self] _ in
			self?.cachedTargetUUID = nil
		}
	}

	/// Determine which screen UUID should be used for brightness OSDs
	/// when the built‑in source is selected.  This mirrors the logic in the
	/// XPC helper, which chooses the menu-bar display if it supports brightness and
	/// otherwise falls back to an internal panel.
	/// Cached; invalidated when the display configuration changes.
	func brightnessTargetUUID() async -> String? {
		if let cachedTargetUUID { return cachedTargetUUID }
		var resolved: String?
		if let displayID = await client.displayIDForBrightness() {
			resolved = NSScreen.screens.first(where: { $0.cgDisplayID == displayID })?.displayUUID
		}
		resolved = resolved ?? NSScreen.main?.displayUUID
		cachedTargetUUID = resolved
		return resolved
	}

	var shouldShowOverlay: Bool { Date().timeIntervalSince(lastChangeAt) < visibleDuration }

	func refresh() {
		Task { @MainActor in
			if let current = await client.currentScreenBrightness() {
				publish(brightness: current, touchDate: false)
			}
		}
	}

	@MainActor func setRelative(delta: Float) {
		pendingDelta += delta
		guard flushTask == nil else { return }
		flushTask = Task { @MainActor in
			defer { flushTask = nil }
			while pendingDelta != 0 {
				let delta = pendingDelta
				pendingDelta = 0
				// One RPC delivers both the adjustment and the resulting value.
				guard let current = await client.adjustScreenBrightness(by: delta) else {
					refresh()
					return
				}
				publish(brightness: current, touchDate: true)

				let uuid = await brightnessTargetUUID()
				NotchUIEventBus.events.send(.sneakPeek(type: .brightness, value: CGFloat(current), targetScreenUUID: uuid))
			}
		}
	}

	func setAbsolute(value: Float) {
		let clamped = max(0, min(1, value))
		Task { @MainActor in
			let ok = await client.setScreenBrightness(clamped)
			if ok {
				publish(brightness: clamped, touchDate: true)
                // optionally show peek when user uses slider/controls
                let targetUUID = await brightnessTargetUUID()
                NotchUIEventBus.events.send(.sneakPeek(type: .brightness, value: CGFloat(clamped), targetScreenUUID: targetUUID))
			} else {
				refresh()
			}
		}
	}

	private func publish(brightness: Float, touchDate: Bool) {
		DispatchQueue.main.async {
			if self.rawBrightness != brightness || touchDate {
				if touchDate { self.lastChangeAt = Date() }
				self.rawBrightness = brightness
				self.animatedBrightness = brightness
			}
		}
	}
}

// (DisplayServices helpers moved into XPC helper)

// MARK: - Keyboard Backlight Controller
final class KeyboardBacklightManager: ObservableObject {
	static let shared = KeyboardBacklightManager()

	@Published private(set) var rawBrightness: Float = 0
	@Published private(set) var lastChangeAt: Date = .distantPast

	private let visibleDuration: TimeInterval = 1.2
	private let client = XPCHelperClient.shared

	/// Deltas accumulate while a read or set call is in flight so key repeats
	/// are coalesced into the next adjustment.
	private var pendingDelta: Float = 0
	/// Size of one key press in the pending batch, used to keep the level on
	/// the same grid as the system brightness keys.
	private var pendingStep: Float = 0
	private var flushTask: Task<Void, Never>?

	private init() { refresh() }

	var shouldShowOverlay: Bool { Date().timeIntervalSince(lastChangeAt) < visibleDuration }

	func refresh() {
		Task { @MainActor in
			if let current = await client.currentKeyboardBrightness() {
				publish(brightness: current, touchDate: false)
			}
		}
	}

	/// Moves the backlight by `delta`, where each call is one key press.
	@MainActor func setRelative(delta: Float) {
		pendingDelta += delta
		let step = abs(delta)
		if step > 0 { pendingStep = pendingStep > 0 ? min(pendingStep, step) : step }
		guard flushTask == nil else { return }
		flushTask = Task { @MainActor in
			defer { flushTask = nil }
			while pendingDelta != 0 {
				let delta = pendingDelta
				let step = pendingStep
				pendingDelta = 0
				pendingStep = 0
				// Include changes made outside the app in every adjustment.
				guard let current = await client.currentKeyboardBrightness() else {
					refresh()
					return
				}
				let target = BrightnessStepping.target(from: current, delta: delta, step: step)
				let ok = await client.setKeyboardBrightness(target)
				if ok {
					publish(brightness: target, touchDate: true)
				} else {
					refresh()
					return
				}
				NotchUIEventBus.events.send(.sneakPeek(type: .backlight, value: CGFloat(target)))
			}
		}
	}

	func setAbsolute(value: Float) {
		let clamped = max(0, min(1, value))
		Task { @MainActor in
			let ok = await client.setKeyboardBrightness(clamped)
			if ok {
				publish(brightness: clamped, touchDate: true)
			} else {
				refresh()
			}
		}
	}

	@MainActor private func publish(brightness: Float, touchDate: Bool) {
		if rawBrightness != brightness || touchDate {
			if touchDate { lastChangeAt = Date() }
			rawBrightness = brightness
		}
	}
}

// MARK: - Stepping

enum BrightnessStepping {
	/// Returns the level after moving `current` by `delta` in steps of `step`.
	///
	/// Like the system brightness keys, the result stays on the grid of `step`:
	/// a level that is off the grid (set by ambient light, a slider or another
	/// app) first moves to the nearest grid point in the direction of the key,
	/// so presses always land on values such as 50% instead of drifting to 51%.
	static func target(from current: Float, delta: Float, step: Float) -> Float {
		guard delta != 0, step > 0 else { return clamp(current + delta) }
		let steps = max(1, (abs(delta) / step).rounded())
		// Read-back values can be a hair off the grid (0.49999 for 0.5);
		// treat anything within 1% of a step as being on it.
		let tolerance: Float = 0.01
		let position = clamp(current) / step
		let grid = delta > 0
			? (position + tolerance).rounded(.down) + steps
			: (position - tolerance).rounded(.up) - steps
		return clamp(grid * step)
	}

	private static func clamp(_ value: Float) -> Float {
		max(0, min(1, value))
	}
}
