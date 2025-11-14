//  BrightnessManager.swift
//  boringNotch
//
//  Created by JeanLouis on 08/22/24.

import AppKit
import IOKit
import ObjectiveC

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

    @MainActor func setRelative(delta: Float) {
		let target = max(0, min(1, rawBrightness + delta))
		setAbsolute(value: target)
		BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .brightness, value: CGFloat(target))
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

// MARK: - Keyboard Backlight Controller
final class KeyboardBacklightManager: ObservableObject {
	static let shared = KeyboardBacklightManager()

	@Published private(set) var rawBrightness: Float = 0
	@Published private(set) var lastChangeAt: Date = .distantPast

	private let visibleDuration: TimeInterval = 1.2
	private let client = KeyboardBrightnessClientWrapper()

	private init() { refresh() }

	var shouldShowOverlay: Bool { Date().timeIntervalSince(lastChangeAt) < visibleDuration }
	var isAvailable: Bool { client.isAvailable }

	func refresh() {
		guard let current = client.currentBrightness() else { return }
		publish(brightness: current, touchDate: false)
	}

	@MainActor func setRelative(delta: Float) {
		guard client.isAvailable else { return }
		let starting = client.currentBrightness() ?? rawBrightness
		let target = max(0, min(1, starting + delta))
		setAbsolute(value: target)
		BoringViewCoordinator.shared.toggleSneakPeek(
			status: true,
			type: .backlight,
			value: CGFloat(target)
		)
	}

	func setAbsolute(value: Float) {
		guard client.isAvailable else { return }
		let clamped = max(0, min(1, value))
		if client.setBrightness(clamped) {
			publish(brightness: clamped, touchDate: true)
		} else {
			refresh()
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

private final class KeyboardBrightnessClientWrapper {
	private static let keyboardID: UInt64 = 1
	private let clientInstance: NSObject?

	private let getSelector = NSSelectorFromString("brightnessForKeyboard:")
	private let setSelector = NSSelectorFromString("setBrightness:forKeyboard:")

	init() {
		var loaded = false
		let bundlePaths = [
			"/System/Library/PrivateFrameworks/CoreBrightness.framework",
			"/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
		]
		for path in bundlePaths where !loaded {
			if let bundle = Bundle(path: path) {
				loaded = bundle.load()
			}
		}
		if loaded, let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type {
			clientInstance = cls.init()
		} else {
			clientInstance = nil
		}
	}

	var isAvailable: Bool { clientInstance != nil }

	func currentBrightness() -> Float? {
		guard let clientInstance,
			let fn: BrightnessGetter = methodIMP(on: clientInstance, selector: getSelector, as: BrightnessGetter.self)
		else { return nil }
		return fn(clientInstance, getSelector, Self.keyboardID)
	}

	func setBrightness(_ value: Float) -> Bool {
		guard let clientInstance,
			let fn: BrightnessSetter = methodIMP(on: clientInstance, selector: setSelector, as: BrightnessSetter.self)
		else { return false }
		return fn(clientInstance, setSelector, value, Self.keyboardID).boolValue
	}

	private typealias BrightnessGetter = @convention(c) (NSObject, Selector, UInt64) -> Float
	private typealias BrightnessSetter = @convention(c) (NSObject, Selector, Float, UInt64) -> ObjCBool

	private func methodIMP<T>(on object: NSObject, selector: Selector, as type: T.Type) -> T? {
		guard let cls = object_getClass(object),
			let method = class_getInstanceMethod(cls, selector)
		else { return nil }
		let imp = method_getImplementation(method)
		return unsafeBitCast(imp, to: type)
	}
}

