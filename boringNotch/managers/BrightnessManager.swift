//  BrightnessManager.swift
//  boringNotch
//
//  Created by JeanLouis on 08/22/24.

import AppKit
import IOKit

final class BrightnessManager: ObservableObject {
	static let shared = BrightnessManager()

	@Published private(set) var rawBrightness: Float = 0
	@Published private(set) var animatedBrightness: Float = 0
	@Published private(set) var lastChangeAt: Date = .distantPast

	private let visibleDuration: TimeInterval = 1.2

	private var displayID: CGDirectDisplayID { CGMainDisplayID() }

	private init() { refresh() }

	var shouldShowOverlay: Bool { Date().timeIntervalSince(lastChangeAt) < visibleDuration }

	func refresh() { if let current = readSystemBrightness() { publish(brightness: current, touchDate: false) } }

    func setRelative(delta: Float) {
        setAbsolute(value: rawBrightness + delta)
        BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .brightness, value: CGFloat(BrightnessManager.shared.rawBrightness))
    }

	func setAbsolute(value: Float) {
		let clamped = max(0, min(1, value))
		let applied = setSystemBrightness(clamped)
		if applied {
			publish(brightness: clamped, touchDate: true)
		} else {
			publish(brightness: rawBrightness, touchDate: true)
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

	private func readSystemBrightness() -> Float? {
		var b: Float = 0
		if displayServicesGetBrightness(displayID: displayID, out: &b) { return b }
		if let io = ioServiceFor(displayID: displayID) {
			var level: Float = 0
			if IODisplayGetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, &level) == kIOReturnSuccess {
				IOObjectRelease(io)
				return level
			}
			IOObjectRelease(io)
		}
		return nil
	}

	private func setSystemBrightness(_ value: Float) -> Bool {
		if displayServicesSetBrightness(displayID: displayID, value: value) { return true }
		if let io = ioServiceFor(displayID: displayID) {
			let ok = IODisplaySetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, value) == kIOReturnSuccess
			IOObjectRelease(io)
			return ok
		}
		return false
	}

	private func displayServicesGetBrightness(displayID: CGDirectDisplayID, out: inout Float) -> Bool {
		guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesGetBrightness") else { return false }
		typealias Fn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
		let fn = unsafeBitCast(sym, to: Fn.self)
		var tmp: Float = 0
		let r = fn(displayID, &tmp)
		if r == 0 { out = tmp; return true }
		return false
	}

	private func displayServicesSetBrightness(displayID: CGDirectDisplayID, value: Float) -> Bool {
		guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesSetBrightness") else { return false }
		typealias Fn = @convention(c) (CGDirectDisplayID, Float) -> Int32
		let fn = unsafeBitCast(sym, to: Fn.self)
		return fn(displayID, value) == 0
	}

	private func ioServiceFor(displayID: CGDirectDisplayID) -> io_service_t? {
		var iterator: io_iterator_t = 0
		let matching = IOServiceMatching("IODisplayConnect")
		let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
		if result != kIOReturnSuccess { return nil }
		var service: io_service_t? = nil
		while case let s = IOIteratorNext(iterator), s != 0 {
			let info = IODisplayCreateInfoDictionary(s, 0).takeRetainedValue() as NSDictionary
			if let vendorID = info[kDisplayVendorID] as? UInt32,
			   let productID = info[kDisplayProductID] as? UInt32 {
				let vid = CGDisplayVendorNumber(displayID)
				let pid = CGDisplayModelNumber(displayID)
				if vendorID == vid && productID == pid {
					service = s
					break
				}
			}
			IOObjectRelease(s)
		}
		IOObjectRelease(iterator)
		return service
	}
}

// MARK: - Helper handle for private framework
private enum DisplayServicesHandle {
	static let handle: UnsafeMutableRawPointer? = {
		let paths = [
			"/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
			"/System/Library/PrivateFrameworks/DisplayServices.framework/Versions/Current/DisplayServices"
		]
		for p in paths {
			if let h = dlopen(p, RTLD_LAZY) { return h }
		}
		return nil
	}()
}

