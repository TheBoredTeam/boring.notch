//  BrightnessManager.swift
//  boringNotch
//
//  Created by JeanLouis on 08/22/24.

import AppKit
import CoreGraphics

final class BrightnessManager: ObservableObject {
	static let shared = BrightnessManager()

	@Published private(set) var rawBrightness: Float = 0
	@Published private(set) var animatedBrightness: Float = 0
	@Published private(set) var lastChangeAt: Date = .distantPast

	private let visibleDuration: TimeInterval = 1.2
	private let client = XPCHelperClient.shared

	private init() { refresh() }

	/// Determine which screen UUID should be used for brightness OSDs
	/// when the built-in source is selected.
	/// Prefer the display being acted on, and only fall back to the helper's
	/// built-in brightness display resolution if needed.
	func brightnessTargetUUID() async -> String? {
		if let displayID = await MainActor.run(body: { targetDisplayID() }),
		   let screen = NSScreen.screens.first(where: { $0.cgDisplayID == displayID })
		{
			return screen.displayUUID
		}

		if let displayID = await client.displayIDForBrightness() {
			if let screen = NSScreen.screens.first(where: { $0.cgDisplayID == displayID }) {
				return screen.displayUUID
			}
		}
		return NSScreen.main?.displayUUID
	}

	var shouldShowOverlay: Bool { Date().timeIntervalSince(lastChangeAt) < visibleDuration }

	@MainActor
	private func targetDisplayID() -> CGDirectDisplayID? {
		if let mouseDisplayID = NSScreen.screenWithMouse?.displayID {
			return mouseDisplayID
		}

		if let selectedScreen = NSScreen.screen(withUUID: BoringViewCoordinator.shared.selectedScreenUUID),
		   let selectedDisplayID = selectedScreen.displayID
		{
			return selectedDisplayID
		}

		if let preferredUUID = BoringViewCoordinator.shared.preferredScreenUUID,
		   let preferredScreen = NSScreen.screen(withUUID: preferredUUID),
		   let preferredDisplayID = preferredScreen.displayID
		{
			return preferredDisplayID
		}

		return NSScreen.main?.displayID ?? NSScreen.screens.first?.displayID
	}

	func refresh() {
		Task { @MainActor in
			if let current = await client.currentScreenBrightness(displayID: targetDisplayID()) {
				publish(brightness: current, touchDate: false)
			}
		}
	}

	@MainActor func setRelative(delta: Float) {
		Task { @MainActor in
			let displayID = targetDisplayID()
			let starting = await client.currentScreenBrightness(displayID: displayID) ?? rawBrightness
			let target = max(0, min(1, starting + delta))
			let ok = await client.setScreenBrightness(target, displayID: displayID)
			if ok {
                let current = await client.currentScreenBrightness(displayID: displayID) ?? target
				publish(brightness: current, touchDate: true)

                let targetUUID = await brightnessTargetUUID()
                BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .brightness, value: CGFloat(current), targetScreenUUID: targetUUID)
			} else {
				refresh()
			}
		}
	}

	func setAbsolute(value: Float) {
		let clamped = max(0, min(1, value))
		Task { @MainActor in
			let displayID = targetDisplayID()
			let ok = await client.setScreenBrightness(clamped, displayID: displayID)
			if ok {
				let current = await client.currentScreenBrightness(displayID: displayID) ?? clamped
				publish(brightness: current, touchDate: true)
                // optionally show peek when user uses slider/controls
                let targetUUID = await brightnessTargetUUID()
                BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .brightness, value: CGFloat(current), targetScreenUUID: targetUUID)
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
