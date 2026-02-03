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
	private let animationDuration: TimeInterval = 0.25
	private let client = XPCHelperClient.shared

	private var brightnessAnimationTask: Task<Void, Never>?

	private init() { refresh() }

	var shouldShowOverlay: Bool { Date().timeIntervalSince(lastChangeAt) < visibleDuration }

	func refresh() {
		Task { @MainActor in
			if let current = await client.currentScreenBrightness() {
				publish(brightness: current, touchDate: false)
			}
		}
	}

	@MainActor func setRelative(delta: Float) {
		brightnessAnimationTask?.cancel()
		Task { @MainActor in
			let starting = await client.currentScreenBrightness() ?? rawBrightness
			let target = max(0, min(1, starting + delta))
			startSmoothAnimation(from: starting, to: target)
			lastChangeAt = Date()
			BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .brightness, value: CGFloat(target))
		}
	}

	func setAbsolute(value: Float) {
		let clamped = max(0, min(1, value))
		Task { @MainActor in
			brightnessAnimationTask?.cancel()
			startSmoothAnimation(from: animatedBrightness, to: clamped)
			lastChangeAt = Date()
		}
	}

	@MainActor private func startSmoothAnimation(from start: Float, to target: Float) {
		brightnessAnimationTask?.cancel()
		let startValue = start
		let targetValue = target
		brightnessAnimationTask = Task { @MainActor in
			let startTime = CACurrentMediaTime()
			let frameInterval: UInt64 = 16_000_000 // ~60 fps
			while !Task.isCancelled {
				let elapsed = CACurrentMediaTime() - startTime
				let t = min(1.0, elapsed / animationDuration)
				let eased = easeInOutCubic(t)
				let value = startValue + (targetValue - startValue) * Float(eased)
				_ = await client.setScreenBrightness(value)
				await MainActor.run {
					self.animatedBrightness = value
					if t >= 1.0 {
						self.rawBrightness = targetValue
						self.animatedBrightness = targetValue
					}
				}
				if t >= 1.0 { return }
				try? await Task.sleep(nanoseconds: frameInterval)
			}
			// Cancelled: leave rawBrightness as-is; next animation will start from animatedBrightness
		}
	}

	private func easeInOutCubic(_ t: Double) -> Double {
		if t <= 0 { return 0 }
		if t >= 1 { return 1 }
		return t * t * (3 - 2 * t)
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

