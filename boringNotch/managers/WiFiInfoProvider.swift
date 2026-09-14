//
//  WiFiInfoProvider.swift
//  boringNotch
//

import CoreWLAN
import Foundation

/// Reads whatever CoreWLAN is willing to tell us about the current network.
///
/// Both interesting details are gated to some degree, so this is written to return a
/// partially-filled answer rather than to fail:
///
/// - `ssid()` needs Location authorization on macOS 14+ (the alternative,
///   `com.apple.developer.networking.wifi-info`, needs a paid provisioning profile).
/// - `rssiValue()` is *not* documented as gated, but reports conflict, so the reading is
///   range-checked rather than trusted. CoreWLAN also returns 0 when not associated.
///
/// Nothing here is ever awaited on the critical path for longer than `timeout`: the
/// activity must appear whether or not these reads succeed.
@MainActor
final class WiFiInfoProvider {
    nonisolated static let shared = WiFiInfoProvider()

    /// Much shorter than the Bluetooth battery timeout — these are local reads, not an XPC
    /// round trip.
    private static let timeout: Duration = .milliseconds(400)

    nonisolated private init() {}

    func info(bsdName: String?, includeSSID: Bool, includeStrength: Bool) async -> WiFiNetworkInfo {
        let result = await withTaskGroup(of: WiFiNetworkInfo?.self) { group in
            group.addTask {
                Self.read(
                    bsdName: bsdName,
                    includeSSID: includeSSID,
                    includeStrength: includeStrength
                )
            }
            group.addTask {
                try? await Task.sleep(for: Self.timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }

        return result ?? WiFiNetworkInfo()
    }

    /// Every CoreWLAN object is created, read and discarded inside this function.
    /// `CWInterface` is not `Sendable`, so none of it may outlive the call.
    nonisolated private static func read(
        bsdName: String?,
        includeSSID: Bool,
        includeStrength: Bool
    ) -> WiFiNetworkInfo {
        let client = CWWiFiClient.shared()
        // Prefer the interface the path actually named, so a USB dongle is read rather than
        // the built-in radio.
        guard let interface = bsdName.flatMap({ client.interface(withName: $0) })
            ?? client.interface()
        else {
            return WiFiNetworkInfo(isPoweredOn: false)
        }

        var info = WiFiNetworkInfo()
        info.isPoweredOn = interface.powerOn()

        if includeSSID {
            // nil is routine, not an error: without authorization macOS simply withholds it.
            info.ssid = interface.ssid()
        }
        if includeStrength {
            // The initialiser rejects 0 and anything implausible, which covers both "not
            // associated" and a possible permission-gated zero.
            info.strength = WiFiSignalStrength(rssi: interface.rssiValue())
        }

        return info
    }
}
