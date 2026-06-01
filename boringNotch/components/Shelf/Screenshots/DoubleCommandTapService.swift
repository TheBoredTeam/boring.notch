//
//  DoubleCommandTapService.swift
//  boringNotch
//
//  Purpose: Detects ⌘ gestures via a global CGEventTap and fires a
//           `.doubleCommand`-sourced capture. Supports:
//             • double-tap of either left or right ⌘
//             • pressing left ⌘ and right ⌘ together
//           Requires Accessibility.
//  Layer: Service
//

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Listens (read-only) to `.flagsChanged` events for the physical ⌘ keys.
final class DoubleCommandTapService {
    /// Invoked on the main actor when a ⌘ gesture is recognized.
    var onCapture: ((CaptureSource) -> Void)?

    /// Max seconds allowed between two ⌘ tap releases.
    private let doubleTapWindow: TimeInterval = 0.30
    /// Ignore repeat fires while both ⌘ keys stay held.
    private let bothCommandCooldown: TimeInterval = 0.75

    private static let leftCommandKeyCode: Int64 = 0x37
    private static let rightCommandKeyCode: Int64 = 0x36

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var leftCommandDown = false
    private var rightCommandDown = false
    private var lastCommandUpTime: TimeInterval = 0
    private var lastBothCommandFireTime: TimeInterval = 0
    private var sawForeignModifierThisCycle = false

    private(set) var isRunning = false

    // MARK: Lifecycle

    /// Installs the tap. No-op (returns false) if Accessibility isn't granted or
    /// the tap can't be created. Safe to call repeatedly.
    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }
        guard AXIsProcessTrusted() else {
            Log.hotkey.notice("double-⌘ not started: Accessibility not granted")
            return false
        }

        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: Self.callback,
            userInfo: userInfo
        ) else {
            Log.hotkey.error("CGEvent.tapCreate returned nil")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        isRunning = true
        resetCycle()
        Log.hotkey.debug("double-⌘ tap installed")
        return true
    }

    func stop() {
        guard isRunning else { return }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil
        isRunning = false
        resetCycle()
    }

    // MARK: Recognition

    private func resetCycle() {
        leftCommandDown = false
        rightCommandDown = false
        lastCommandUpTime = 0
        lastBothCommandFireTime = 0
        sawForeignModifierThisCycle = false
    }

    /// Handles one flagsChanged event for a physical ⌘ key transition.
    fileprivate func handleFlagsChanged(_ event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == Self.leftCommandKeyCode || keyCode == Self.rightCommandKeyCode else {
            return
        }

        let flags = event.flags
        let foreign: CGEventFlags = [.maskShift, .maskAlternate, .maskControl, .maskSecondaryFn]
        if !flags.intersection(foreign).isEmpty {
            sawForeignModifierThisCycle = true
        }

        let isLeft = keyCode == Self.leftCommandKeyCode
        let wasDown = isLeft ? leftCommandDown : rightCommandDown

        if wasDown {
            if isLeft { leftCommandDown = false } else { rightCommandDown = false }

            let now = ProcessInfo.processInfo.systemUptime
            defer { sawForeignModifierThisCycle = false }

            guard !sawForeignModifierThisCycle else {
                lastCommandUpTime = 0
                return
            }

            if now - lastCommandUpTime <= doubleTapWindow {
                lastCommandUpTime = 0
                fireCapture()
            } else {
                lastCommandUpTime = now
            }
        } else {
            if isLeft { leftCommandDown = true } else { rightCommandDown = true }
            checkBothCommandsPressed()
        }
    }

    private func checkBothCommandsPressed() {
        guard leftCommandDown, rightCommandDown, !sawForeignModifierThisCycle else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastBothCommandFireTime >= bothCommandCooldown else { return }
        lastBothCommandFireTime = now
        lastCommandUpTime = 0
        fireCapture()
    }

    private func fireCapture() {
        Log.hotkey.debug("double-⌘ fireCapture")
        let handler = onCapture
        DispatchQueue.main.async { handler?(.doubleCommand) }
    }

    private func reEnableIfNeeded() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    // MARK: C callback

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let service = Unmanaged<DoubleCommandTapService>.fromOpaque(userInfo).takeUnretainedValue()

        switch type {
        case .flagsChanged:
            service.handleFlagsChanged(event)
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            service.reEnableIfNeeded()
        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }
}
