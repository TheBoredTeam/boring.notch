//
//  SystemMetricKind.swift
//  boringNotch
//
//  The set of metrics the system monitor can show, and the presentation
//  metadata that goes with each one.
//
//  Kept apart from `SystemMetrics.swift` so that file stays free of any
//  dependency on Defaults — the arithmetic there is the part worth testing in
//  isolation.
//

import Defaults
import SwiftUI

enum SystemMetricKind: String, CaseIterable, Identifiable, Defaults.Serializable {
    case cpu
    case memory
    case battery
    case disk
    case network
    case wifi

    var id: String { rawValue }

    /// Order the cards appear in the grid. Explicit rather than relying on
    /// `allCases`, so reordering the declaration can't silently reshuffle the
    /// user's notch.
    static let displayOrder: [SystemMetricKind] = [.cpu, .memory, .battery, .disk, .network, .wifi]

    var localizedTitle: String {
        switch self {
        case .cpu: return NSLocalizedString("system_metric_cpu", comment: "System monitor card title: CPU")
        case .memory: return NSLocalizedString("system_metric_memory", comment: "System monitor card title: memory")
        case .battery: return NSLocalizedString("system_metric_battery", comment: "System monitor card title: battery")
        case .disk: return NSLocalizedString("system_metric_disk", comment: "System monitor card title: disk")
        case .network: return NSLocalizedString("system_metric_network", comment: "System monitor card title: network")
        case .wifi: return NSLocalizedString("system_metric_wifi", comment: "System monitor card title: Wi-Fi")
        }
    }

    var systemImage: String {
        switch self {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .battery: return "battery.100"
        case .disk: return "internaldrive"
        case .network: return "network"
        case .wifi: return "wifi"
        }
    }

    /// Ring colour. Network and Wi-Fi are "connectivity" and read green when
    /// healthy; the capacity metrics use the warm ring so a filling gauge is
    /// visually the same language across CPU, memory, battery and disk.
    var tint: Color {
        switch self {
        case .cpu, .memory, .battery, .disk: return SystemMonitorPalette.ring
        case .network, .wifi: return SystemMonitorPalette.positive
        }
    }

    /// Metrics that need two samples before they can report a rate, and so
    /// must render a placeholder on the first tick instead of a zero.
    var requiresTwoSamples: Bool {
        switch self {
        case .cpu, .network: return true
        case .memory, .battery, .disk, .wifi: return false
        }
    }

    static let defaultSelection: Set<SystemMetricKind> = Set(SystemMetricKind.allCases)
}

/// Colours for the monitor surface. Defined once so the cards, gauges and
/// closed-notch pill can't drift apart.
enum SystemMonitorPalette {
    /// Card fill — a touch lighter than the notch's pure black so the grid
    /// reads as cards rather than as floating text.
    static let cardBackground = Color(red: 0.086, green: 0.098, blue: 0.125)
    static let cardBorder = Color.white.opacity(0.07)
    /// The recessed action button at the foot of each card.
    static let actionBackground = Color.white.opacity(0.06)
    static let track = Color.white.opacity(0.12)
    static let ring = Color(red: 0.933, green: 0.549, blue: 0.227)
    static let positive = Color(red: 0.204, green: 0.780, blue: 0.349)
    static let warning = Color(red: 0.984, green: 0.737, blue: 0.180)
    static let critical = Color(red: 0.922, green: 0.290, blue: 0.259)
    static let label = Color.white.opacity(0.45)
    static let secondary = Color.white.opacity(0.55)
}
