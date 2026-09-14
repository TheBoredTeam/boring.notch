//
//  NotchSystemView.swift
//  boringNotch
//

import Defaults
import SwiftUI

/// The System section of the opened notch: reference information that is useful to glance
/// at but never worth interrupting anyone with, so it lives here and never in the closed
/// notch.
///
/// Network lives here now; the Developer section joins it in the same surface rather than
/// claiming a tab of its own.
struct NotchSystemView: View {
    @Default(.showNetworkInformation) private var showNetwork

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                if showNetwork {
                    NetworkSection()
                } else {
                    Text("Nothing to show. Enable a section in Settings ▸ System.")
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 8)
    }
}

/// Live throughput and link details.
///
/// Sampling starts when this appears and stops when it goes away, so nothing is measured
/// while the notch is closed.
struct NetworkSection: View {
    @ObservedObject private var manager = NetworkActivityManager.shared
    @Default(.showPublicIPAddress) private var showPublicIP

    private var snapshot: NetworkSnapshot { manager.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .foregroundStyle(snapshot.isConnected ? .white : .gray)
                    .imageScale(.small)
                Text("Network")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer(minLength: 4)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(snapshot.isConnected ? .green : .gray)
            }

            HStack(alignment: .top, spacing: 20) {
                rate(
                    symbol: "arrow.down", label: Text("Download"),
                    value: snapshot.throughput.download)
                rate(symbol: "arrow.up", label: Text("Upload"), value: snapshot.throughput.upload)
            }

            VStack(alignment: .leading, spacing: 3) {
                if let ssid = snapshot.ssid {
                    // Runtime data, so verbatim: not a localization key.
                    detail(Text("Network"), Text(verbatim: ssid))
                }
                if let ip = snapshot.localIPv4 {
                    detail(Text("Local IP"), Text(verbatim: ip))
                }
                if showPublicIP {
                    detail(
                        Text("Public IP"),
                        snapshot.publicIPv4.map { Text(verbatim: $0) } ?? Text("Looking up…"))
                }
                if snapshot.isExpensive {
                    detail(Text("Connection"), Text("Metered"))
                }
            }
        }
        // The whole point of the phase: nothing is sampled unless this is on screen.
        .onAppear { manager.beginObserving() }
        .onDisappear { manager.endObserving() }
    }

    private var symbol: String {
        switch snapshot.kind {
        case .wifi: return "wifi"
        case .wired: return "cable.connector"
        case .cellular: return "antenna.radiowaves.left.and.right"
        case .other: return "network"
        case .none: return "wifi.slash"
        }
    }

    private var statusText: LocalizedStringKey {
        guard snapshot.isConnected else { return "Offline" }
        switch snapshot.kind {
        case .wifi: return "Wi-Fi"
        case .wired: return "Ethernet"
        case .cellular: return "Cellular"
        case .other, .none: return "Connected"
        }
    }

    private func rate(symbol: String, label: Text, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Image(systemName: symbol)
                    .imageScale(.small)
                    .foregroundStyle(.gray)
                label
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }
            Text(verbatim: NetworkActivityState.formatRate(value, formatter: Self.bytes))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .contentTransition(.numericText())
                // Rates move every second; gliding keeps the row from twitching.
                .animation(.smooth, value: value)
        }
    }

    private func detail(_ label: Text, _ value: Text) -> some View {
        HStack(spacing: 6) {
            label
                .font(.caption2)
                .foregroundStyle(.gray)
            Spacer(minLength: 4)
            value
                .font(.caption2)
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private static let bytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()
}

#Preview {
    NotchSystemView()
        .frame(width: 320, height: 170)
        .background(Color.black)
}
