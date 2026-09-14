//
//  NetworkActivityState.swift
//  boringNotch
//

import Foundation

/// Cumulative byte counters for one interface.
struct InterfaceCounters: Equatable {
    var received: UInt64 = 0
    var sent: UInt64 = 0
}

/// Bytes per second in each direction.
struct NetworkThroughput: Equatable {
    var download: Double = 0
    var upload: Double = 0

    static let zero = NetworkThroughput()
}

/// The kind of link currently carrying traffic.
enum NetworkInterfaceKind: Equatable {
    case wifi
    case wired
    case cellular
    case other
    case none
}

/// Everything the Network section shows, as one value.
struct NetworkSnapshot: Equatable {
    var isConnected: Bool = false
    var kind: NetworkInterfaceKind = .none
    /// BSD name, e.g. `en0`.
    var interfaceName: String?
    var localIPv4: String?
    /// Only populated for Wi-Fi, and only when the user has opted into showing it.
    var ssid: String?
    var throughput: NetworkThroughput = .zero
    /// A metered link, such as a personal hotspot.
    var isExpensive: Bool = false
    /// Fetched only when explicitly enabled, because it takes an external request.
    var publicIPv4: String?
}

enum NetworkActivityState {
    /// Convert two counter readings into a rate.
    ///
    /// Counters only ever climb while an interface stays up, so a *decrease* means the
    /// interface was reset or replaced rather than that traffic went backwards. Reporting
    /// zero for that one sample is right: the alternative is a fabricated spike of however
    /// many gigabytes the old interface had accumulated.
    static func throughput(
        from previous: InterfaceCounters,
        to current: InterfaceCounters,
        over interval: TimeInterval
    ) -> NetworkThroughput {
        guard interval > 0 else { return .zero }
        let received = current.received >= previous.received
            ? Double(current.received - previous.received) : 0
        let sent = current.sent >= previous.sent
            ? Double(current.sent - previous.sent) : 0
        return NetworkThroughput(download: received / interval, upload: sent / interval)
    }

    /// "8.2 MB/s". Uses the same byte formatting as the rest of the app.
    static func formatRate(_ bytesPerSecond: Double, formatter: ByteCountFormatter) -> String {
        let clamped = bytesPerSecond.isFinite && bytesPerSecond > 0 ? bytesPerSecond : 0
        return formatter.string(fromByteCount: Int64(clamped)) + "/s"
    }
}
