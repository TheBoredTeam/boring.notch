//  BrightnessManager.swift
//  boringNotch
//
//  Created by JeanLouis on 08/22/24.

import AppKit
import Defaults

final class BrightnessManager: ObservableObject {
	static let shared = BrightnessManager()

	@Published private(set) var rawBrightness: Float = 0
	@Published private(set) var animatedBrightness: Float = 0
	@Published private(set) var lastChangeAt: Date = .distantPast

	private let visibleDuration: TimeInterval = 1.2
	private let client = XPCHelperClient.shared

	private var externalChangeTask: Task<Void, Never>?

	private init() {
		refresh()
		observeExternalChangesIfEnabled()
	}

	/// macOS publishes no notification when display brightness changes, so an OSD can
	/// only appear for changes we make ourselves via the media keys. Catching changes
	/// made from Control Centre, System Settings or auto-brightness means polling, which
	/// is why this is opt-in and off by default. Users of BetterDisplay or Lunar should
	/// pick those sources instead — they are genuinely event driven.
	func observeExternalChangesIfEnabled() {
		externalChangeTask?.cancel()
		externalChangeTask = nil

		guard Defaults[.osdObserveExternalBrightness] else { return }

		externalChangeTask = Task { @MainActor [weak self] in
			while !Task.isCancelled {
				try? await Task.sleep(for: .seconds(1))
				guard let self, !Task.isCancelled else { return }

				// Nothing to show while the screen is locked or the OSD is switched off.
				guard Defaults[.osdReplacement], Defaults[.osdBrightnessEnabled],
				      Defaults[.osdBrightnessSource] == .builtin,
				      !LockScreenManager.shared.isLocked
				else { continue }

				guard let current = await self.client.currentScreenBrightness() else { continue }

				// Ignore changes we just made ourselves; those already showed an OSD.
				guard Date().timeIntervalSince(self.lastChangeAt) > 1.5 else { continue }
				guard abs(current - self.rawBrightness) > 0.005 else { continue }

				self.publish(brightness: current, touchDate: true)
				let targetUUID = await self.brightnessTargetUUID()
				BoringViewCoordinator.shared.toggleSneakPeek(
					status: true, type: .brightness,
					value: CGFloat(current), targetScreenUUID: targetUUID
				)
			}
		}
	}

	/// Determine which screen UUID should be used for brightness OSDs
	/// when the built‑in source is selected.  This mirrors the logic in the
	/// XPC helper, which chooses the menu-bar display if it supports brightness and
	/// otherwise falls back to an internal panel.
	func brightnessTargetUUID() async -> String? {
		if let displayID = await client.displayIDForBrightness() {
			if let screen = NSScreen.screens.first(where: { $0.cgDisplayID == displayID }) {
				return screen.displayUUID
			}
		}
		return NSScreen.main?.displayUUID
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
		Task { @MainActor in
            let ok = await client.adjustScreenBrightness(by: delta)
			if ok {
                let current = await client.currentScreenBrightness() ?? rawBrightness
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
			let ok = await client.setScreenBrightness(clamped)
			if ok {
				publish(brightness: clamped, touchDate: true)
                // optionally show peek when user uses slider/controls
                let targetUUID = await brightnessTargetUUID()
                BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .brightness, value: CGFloat(clamped), targetScreenUUID: targetUUID)
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
