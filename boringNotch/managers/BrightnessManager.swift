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

	// MARK: - Smoothing

	/// Duration of each brightness ramp (seconds).
	private static let rampDuration: TimeInterval = 0.20
	/// Frame interval for the ramp (~60 fps).
	private static let rampInterval: TimeInterval = 1.0 / 60.0
	/// In-flight ramp task; cancelled whenever a new target arrives.
	private var rampTask: Task<Void, Never>?
	/// The brightness value most recently written to the display.
	private var currentDisplayBrightness: Float = 0

	private init() { refresh() }

	var shouldShowOverlay: Bool { Date().timeIntervalSince(lastChangeAt) < visibleDuration }

	func refresh() {
		Task { @MainActor in
			if let current = await client.currentScreenBrightness() {
				currentDisplayBrightness = current
				publish(brightness: current, touchDate: false)
			}
		}
	}

	@MainActor func setRelative(delta: Float) {
		Task { @MainActor in
			let starting: Float

			// When keys are pressed in quick succession use our last known
			// target so that deltas accumulate correctly and we avoid reading
			// a mid-ramp intermediate value from the system.
			if Date().timeIntervalSince(lastChangeAt) < 1.0 {
				starting = rawBrightness
			} else {
				let system = await client.currentScreenBrightness()
				if let system { currentDisplayBrightness = system }
				starting = system ?? rawBrightness
			}

			let target = max(0, min(1, starting + delta))
			let from = currentDisplayBrightness

			publish(brightness: target, touchDate: true)
			rampDisplayBrightness(from: from, to: target)

			BoringViewCoordinator.shared.toggleSneakPeek(
				status: true, type: .brightness, value: CGFloat(target)
			)
		}
	}

	func setAbsolute(value: Float) {
		let clamped = max(0, min(1, value))
		Task { @MainActor in
			// Cancel any in-progress ramp so the slider feels immediate.
			rampTask?.cancel()

			let ok = await client.setScreenBrightness(clamped)
			if ok {
				currentDisplayBrightness = clamped
				publish(brightness: clamped, touchDate: true)
			} else {
				refresh()
			}
		}
	}

	// MARK: - Smooth Ramp

	/// Smoothly ramps the physical display brightness from `start` to
	/// `target` over ``rampDuration`` using an ease-out quadratic curve.
	/// When a new key-press arrives mid-ramp the running task is cancelled
	/// and a fresh ramp begins from wherever the display currently sits,
	/// producing continuous fluid motion when keys are held down.
	private func rampDisplayBrightness(from start: Float, to target: Float) {
		rampTask?.cancel()

		let totalSteps = max(1, Int(Self.rampDuration / Self.rampInterval))
		let interval = Self.rampInterval

		rampTask = Task { [weak self] in
			guard let self else { return }

			for step in 1...totalSteps {
				if Task.isCancelled { return }

				let t = Float(step) / Float(totalSteps)
				// Ease-out quadratic: fast start, gentle settle.
				let eased = 1.0 - (1.0 - t) * (1.0 - t)
				let value = start + (target - start) * eased

				let ok = await self.client.setScreenBrightness(value)
				if ok {
					await MainActor.run { self.currentDisplayBrightness = value }
				}

				if step < totalSteps {
					try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
				}
			}

			// Ensure we land exactly on the target.
			if !Task.isCancelled {
				let ok = await self.client.setScreenBrightness(target)
				if ok {
					await MainActor.run { self.currentDisplayBrightness = target }
				}
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

	// MARK: - Smoothing

	private static let rampDuration: TimeInterval = 0.20
	private static let rampInterval: TimeInterval = 1.0 / 60.0
	private var rampTask: Task<Void, Never>?
	private var currentDisplayBrightness: Float = 0

	private init() { refresh() }

	var shouldShowOverlay: Bool { Date().timeIntervalSince(lastChangeAt) < visibleDuration }

	func refresh() {
		Task { @MainActor in
			if let current = await client.currentKeyboardBrightness() {
				currentDisplayBrightness = current
				publish(brightness: current, touchDate: false)
			}
		}
	}

	@MainActor func setRelative(delta: Float) {
		Task { @MainActor in
			let starting: Float
			if Date().timeIntervalSince(lastChangeAt) < 1.0 {
				starting = rawBrightness
			} else {
				let system = await client.currentKeyboardBrightness()
				if let system { currentDisplayBrightness = system }
				starting = system ?? rawBrightness
			}

			let target = max(0, min(1, starting + delta))
			let from = currentDisplayBrightness

			publish(brightness: target, touchDate: true)
			rampDisplayBrightness(from: from, to: target)

			BoringViewCoordinator.shared.toggleSneakPeek(
				status: true, type: .backlight, value: CGFloat(target)
			)
		}
	}

	func setAbsolute(value: Float) {
		let clamped = max(0, min(1, value))
		Task { @MainActor in
			rampTask?.cancel()

			let ok = await client.setKeyboardBrightness(clamped)
			if ok {
				currentDisplayBrightness = clamped
				publish(brightness: clamped, touchDate: true)
			} else {
				refresh()
			}
		}
	}

	// MARK: - Smooth Ramp

	private func rampDisplayBrightness(from start: Float, to target: Float) {
		rampTask?.cancel()

		let totalSteps = max(1, Int(Self.rampDuration / Self.rampInterval))
		let interval = Self.rampInterval

		rampTask = Task { [weak self] in
			guard let self else { return }

			for step in 1...totalSteps {
				if Task.isCancelled { return }

				let t = Float(step) / Float(totalSteps)
				let eased = 1.0 - (1.0 - t) * (1.0 - t)
				let value = start + (target - start) * eased

				let ok = await self.client.setKeyboardBrightness(value)
				if ok {
					await MainActor.run { self.currentDisplayBrightness = value }
				}

				if step < totalSteps {
					try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
				}
			}

			if !Task.isCancelled {
				let ok = await self.client.setKeyboardBrightness(target)
				if ok {
					await MainActor.run { self.currentDisplayBrightness = target }
				}
			}
		}
	}

	private func publish(brightness: Float, touchDate: Bool) {
		DispatchQueue.main.async {
			if self.rawBrightness != brightness || touchDate {
				if touchDate { self.lastChangeAt = Date() }
				self.rawBrightness = brightness
			}
		}
	}
}
