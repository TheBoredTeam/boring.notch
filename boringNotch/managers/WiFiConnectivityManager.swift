//
//  WiFiConnectivityManager.swift
//  boringNotch
//

import AppKit
import Defaults
import Foundation
import Network

/// Shows an activity in the notch when the Mac joins or leaves a Wi-Fi network.
///
/// ## Design notes
/// - The trigger is `NWPathMonitor`, not CoreWLAN's `CWEventDelegate`. CoreWLAN's events
///   fire on AP roaming *within* one network — a laptop carried across an office emits them
///   continuously with nothing user-visible changing — and `.ssidDidChange` carries no
///   payload anyway, so it buys no permission advantage. CoreWLAN is used only as an
///   on-demand read at presentation time, never to drive the timeline.
/// - `.unsatisfied` collapses "Wi-Fi powered off", "on but not associated" and "association
///   dropped" into one state. All three are shown as a disconnect, which matches the
///   Bluetooth precedent where powering off headphones reads as a disconnect.
/// - `.satisfied` is route-based, not a reachability probe, so a captive portal or a
///   printer-only network counts as connected. That is the intended reading of "joined".
@MainActor
final class WiFiConnectivityManager: ObservableObject {
    nonisolated static let shared = WiFiConnectivityManager()

    /// The network in the activity currently being shown.
    @Published private(set) var activeNetwork: WiFiNetworkInfo?
    @Published private(set) var isDisconnection: Bool = false

    private var state = WiFiActivityState()
    private var monitor: NWPathMonitor?
    private var coalesceTask: Task<Void, Never>?
    private var resumeTask: Task<Void, Never>?
    private var sleepObservers: [NSObjectProtocol] = []

    /// The BSD name of the Wi-Fi interface, kept so a USB dongle is read rather than the
    /// built-in radio. It survives a disconnect, when the path lists no interfaces.
    private var wifiInterfaceName: String?

    /// So a disconnect can name the network that was lost, the way the Bluetooth activity
    /// names the device that went away.
    private var lastKnownSSID: String?

    /// Wider than the Bluetooth manager's 600ms: Wi-Fi association is slower and noisier,
    /// and this window is what absorbs DHCP hiccups and re-association flap.
    private static let coalesceWindow: Duration = .milliseconds(1200)

    /// How long to stay quiet after wake while the link re-establishes itself.
    private static let wakeSettleWindow: Duration = .seconds(5)

    nonisolated private init() {}

    func start() {
        guard monitor == nil else { return }

        let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
        monitor.pathUpdateHandler = { [weak self] path in
            // Reduce the path to Sendable values here rather than passing it across.
            let isConnected = Self.isConnected(path)
            let interfaceName = path.availableInterfaces.first { $0.type == .wifi }?.name
            Task { @MainActor in
                self?.handlePathUpdate(isConnected: isConnected, interfaceName: interfaceName)
            }
        }
        monitor.start(queue: DispatchQueue(label: "boringNotch.wifi", qos: .utility))
        self.monitor = monitor

        observeSleepWake()
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
        coalesceTask?.cancel()
        coalesceTask = nil
        resumeTask?.cancel()
        resumeTask = nil

        let center = NSWorkspace.shared.notificationCenter
        sleepObservers.forEach { center.removeObserver($0) }
        sleepObservers.removeAll()

        // Back to the launch state, so a restart re-seeds silently instead of announcing
        // whatever the link happens to be doing.
        state.reset()
        wifiInterfaceName = nil
        lastKnownSSID = nil
    }

    // MARK: - Events

    /// The single place connectivity is derived from the path.
    ///
    /// Isolated deliberately: if the interface-restricted monitor ever misreports while
    /// Ethernet is the primary route, the fallback (an unrestricted monitor plus
    /// `availableInterfaces`) is a change to this one function.
    nonisolated private static func isConnected(_ path: NWPath) -> Bool {
        path.status == .satisfied
    }

    private func handlePathUpdate(isConnected: Bool, interfaceName: String?) {
        // A disconnect lists no interfaces, so only ever upgrade the remembered name.
        if let interfaceName { wifiInterfaceName = interfaceName }

        state.note(isConnected: isConnected)
        scheduleCoalescedPresentation()
    }

    private func observeSleepWake() {
        let center = NSWorkspace.shared.notificationCenter
        sleepObservers = [
            center.addObserver(
                forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.state.suppress() }
            },
            center.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.scheduleResume() }
            },
        ]
    }

    /// Wake tears the link down and brings it back; re-baseline once it has settled so the
    /// reconnection is not announced as news.
    private func scheduleResume() {
        resumeTask?.cancel()
        resumeTask = Task { [weak self] in
            try? await Task.sleep(for: Self.wakeSettleWindow)
            guard !Task.isCancelled else { return }
            await self?.resumeAfterWake()
        }
    }

    private func resumeAfterWake() {
        state.resume()
    }

    // MARK: - Presentation

    private func scheduleCoalescedPresentation() {
        coalesceTask?.cancel()
        coalesceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.coalesceWindow)
            guard !Task.isCancelled else { return }
            await self?.presentPending()
        }
    }

    private func presentPending() async {
        let outcome = state.flush(
            connectEnabled: Defaults[.wifiConnectActivity],
            disconnectEnabled: Defaults[.wifiDisconnectActivity]
        )
        guard outcome != .none else { return }

        let disconnected = outcome == .disconnected
        var network = WiFiNetworkInfo()

        if disconnected {
            network.ssid = lastKnownSSID
        } else {
            // Only touch the gated API when the user has opted in and the system has
            // actually granted it.
            let includeSSID = Defaults[.wifiShowNetworkName]
                && WiFiLocationAuthorization.shared.isGranted

            network = await WiFiInfoProvider.shared.info(
                bsdName: wifiInterfaceName,
                includeSSID: includeSSID,
                includeStrength: Defaults[.wifiSignalStrength]
            )
            lastKnownSSID = network.ssid
        }

        NSLog(
            "📶 Wi-Fi \(disconnected ? "disconnected" : "connected")"
                + (network.ssid.map { ": \($0)" } ?? "")
                + (disconnected || network.strength != nil ? "" : " (no signal reading)")
        )

        // Assigned after the await so the view never sees a bare record then a re-render.
        isDisconnection = disconnected
        activeNetwork = network
        BoringViewCoordinator.shared.toggleExpandingView(status: true, type: .wifi)
    }
}
