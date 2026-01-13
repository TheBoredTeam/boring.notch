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
	private let stepSize: Float = 0.001
	private let singlePressDurationNs: UInt64 = 500_000_000
	private let continuousRatePerSecond: Float = 0.50
	private let holdDelayNs: UInt64 = 250_000_000
	private let continuousStepSize: Float = 0.002
	private let client = XPCHelperClient.shared
	private var steppingTask: Task<Void, Never>?
	private var holdTask: Task<Void, Never>?
	private var continuousTask: Task<Void, Never>?

	private init() { refresh() }

	var shouldShowOverlay: Bool { Date().timeIntervalSince(lastChangeAt) < visibleDuration }

	func refresh() {
		Task { @MainActor in
			if let current = await client.currentScreenBrightness() {
				publish(brightness: current, touchDate: false)
			}
		}
	}

	@MainActor func handleKeyDown(delta: Float) {
		steppingTask?.cancel()
		holdTask?.cancel()
		continuousTask?.cancel()

		let direction: Float = delta >= 0 ? 1 : -1
		steppingTask = Task { @MainActor in
			let starting = await client.currentScreenBrightness() ?? rawBrightness
			let target = max(0, min(1, starting + delta))
			await applySteppedBrightness(
				from: starting,
				to: target,
				durationNs: singlePressDurationNs
			)
		}

		holdTask = Task { @MainActor in
			try? await Task.sleep(nanoseconds: holdDelayNs)
			if Task.isCancelled { return }
			startContinuousAdjustment(direction: direction)
		}
	}

	@MainActor func handleKeyUp() {
		holdTask?.cancel()
		continuousTask?.cancel()
	}

	func setAbsolute(value: Float) {
		let clamped = max(0, min(1, value))
		Task { @MainActor in
			let ok = await client.adjustScreenBrightness(by: clamped)
			if ok {
				publish(brightness: clamped, touchDate: true)
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

	@MainActor private func applySteppedBrightness(
		from starting: Float,
		to target: Float,
		durationNs: UInt64
	) async {
		let delta = target - starting
		guard delta != 0 else { return }
		if abs(delta) <= stepSize {
			await setAndPublishBrightness(target)
			return
		}

		let direction: Float = delta > 0 ? 1 : -1
		let steps = Int(abs(delta) / stepSize)
		let intervalNs = max(durationNs / UInt64(max(steps, 1)), 1)
		var current = starting

		for _ in 0..<steps {
			if Task.isCancelled { return }
			current = max(0, min(1, current + direction * stepSize))
			let ok = await client.adjustScreenBrightness(by: current)
			if ok {
				publish(brightness: current, touchDate: true)
				BoringViewCoordinator.shared.toggleSneakPeek(
					status: true,
					type: .brightness,
					value: CGFloat(current)
				)
			} else {
				refresh()
				return
			}
			try? await Task.sleep(nanoseconds: intervalNs)
		}

		if Task.isCancelled { return }
		if current != target {
			await setAndPublishBrightness(target)
		}
	}

	@MainActor private func setAndPublishBrightness(_ value: Float) async {
		let ok = await client.adjustScreenBrightness(by: value)
		if ok {
			publish(brightness: value, touchDate: true)
			BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .brightness, value: CGFloat(value))
		} else {
			refresh()
		}
	}

	@MainActor private func startContinuousAdjustment(direction: Float) {
		steppingTask?.cancel()
		continuousTask?.cancel()

		continuousTask = Task { @MainActor in
			let step = max(continuousStepSize, stepSize)
			let intervalNs = max(
				UInt64(Double(step) / Double(continuousRatePerSecond) * 1_000_000_000),
				1
			)
			var current = rawBrightness

			while !Task.isCancelled {
				let next = max(0, min(1, current + direction * step))
				if next == current { return }
				let ok = await client.setScreenBrightness(next)
				if ok {
					publish(brightness: next, touchDate: true)
					BoringViewCoordinator.shared.toggleSneakPeek(
						status: true,
						type: .brightness,
						value: CGFloat(next)
					)
					current = next
				} else {
					refresh()
					return
				}
				try? await Task.sleep(nanoseconds: intervalNs)
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

	private init() { refresh() }

	var shouldShowOverlay: Bool { Date().timeIntervalSince(lastChangeAt) < visibleDuration }

	func refresh() {
		Task { @MainActor in
			if let current = await client.currentKeyboardBrightness() {
				publish(brightness: current, touchDate: false)
			}
		}
	}

	@MainActor func setRelative(delta: Float) {
		Task { @MainActor in
			let starting = await client.currentKeyboardBrightness() ?? rawBrightness
			let target = max(0, min(1, starting + delta))
			let ok = await client.setKeyboardBrightness(target)
			if ok {
				publish(brightness: target, touchDate: true)
			} else {
				refresh()
			}
			BoringViewCoordinator.shared.toggleSneakPeek(
				status: true,
				type: .backlight,
				value: CGFloat(target)
			)
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

	private func publish(brightness: Float, touchDate: Bool) {
		DispatchQueue.main.async {
			if self.rawBrightness != brightness || touchDate {
				if touchDate { self.lastChangeAt = Date() }
				self.rawBrightness = brightness
			}
		}
	}
}
