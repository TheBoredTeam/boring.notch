//
//  WiFiLocationAuthorization.swift
//  boringNotch
//

import CoreLocation
import Defaults
import Foundation

/// Location authorization, wanted for exactly one thing: the Wi-Fi network name.
///
/// macOS 14 moved `CWInterface.ssid()` behind Location Services for apps without the
/// `com.apple.developer.networking.wifi-info` entitlement, which needs a paid provisioning
/// profile this project does not have. So the name is opt-in, and everything here stays
/// dormant until the user asks for it in settings.
@MainActor
final class WiFiLocationAuthorization: ObservableObject {
    nonisolated static let shared = WiFiLocationAuthorization()

    @Published private(set) var status: CLAuthorizationStatus = .notDetermined

    /// macOS resolves a when-in-use request to always for a normal app.
    var isGranted: Bool { status == .authorizedAlways || status == .authorized }
    var isDenied: Bool { status == .denied || status == .restricted }

    private var manager: CLLocationManager?
    private let bridge = AuthorizationBridge()

    /// `CLLocationManagerDelegate` is an `@objc` protocol, so it needs an `NSObject` to
    /// target. Keeping that separate avoids making the whole class an `NSObject` subclass.
    private final class AuthorizationBridge: NSObject, CLLocationManagerDelegate {
        var onChange: ((CLAuthorizationStatus) -> Void)?

        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            // Read the status here and hand on only the enum. `CLAuthorizationStatus` is
            // Sendable; `CLLocationManager` is not, and capturing it in a Task is what
            // breaks strict concurrency.
            onChange?(manager.authorizationStatus)
        }
    }

    nonisolated private init() {}

    /// Create the manager and read the current status **without prompting**.
    ///
    /// Instantiating a `CLLocationManager` and reading `authorizationStatus` does not
    /// register the app in Location Services — only requesting does — so a user who never
    /// opens the Connectivity pane never appears in that list at all.
    func prepare() {
        guard manager == nil else { return }

        bridge.onChange = { [weak self] status in
            Task { @MainActor in self?.apply(status) }
        }

        let manager = CLLocationManager()
        manager.delegate = bridge
        self.manager = manager
        apply(manager.authorizationStatus)
    }

    /// Ask for authorization. The system prompt is one-shot for the life of the install:
    /// once denied, calling this again does nothing, which is why the UI branches on
    /// `isDenied` rather than re-prompting.
    func request() {
        prepare()
        manager?.requestWhenInUseAuthorization()
    }

    private func apply(_ status: CLAuthorizationStatus) {
        self.status = status

        // A denial has to switch the setting back off, or it would sit there claiming to
        // show a name the system will never hand over.
        if isDenied, Defaults[.wifiShowNetworkName] {
            Defaults[.wifiShowNetworkName] = false
        }
    }
}
