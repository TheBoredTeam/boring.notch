//
//  NetworkActivityManager.swift
//  boringNotch
//

import Combine
import Defaults
import Foundation
import Network

/// Network information for the opened notch.
///
/// Unlike the other activity managers this one never touches the closed notch: throughput
/// numbers are reference material, not something worth interrupting anyone with. It also
/// only runs while its section is actually on screen — `beginObserving()` and
/// `endObserving()` are driven by the view's lifecycle, so a collapsed notch costs nothing.
///
/// Local statistics are read straight from the kernel; no request is made to any server to
/// find out how fast the link is going. The public IP address is the one exception, needs an
/// external request, and is therefore opt-in and off by default.
///
/// ## Limitations
/// - Throughput is measured on the *primary* interface only. Traffic over a second active
///   link (a VPN tunnel alongside Wi-Fi, say) is not added in.
/// - The first sample after opening the section reads zero: a rate needs two readings.
/// - The network name requires Location authorization, which is the existing
///   `wifiShowNetworkName` opt-in shared with the Wi-Fi activity.
/// - Round-trip latency is deliberately not measured. It cannot be obtained without sending
///   traffic, and the useful methods (ICMP) need a privileged raw socket the sandbox does
///   not allow. Guessing from a TCP handshake to an arbitrary host would measure that host
///   more than the connection.
@MainActor
final class NetworkActivityManager: ObservableObject {
    nonisolated static let shared = NetworkActivityManager()

    @Published private(set) var snapshot = NetworkSnapshot()

    /// Slow enough to stay invisible in Activity Monitor, quick enough that the numbers feel
    /// live. Only ever runs while the section is on screen.
    private static let sampleInterval: Duration = .seconds(1)

    private var monitor: NWPathMonitor?
    private var sampleTask: Task<Void, Never>?
    private var publicIPTask: Task<Void, Never>?

    private var previousCounters: InterfaceCounters?
    private var previousSampleAt: Date?

    /// Reference counted, because more than one view could show the section.
    private var observerCount = 0

    nonisolated private init() {}

    // MARK: - Lifecycle, driven by the view

    func beginObserving() {
        observerCount += 1
        guard observerCount == 1 else { return }

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            // Snapshot the parts we need here; NWPath is not Sendable.
            let status = path.status == .satisfied
            let expensive = path.isExpensive
            let interface = path.availableInterfaces.first
            let name = interface?.name
            let kind: NetworkInterfaceKind
            switch interface?.type {
            case .wifi: kind = .wifi
            case .wiredEthernet: kind = .wired
            case .cellular: kind = .cellular
            case .loopback, .other: kind = .other
            case nil: kind = .none
            @unknown default: kind = .other
            }
            Task { @MainActor [weak self] in
                self?.applyPath(
                    isConnected: status, kind: kind, interfaceName: name, isExpensive: expensive)
            }
        }
        monitor.start(queue: .main)
        self.monitor = monitor

        startSampling()
        NSLog("🌐 Network section observing")
    }

    func endObserving() {
        observerCount = max(0, observerCount - 1)
        guard observerCount == 0 else { return }

        sampleTask?.cancel()
        sampleTask = nil
        publicIPTask?.cancel()
        publicIPTask = nil
        monitor?.cancel()
        monitor = nil
        previousCounters = nil
        previousSampleAt = nil
        // Keep the last reading so reopening does not flash empty, but stop the rate: it is
        // no longer being measured and a stale number would be a lie.
        snapshot.throughput = .zero
        NSLog("🌐 Network section idle")
    }

    private func startSampling() {
        sampleTask?.cancel()
        sampleTask = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run { self?.sample() }
                try? await Task.sleep(for: Self.sampleInterval)
            }
        }
    }

    private func applyPath(
        isConnected: Bool, kind: NetworkInterfaceKind, interfaceName: String?, isExpensive: Bool
    ) {
        let interfaceChanged = interfaceName != snapshot.interfaceName
        snapshot.isConnected = isConnected
        snapshot.kind = kind
        snapshot.interfaceName = interfaceName
        snapshot.isExpensive = isExpensive

        if interfaceChanged {
            // Counters belong to the old interface and are meaningless against the new one.
            previousCounters = nil
            previousSampleAt = nil
            snapshot.throughput = .zero
            snapshot.localIPv4 = interfaceName.flatMap(Self.ipv4Address(of:))
            snapshot.ssid = nil
            refreshSSID()
        }

        refreshPublicIPIfNeeded()
    }

    private func sample() {
        guard let name = snapshot.interfaceName else { return }

        let counters = Self.counters(for: name)
        let now = Date()
        defer {
            previousCounters = counters
            previousSampleAt = now
        }

        guard let previous = previousCounters, let previousAt = previousSampleAt else { return }
        snapshot.throughput = NetworkActivityState.throughput(
            from: previous, to: counters, over: now.timeIntervalSince(previousAt))

        if snapshot.localIPv4 == nil {
            snapshot.localIPv4 = Self.ipv4Address(of: name)
        }
    }

    private func refreshSSID() {
        guard snapshot.kind == .wifi else { return }
        let name = snapshot.interfaceName
        // Reuses the Wi-Fi activity's provider, so the Location opt-in and its timeout are
        // shared rather than reimplemented.
        Task { @MainActor [weak self] in
            let info = await WiFiInfoProvider.shared.info(
                bsdName: name,
                includeSSID: Defaults[.wifiShowNetworkName],
                includeStrength: false
            )
            guard let self, self.snapshot.interfaceName == name else { return }
            self.snapshot.ssid = info.ssid
        }
    }

    // MARK: - Public IP (opt-in; the only thing here that talks to a server)

    private func refreshPublicIPIfNeeded() {
        guard Defaults[.showPublicIPAddress] else {
            snapshot.publicIPv4 = nil
            return
        }
        guard snapshot.isConnected, snapshot.publicIPv4 == nil, publicIPTask == nil else { return }

        publicIPTask = Task { [weak self] in
            defer { Task { @MainActor in self?.publicIPTask = nil } }
            guard let address = await Self.fetchPublicIP() else { return }
            await MainActor.run { self?.snapshot.publicIPv4 = address }
        }
    }

    /// Asks one well-known service for the address this machine appears as.
    ///
    /// Fetched once per connection change rather than on every sample — it does not change
    /// between samples, and repeating it would be traffic spent on nothing.
    nonisolated private static func fetchPublicIP() async -> String? {
        guard let url = URL(string: "https://api.ipify.org") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let text = String(data: data, encoding: .utf8)
        else { return nil }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Only accept something that actually looks like an address, so an error page or a
        // captive-portal redirect never gets shown as one.
        guard !trimmed.isEmpty, trimmed.count <= 45,
              trimmed.allSatisfy({ $0.isHexDigit || $0 == "." || $0 == ":" })
        else { return nil }
        return trimmed
    }

    // MARK: - Kernel reads

    /// Cumulative counters for one interface.
    ///
    /// Uses the routing table's `if_msghdr2`, whose `if_data64` counters are 64 bit. The
    /// `if_data` that `getifaddrs` reports is only 32 bit and wraps every few gigabytes —
    /// which on a machine that has already moved 2.8 GB is not a theoretical concern.
    nonisolated private static func counters(for interfaceName: String) -> InterfaceCounters {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else {
            return InterfaceCounters()
        }

        var buffer = [UInt8](repeating: 0, count: size)
        let fetched = buffer.withUnsafeMutableBytes {
            sysctl(&mib, u_int(mib.count), $0.baseAddress, &size, nil, 0)
        }
        guard fetched == 0 else { return InterfaceCounters() }

        var result = InterfaceCounters()
        buffer.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < size {
                let header = base.advanced(by: offset)
                    .assumingMemoryBound(to: if_msghdr.self).pointee
                let length = Int(header.ifm_msglen)
                guard length > 0 else { break }
                defer { offset += length }
                guard header.ifm_type == RTM_IFINFO2 else { continue }

                let message = base.advanced(by: offset)
                    .assumingMemoryBound(to: if_msghdr2.self).pointee
                let link = base.advanced(by: offset + MemoryLayout<if_msghdr2>.size)
                    .assumingMemoryBound(to: sockaddr_dl.self).pointee
                guard link.sdl_nlen > 0 else { continue }

                var storage = link.sdl_data
                let name = withUnsafePointer(to: &storage) { pointer -> String in
                    pointer.withMemoryRebound(to: UInt8.self, capacity: Int(link.sdl_nlen)) {
                        String(
                            decoding: UnsafeBufferPointer(start: $0, count: Int(link.sdl_nlen)),
                            as: UTF8.self)
                    }
                }
                guard name == interfaceName else { continue }
                result = InterfaceCounters(
                    received: message.ifm_data.ifi_ibytes, sent: message.ifm_data.ifi_obytes)
                return
            }
        }
        return result
    }

    nonisolated private static func ipv4Address(of interfaceName: String) -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let start = head else { return nil }
        defer { freeifaddrs(head) }

        for pointer in sequence(first: start, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let address = entry.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET),
                  String(cString: entry.ifa_name) == interfaceName
            else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                nil, 0, NI_NUMERICHOST) == 0
            else { continue }
            return String(cString: host)
        }
        return nil
    }
}
