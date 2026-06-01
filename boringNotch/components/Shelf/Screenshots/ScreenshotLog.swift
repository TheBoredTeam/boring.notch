//
//  ScreenshotLog.swift
//  boringNotch
//
//  Purpose: Thin os.Logger wrapper with per-subsystem categories for the
//           screenshot-capture subsystem. Ported from IslandNotch's Log.
//  Layer: Support
//

import Foundation
import os

/// Centralized loggers so call sites stay terse: `Log.capture.debug("...")`.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "theboringteam.boringnotch"

    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let store = Logger(subsystem: subsystem, category: "store")
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    static let permissions = Logger(subsystem: subsystem, category: "permissions")
}
