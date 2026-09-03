import Foundation
import Network
import SystemConfiguration

final class VPNManager: ObservableObject {
    static let shared = VPNManager()

    @Published var isConnected = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.boringnotch.vpnmonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = Self.detectVPN(path: path)
            DispatchQueue.main.async {
                self?.isConnected = connected
            }
        }
        monitor.start(queue: queue)
    }

    private static func detectVPN(path: NWPath) -> Bool {
        for interface in path.availableInterfaces where interface.type == .other {
            let name = interface.name
            guard name.hasPrefix("utun") || name.hasPrefix("tap") ||
                    name.hasPrefix("tun") || name.hasPrefix("ppp") else { continue }

            // Verify IPv4 config exists (filters Apple system utun interfaces)
            if hasIPv4(on: name) { return true }
        }
        return false
    }

    private static func hasIPv4(on interface: String) -> Bool {
        guard let store = SCDynamicStoreCreate(nil, "BoringNotch" as CFString, nil, nil) else {
            return false
        }
        let key = "State:/Network/Interface/\(interface)/IPv4" as CFString
        return SCDynamicStoreCopyValue(store, key) != nil
    }

    deinit {
        monitor.cancel()
    }
}
