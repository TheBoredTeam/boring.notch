//
//  WiFiActivityState.swift
//  boringNotch
//

import Foundation

/// How strong the Wi-Fi signal is, bucketed for display.
///
/// RSSI is a logarithmic quantity, so it is bucketed rather than converted to a percentage:
/// every vendor invents a different dBm-to-percent curve and none of them mean anything.
enum WiFiSignalStrength: Equatable, Sendable, CaseIterable {
    case weak
    case fair
    case good
    case excellent

    /// Readings outside this are either CoreWLAN's "not associated" sentinel of 0 or
    /// nonsense, and in both cases we would rather show nothing than a wrong bar count.
    static let plausibleRSSI: ClosedRange<Int> = -100...(-10)

    init?(rssi: Int) {
        guard Self.plausibleRSSI.contains(rssi) else { return nil }
        switch rssi {
        case (-55)...: self = .excellent
        case (-67)...: self = .good
        case (-75)...: self = .fair
        default: self = .weak
        }
    }

    /// Fill fraction for `Image(systemName:variableValue:)`.
    ///
    /// Never 0 — a fully dim glyph reads as "no signal", which contradicts an activity that
    /// has just announced the network as connected.
    var variableValue: Double {
        switch self {
        case .weak: return 0.25
        case .fair: return 0.5
        case .good: return 0.75
        case .excellent: return 1
        }
    }

    /// Localization key for the word shown beside the glyph.
    var labelKey: String {
        switch self {
        case .weak: return "Weak"
        case .fair: return "Fair"
        case .good: return "Good"
        case .excellent: return "Excellent"
        }
    }
}

/// The Wi-Fi network as far as the notch is concerned.
///
/// Both details are optional because both are permission-gated to some degree: `ssid` needs
/// Location authorization, and `strength` may come back as CoreWLAN's zero sentinel. Absence
/// is a normal state to render, not an error.
struct WiFiNetworkInfo: Equatable, Sendable {
    var ssid: String?
    var strength: WiFiSignalStrength?
    var isPoweredOn: Bool = true
}

/// Decides *whether* a Wi-Fi change is worth announcing.
///
/// Kept free of Network.framework and of any UI so the rules can be unit tested directly.
///
/// Wi-Fi is one resource with a boolean state, unlike Bluetooth's set of devices, so the
/// rule is: last state wins, and if the state at the end of the debounce window equals the
/// last *announced* state, say nothing. That single rule absorbs rapid reconnects, AP
/// roaming, DHCP renegotiation and the unsatisfied/satisfied pair Wi-Fi emits on a channel
/// change, without any of them needing to be recognised individually.
struct WiFiActivityState: Equatable {
    enum Outcome: Equatable {
        case none
        case connected
        case disconnected
    }

    /// The last state the user was actually told about. `nil` until the first report, which
    /// is what keeps launch quiet on a Mac that is already online.
    private(set) var announcedConnected: Bool?

    /// The most recent report since the window opened. Only the last one matters.
    private(set) var pendingConnected: Bool?

    private(set) var isSuppressed: Bool = false

    /// Record the current connectivity. Cheap, and safe to call on every path update.
    mutating func note(isConnected: Bool) {
        pendingConnected = isConnected
    }

    /// Stop announcing anything, for a stretch where transitions are expected and
    /// meaningless — sleep tears the link down and wake brings it back.
    mutating func suppress() {
        isSuppressed = true
    }

    /// Resume announcing, silently adopting whatever happened while suppressed as the new
    /// baseline so the first post-wake report is not reported as a change.
    mutating func resume() {
        guard isSuppressed else { return }
        isSuppressed = false
        if let pending = pendingConnected {
            announcedConnected = pending
            pendingConnected = nil
        }
    }

    /// Resolve everything noted since the last flush into at most one announcement.
    mutating func flush(connectEnabled: Bool, disconnectEnabled: Bool) -> Outcome {
        guard !isSuppressed else { return .none }
        guard let pending = pendingConnected else { return .none }
        pendingConnected = nil

        // The first report is a statement of the current state, not a transition.
        guard let announced = announcedConnected else {
            announcedConnected = pending
            return .none
        }

        guard pending != announced else { return .none }

        // The baseline advances even when the matching setting is off. Gating the
        // bookkeeping instead would let re-enabling a setting mid-session fire an
        // announcement about a change that happened while it was disabled.
        announcedConnected = pending

        if pending {
            return connectEnabled ? .connected : .none
        }
        return disconnectEnabled ? .disconnected : .none
    }

    /// Back to the launch state, so a stop/start cycle re-seeds without announcing.
    mutating func reset() {
        announcedConnected = nil
        pendingConnected = nil
        isSuppressed = false
    }
}
