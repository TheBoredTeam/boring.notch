//  Log.swift
//  IslandNotch
//
//  Purpose: Thin os.Logger wrapper with per-subsystem categories.
//  Layer: Support

import Foundation
import os

/// Centralized loggers so call sites stay terse: `Log.capture.debug("...")`.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.constellagent.islandnotch"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let store = Logger(subsystem: subsystem, category: "store")
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    static let permissions = Logger(subsystem: subsystem, category: "permissions")
    static let notch = Logger(subsystem: subsystem, category: "notch")
}
