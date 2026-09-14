//  BrightnessManager.swift
//  boringNotch
//
//  Created by JeanLouis on 08/22/24.

import AppKit
import CoreGraphics
import Defaults

@MainActor
final class BrightnessManager: ObservableObject {
	static let shared = BrightnessManager()

	@Published private(set) var rawBrightness: Float = 0
	@Published private(set) var animatedBrightness: Float = 0
	@Published private(set) var lastChangeAt: Date = .distantPast
	@Published private(set) var canAdjustBrightness = false

	private let visibleDuration: TimeInterval = 1.2
	private let client: any BrightnessHardwareControlling
	private let displayUUID: (CGDirectDisplayID) -> String?
	private let controlEnabled: () -> Bool
	private let eventSink: (Float, String?) -> Void

	/// Key repeats arriving while an XPC call is in flight accumulate here so
	/// no press is lost — each press used to trigger its own 3-RPC sequence
	/// (adjust + read + display lookup), and they would queue behind each other.
	private var pendingDelta: Float = 0
	private var flushTask: Task<Void, Never>?
	private var flushTaskToken: UInt64?
	private var nextFlushTaskToken: UInt64 = 0
	private struct Target: Equatable {
		let generation: UInt64
		let displayID: CGDirectDisplayID
		let uuid: String?
	}
	private var target: Target?
	private var topologyGeneration: UInt64 = 0
	private var screenParametersObserver: (any NSObjectProtocol)?

	private convenience init() {
		self.init(
			client: XPCHelperClient.shared,
			displayUUID: { id in
				NSScreen.screens.first(where: { $0.cgDisplayID == id })?.displayUUID
			},
			eventSink: { value, uuid in
				NotchUIEventBus.events.send(
					.sneakPeek(
						type: .brightness, value: CGFloat(value),
						targetScreenUUID: uuid, provider: .builtin))
			},
			controlEnabled: {
				Defaults[.osdReplacement] && Defaults[.osdBrightnessSource] == .builtin
			})
	}

	init(
		client: any BrightnessHardwareControlling,
		displayUUID: @escaping (CGDirectDisplayID) -> String?,
		eventSink: @escaping (Float, String?) -> Void,
		observeTopology: Bool = true,
		controlEnabled: @escaping () -> Bool = { true }
	) {
		self.client = client
		self.displayUUID = displayUUID
		self.eventSink = eventSink
		self.controlEnabled = controlEnabled
		if observeTopology {
			screenParametersObserver = NotificationCenter.default.addObserver(
				forName: NSApplication.didChangeScreenParametersNotification,
				object: nil, queue: .main
			) { [weak self] _ in
				Task { @MainActor in self?.invalidateTopology() }
			}
		}
		refresh()
	}

	func brightnessTargetUUID() async -> String? {
		target?.uuid
	}

	var shouldShowOverlay: Bool { Date().timeIntervalSince(lastChangeAt) < visibleDuration }

	func refresh() {
		topologyGeneration &+= 1
		let generation = topologyGeneration
		target = nil
		canAdjustBrightness = false
		guard controlEnabled() else { return }
		Task { @MainActor [weak self] in
			guard let self, controlEnabled(), topologyGeneration == generation,
				  let displayID = await client.displayIDForBrightness(),
				  let result = await client.currentScreenBrightness(displayID: displayID),
				  result.displayID == displayID,
				  topologyGeneration == generation, controlEnabled()
			else { return }
			target = Target(
				generation: generation, displayID: displayID,
				uuid: displayUUID(displayID))
			canAdjustBrightness = true
			publish(brightness: result.brightness, touchDate: false)
		}
	}

	func invalidateTopology() {
		flushTask?.cancel()
		flushTask = nil
		flushTaskToken = nil
		pendingDelta = 0
		refresh()
	}

	@MainActor func setRelative(delta: Float) {
		guard controlEnabled(), let operationTarget = target else { return }
		pendingDelta += delta
		guard flushTask == nil else { return }
		nextFlushTaskToken &+= 1
		let taskToken = nextFlushTaskToken
		flushTaskToken = taskToken
		flushTask = Task { @MainActor in
			defer {
				if flushTaskToken == taskToken {
					pendingDelta = 0
					flushTask = nil
					flushTaskToken = nil
				}
			}
			while pendingDelta != 0 {
				guard !Task.isCancelled, controlEnabled(),
					  flushTaskToken == taskToken, target == operationTarget else { return }
				let delta = pendingDelta
				pendingDelta = 0
				guard let result = await client.adjustScreenBrightness(
					by: delta, displayID: operationTarget.displayID),
					  !Task.isCancelled, controlEnabled(),
					  flushTaskToken == taskToken, target == operationTarget,
					  result.displayID == operationTarget.displayID
				else {
					if !Task.isCancelled, flushTaskToken == taskToken { invalidateTopology() }
					return
				}
				publish(brightness: result.brightness, touchDate: true)
				eventSink(result.brightness, operationTarget.uuid)
			}
		}
	}

	func setAbsolute(value: Float) {
		let clamped = max(0, min(1, value))
		guard controlEnabled(), let operationTarget = target else { return }
		Task { @MainActor [weak self] in
			guard let self, !Task.isCancelled, controlEnabled(), target == operationTarget,
				  let result = await client.setScreenBrightness(
					clamped, displayID: operationTarget.displayID),
				  !Task.isCancelled, controlEnabled(), target == operationTarget,
				  result.displayID == operationTarget.displayID
			else { return }
			publish(brightness: result.brightness, touchDate: true)
			eventSink(result.brightness, operationTarget.uuid)
		}
	}

	private func publish(brightness: Float, touchDate: Bool) {
		if rawBrightness != brightness || touchDate {
			if touchDate { lastChangeAt = Date() }
			rawBrightness = brightness
			animatedBrightness = brightness
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

	/// Deltas accumulate while a set call is in flight so key repeats are
	/// never lost; each flush costs exactly one XPC call.
	private var pendingDelta: Float = 0
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

	@MainActor func setRelative(delta: Float) {
		pendingDelta += delta
		guard flushTask == nil else { return }
		flushTask = Task { @MainActor in
			defer { flushTask = nil }
			while pendingDelta != 0 {
				let delta = pendingDelta
				pendingDelta = 0
				// Compute from the cached value — the read-back RPC the old
				// code did before every set doubles the cost per key press.
				let target = max(0, min(1, rawBrightness + delta))
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

	private func publish(brightness: Float, touchDate: Bool) {
		DispatchQueue.main.async {
			if self.rawBrightness != brightness || touchDate {
				if touchDate { self.lastChangeAt = Date() }
				self.rawBrightness = brightness
			}
		}
	}
}
