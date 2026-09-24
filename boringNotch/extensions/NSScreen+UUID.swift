//
//  NSScreen+UUID.swift
//  boringNotch
//
//  Created by Alexander on 2025-11-21.
//

import AppKit
import CoreGraphics
import os

extension NSScreen {
    /// Returns a persistent UUID for this display
    var displayUUID: String? {
        guard let displayID = cgDisplayID else { return nil }
        if let cached = NSScreenUUIDCache.uuidsByDisplayID.withLock({ $0[displayID] }) {
            return cached
        }
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID) else {
            return nil
        }
        let uuidString = CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String
        NSScreenUUIDCache.uuidsByDisplayID.withLock { $0[displayID] = uuidString }
        return uuidString
    }

    var cgDisplayID: CGDirectDisplayID? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }

    /// Find a screen by its UUID
    @MainActor static func screen(withUUID uuid: String) -> NSScreen? {
        return NSScreenUUIDCache.shared.screen(forUUID: uuid)
    }

    /// Get UUID to NSScreen mapping for all screens
    @MainActor static var screensByUUID: [String: NSScreen] {
        return NSScreenUUIDCache.shared.allScreens
    }
}

/// Cache for UUID to NSScreen mappings to avoid repeated lookups
@MainActor
final class NSScreenUUIDCache {
    static let shared = NSScreenUUIDCache()

    private var cache: [String: NSScreen] = [:]
    /// Reverse mapping used by `displayUUID`; nonisolated because that property is,
    /// and cleared here whenever screen parameters change.
    nonisolated static let uuidsByDisplayID = OSAllocatedUnfairLock(initialState: [CGDirectDisplayID: String]())
    private var observer: Any?

    private init() {
        rebuildCache()
        setupObserver()
    }

    deinit {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupObserver() {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.rebuildCache()
        }
    }

    private func rebuildCache() {
        Self.uuidsByDisplayID.withLock { $0.removeAll(keepingCapacity: true) }
        var newCache: [String: NSScreen] = [:]

        for screen in NSScreen.screens {
            if let uuid = screen.displayUUID {
                newCache[uuid] = screen
            }
        }

        cache = newCache
    }

    func screen(forUUID uuid: String) -> NSScreen? {
        return cache[uuid]
    }

    var allScreens: [String: NSScreen] {
        return cache
    }
}
