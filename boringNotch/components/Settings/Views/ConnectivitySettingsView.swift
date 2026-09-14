//
//  ConnectivitySettingsView.swift
//  boringNotch
//

import CoreLocation
import Defaults
import SwiftUI

struct ConnectivitySettings: View {
    @Default(.bluetoothConnectActivity) var connectActivity
    @Default(.bluetoothDisconnectActivity) var disconnectActivity
    @Default(.wifiConnectActivity) var wifiConnectActivity
    @Default(.wifiShowNetworkName) var wifiShowNetworkName

    @ObservedObject private var locationAuth = WiFiLocationAuthorization.shared

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .bluetoothConnectActivity) {
                    Text("Show connection activities")
                }
                Defaults.Toggle(key: .bluetoothDisconnectActivity) {
                    Text("Show disconnection activities")
                }
                Defaults.Toggle(key: .bluetoothDeviceBattery) {
                    Text("Show device battery")
                }
                .disabled(!connectActivity)
            } header: {
                Text("Bluetooth")
            } footer: {
                HelpText("Battery levels are only reported by some accessories, mainly Apple audio devices. Devices that use Bluetooth Low Energy only, such as many mice and keyboards, may not report connections at all.")
            }

            Section {
                Defaults.Toggle(key: .wifiConnectActivity) {
                    Text("Show connection activities")
                }
                Defaults.Toggle(key: .wifiDisconnectActivity) {
                    Text("Show disconnection activities")
                }
                Toggle(isOn: networkNameBinding) {
                    Text("Show network name")
                }
                .disabled(!wifiConnectActivity || locationAuth.isDenied)
                Defaults.Toggle(key: .wifiSignalStrength) {
                    Text("Show signal strength")
                }
                .disabled(!wifiConnectActivity)

                if locationAuth.isDenied {
                    Text("Location access is denied. Please enable it in System Settings.")
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("Open Location Settings") {
                        if let settingsURL = URL(
                            string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
                        ) {
                            NSWorkspace.shared.open(settingsURL)
                        }
                    }
                }
            } header: {
                Text("Wi-Fi")
            } footer: {
                HelpText("macOS only reveals the Wi-Fi network name to apps that have Location access, so showing it requires granting that permission. Without it the activity still appears, labelled simply \"Wi-Fi\". Your location is never stored or sent anywhere.")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Connectivity")
        // Reads the current status without prompting, so the toggle reflects reality as
        // soon as the pane opens.
        .task { locationAuth.prepare() }
    }

    /// Not a `Defaults.Toggle`, because the setting is only meaningful when the system has
    /// actually granted Location access — the toggle has to answer to authorization, not
    /// just to the stored preference.
    private var networkNameBinding: Binding<Bool> {
        Binding(
            get: { wifiShowNetworkName && locationAuth.isGranted },
            set: { isOn in
                guard isOn else {
                    Defaults[.wifiShowNetworkName] = false
                    return
                }
                switch locationAuth.status {
                case .notDetermined:
                    // Optimistic: a denial arrives via the delegate and switches it back.
                    Defaults[.wifiShowNetworkName] = true
                    locationAuth.request()
                case .authorizedAlways, .authorized:
                    Defaults[.wifiShowNetworkName] = true
                default:
                    // Denied or restricted: the prompt is spent, so leave it off and let
                    // the System Settings row below explain why.
                    Defaults[.wifiShowNetworkName] = false
                }
            }
        )
    }
}

#Preview {
    ConnectivitySettings().frame(width: 500, height: 600)
}
