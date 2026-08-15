//
//  Log.swift
//  boringNotch
//
//  os.Logger backbone. One subsystem, per-feature categories — filterable
//  in Console.app and persisted appropriately by level (debug is
//  memory-only; notice+ hits the log store).
//

import OSLog

enum Log {
    private static let subsystem = "theboringteam.boringnotch"

    static let general = Logger(subsystem: subsystem, category: "general")
    static let app = Logger(subsystem: subsystem, category: "app")
    static let music = Logger(subsystem: subsystem, category: "music")
    static let osd = Logger(subsystem: subsystem, category: "osd")
    static let xpc = Logger(subsystem: subsystem, category: "xpc")
    static let shelf = Logger(subsystem: subsystem, category: "shelf")
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
    static let battery = Logger(subsystem: subsystem, category: "battery")
    static let webcam = Logger(subsystem: subsystem, category: "webcam")
    static let calendar = Logger(subsystem: subsystem, category: "calendar")
    static let window = Logger(subsystem: subsystem, category: "window")
}
