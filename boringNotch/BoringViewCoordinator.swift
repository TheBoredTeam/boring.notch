//
//  BoringViewCoordinator.swift
//  boringNotch
//
//  Created by Alexander on 2024-11-20.
//

import AppKit
import Combine
import CoreBluetooth
import Defaults
import IOBluetooth
import SwiftUI

enum SneakContentType {
    case brightness
    case volume
    case backlight
    case music
    case mic
    case battery
    case download
}

struct sneakPeek {
    var show: Bool = false
    var type: SneakContentType = .music
    var value: CGFloat = 0
    var icon: String = ""
}

struct SharedSneakPeek: Codable {
    var show: Bool
    var type: String
    var value: String
    var icon: String
}

enum BrowserType {
    case chromium
    case safari
}

struct ExpandedItem {
    var show: Bool = false
    var type: SneakContentType = .battery
    var value: CGFloat = 0
    var browser: BrowserType = .chromium
}

@MainActor
class BoringViewCoordinator: ObservableObject {
    static let shared = BoringViewCoordinator()

    @Published var currentView: NotchViews = .home
    @Published var helloAnimationRunning: Bool = false
    private var sneakPeekDispatch: DispatchWorkItem?
    private var expandingViewDispatch: DispatchWorkItem?
    private var hudEnableTask: Task<Void, Never>?

    @AppStorage("firstLaunch") var firstLaunch: Bool = true
    @AppStorage("showWhatsNew") var showWhatsNew: Bool = true
    @AppStorage("musicLiveActivityEnabled") var musicLiveActivityEnabled: Bool = true
    @AppStorage("bluetoothLiveActivityEnabled") var bluetoothLiveActivityEnabled: Bool = true
    @AppStorage("currentMicStatus") var currentMicStatus: Bool = true

    @AppStorage("alwaysShowTabs") var alwaysShowTabs: Bool = true {
        didSet {
            if !alwaysShowTabs {
                openLastTabByDefault = false
                if ShelfStateViewModel.shared.isEmpty || !Defaults[.openShelfByDefault] {
                    currentView = .home
                }
            }
        }
    }

    @AppStorage("openLastTabByDefault") var openLastTabByDefault: Bool = false {
        didSet {
            if openLastTabByDefault {
                alwaysShowTabs = true
            }
        }
    }
    
    @Default(.hudReplacement) var hudReplacement: Bool
    
    // Legacy storage for migration
    @AppStorage("preferred_screen_name") private var legacyPreferredScreenName: String?
    
    // New UUID-based storage
    @AppStorage("preferred_screen_uuid") var preferredScreenUUID: String? {
        didSet {
            if let uuid = preferredScreenUUID {
                selectedScreenUUID = uuid
            }
            NotificationCenter.default.post(name: Notification.Name.selectedScreenChanged, object: nil)
        }
    }

    @Published var selectedScreenUUID: String = NSScreen.main?.displayUUID ?? ""

    @Published var optionKeyPressed: Bool = true
    private var accessibilityObserver: Any?
    private var hudReplacementCancellable: AnyCancellable?

    private init() {
        // Perform migration from name-based to UUID-based storage
        if preferredScreenUUID == nil, let legacyName = legacyPreferredScreenName {
            // Try to find screen by name and migrate to UUID
            if let screen = NSScreen.screens.first(where: { $0.localizedName == legacyName }),
               let uuid = screen.displayUUID {
                preferredScreenUUID = uuid
                NSLog("✅ Migrated display preference from name '\(legacyName)' to UUID '\(uuid)'")
            } else {
                // Fallback to main screen if legacy screen not found
                preferredScreenUUID = NSScreen.main?.displayUUID
                NSLog("⚠️ Could not find display named '\(legacyName)', falling back to main screen")
            }
            // Clear legacy value after migration
            legacyPreferredScreenName = nil
        } else if preferredScreenUUID == nil {
            // No legacy value, use main screen
            preferredScreenUUID = NSScreen.main?.displayUUID
        }
        
        selectedScreenUUID = preferredScreenUUID ?? NSScreen.main?.displayUUID ?? ""
        // Observe changes to accessibility authorization and react accordingly
        accessibilityObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.accessibilityAuthorizationChanged,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                if Defaults[.hudReplacement] {
                    await MediaKeyInterceptor.shared.start(promptIfNeeded: false)
                }
            }
        }

        // Observe changes to hudReplacement
        hudReplacementCancellable = Defaults.publisher(.hudReplacement)
            .sink { [weak self] change in
                Task { @MainActor in
                    guard let self = self else { return }

                    self.hudEnableTask?.cancel()
                    self.hudEnableTask = nil

                    if change.newValue {
                        self.hudEnableTask = Task { @MainActor in
                            let granted = await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: true)
                            if Task.isCancelled { return }

                            if granted {
                                await MediaKeyInterceptor.shared.start()
                            } else {
                                Defaults[.hudReplacement] = false
                            }
                        }
                    } else {
                        MediaKeyInterceptor.shared.stop()
                    }
                }
            }

        Task { @MainActor in
            helloAnimationRunning = firstLaunch

            if Defaults[.hudReplacement] {
                let authorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
                if !authorized {
                    Defaults[.hudReplacement] = false
                } else {
                    await MediaKeyInterceptor.shared.start(promptIfNeeded: false)
                }
            }
        }
    }
    
    @objc func sneakPeekEvent(_ notification: Notification) {
        let decoder = JSONDecoder()
        if let decodedData = try? decoder.decode(
            SharedSneakPeek.self, from: notification.userInfo?.first?.value as! Data)
        {
            let contentType =
                decodedData.type == "brightness"
                ? SneakContentType.brightness
                : decodedData.type == "volume"
                    ? SneakContentType.volume
                    : decodedData.type == "backlight"
                        ? SneakContentType.backlight
                        : decodedData.type == "mic"
                            ? SneakContentType.mic : SneakContentType.brightness

            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.numberStyle = .decimal
            let value = CGFloat((formatter.number(from: decodedData.value) ?? 0.0).floatValue)
            let icon = decodedData.icon

            print("Decoded: \(decodedData), Parsed value: \(value)")

            toggleSneakPeek(status: decodedData.show, type: contentType, value: value, icon: icon)

        } else {
            print("Failed to decode JSON data")
        }
    }

    func toggleSneakPeek(
        status: Bool, type: SneakContentType, duration: TimeInterval = 1.5, value: CGFloat = 0,
        icon: String = ""
    ) {
        sneakPeekDuration = duration
        if type != .music {
            // close()
            if !Defaults[.hudReplacement] {
                return
            }
        }
        Task { @MainActor in
            withAnimation(.smooth) {
                self.sneakPeek.show = status
                self.sneakPeek.type = type
                self.sneakPeek.value = value
                self.sneakPeek.icon = icon
            }
        }

        if type == .mic {
            currentMicStatus = value == 1
        }
    }

    private var sneakPeekDuration: TimeInterval = 1.5
    private var sneakPeekTask: Task<Void, Never>?

    // Helper function to manage sneakPeek timer using Swift Concurrency
    private func scheduleSneakPeekHide(after duration: TimeInterval) {
        sneakPeekTask?.cancel()

        sneakPeekTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self = self, !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation {
                    self.toggleSneakPeek(status: false, type: .music)
                    self.sneakPeekDuration = 1.5
                }
            }
        }
    }

    @Published var sneakPeek: sneakPeek = .init() {
        didSet {
            if sneakPeek.show {
                scheduleSneakPeekHide(after: sneakPeekDuration)
            } else {
                sneakPeekTask?.cancel()
            }
        }
    }

    func toggleExpandingView(
        status: Bool,
        type: SneakContentType,
        value: CGFloat = 0,
        browser: BrowserType = .chromium
    ) {
        Task { @MainActor in
            withAnimation(.smooth) {
                self.expandingView.show = status
                self.expandingView.type = type
                self.expandingView.value = value
                self.expandingView.browser = browser
            }
        }
    }

    private var expandingViewTask: Task<Void, Never>?

    @Published var expandingView: ExpandedItem = .init() {
        didSet {
            if expandingView.show {
                expandingViewTask?.cancel()
                let duration: TimeInterval = (expandingView.type == .download ? 2 : 3)
                let currentType = expandingView.type
                expandingViewTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(duration))
                    guard let self = self, !Task.isCancelled else { return }
                    self.toggleExpandingView(status: false, type: currentType)
                }
            } else {
                expandingViewTask?.cancel()
            }
        }
    }
    
    func showEmpty() {
        currentView = .home
    }
}

// MARK: - Bluetooth Live Activity Support

enum BluetoothEventType {
    case connected
    case disconnected
    
    var symbolName: String {
        switch self {
        case .connected:
            return "checkmark.circle.fill"
        case .disconnected:
            return "xmark.circle.fill"
        }
    }
    
    var tint: Color {
        switch self {
        case .connected:
            return .green
        case .disconnected:
            return .red
        }
    }
    
    var statusText: String {
        switch self {
        case .connected:
            return "연결됨"
        case .disconnected:
            return "연결 해제됨"
        }
    }
}

struct BluetoothEvent: Equatable {
    let deviceName: String
    let address: String
    let type: BluetoothEventType
    let timestamp: Date
}

struct BluetoothDeviceInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let address: String
    let isConnected: Bool
}

@MainActor
class BluetoothManager: NSObject, ObservableObject {
    static let shared = BluetoothManager()
    private var centralManager: CBCentralManager?
    
    @Published private(set) var connectedDevices: [BluetoothDeviceInfo] = []
    @Published private(set) var latestEvent: BluetoothEvent?
    @Published private(set) var monitoringError: String?
    @Published private(set) var bleConnectedDevices: [BluetoothDeviceInfo] = []
    @Published var listInteractionActive: Bool = false
    
    private let connectedPeripheralChannel = PassthroughSubject<CBPeripheral, Never>()
    private let disconnectedPeripheralChannel = PassthroughSubject<CBPeripheral, Never>()
    private var bleSubscriptions = Set<AnyCancellable>()
    
    var hasConnectedDevices: Bool {
        !connectedDevices.isEmpty
    }
    
    var shouldShowLiveActivity: Bool {
        latestEvent != nil
    }
    
    private let displayDuration: TimeInterval = 6
    private let refreshInterval: TimeInterval = 7
    
    private var connectedIds: Set<String> = []
    private var refreshCancellable: AnyCancellable?
    private var eventDismissTask: Task<Void, Never>?
    
    override private init() {
        super.init()
        // BLE 권한 및 연결 기기 조회용 Central Manager
        centralManager = CBCentralManager(delegate: self, queue: DispatchQueue(label: "BoringNotch.BluetoothManager.Central", qos: .userInitiated))
        connectedPeripheralChannel
            .merge(with: disconnectedPeripheralChannel)
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.global(qos: .userInitiated))
            .sink { [weak self] _ in
                self?.refreshBLEConnectedDevices()
            }
            .store(in: &bleSubscriptions)
        refreshConnectedDevices()
        startMonitoring()
    }
    
    func manualRefresh() {
        refreshBLEConnectedDevices()
        refreshConnectedDevices()
    }
    
    private func startMonitoring() {
        refreshCancellable?.cancel()
        refreshCancellable = Timer.publish(every: refreshInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshBLEConnectedDevices()
                self?.refreshConnectedDevices()
            }
    }
    
    private func refreshConnectedDevices() {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            
            // Snapshot current state from the main actor
            let snapshot = await MainActor.run { (ids: self.connectedIds, devices: self.connectedDevices, ble: self.bleConnectedDevices) }
            
            let classic = self.fetchConnectedDevices()
            let mergedDevices = self.mergeDevices(classic: classic, ble: snapshot.ble)
            let newIds = Set(mergedDevices.map { $0.id })
            
            let added = newIds.subtracting(snapshot.ids)
            let removed = snapshot.ids.subtracting(newIds)
            
            var pendingEvent: BluetoothEvent?
            
            if let addedId = added.first,
               let device = mergedDevices.first(where: { $0.id == addedId })
            {
                pendingEvent = .init(
                    deviceName: device.name,
                    address: device.address,
                    type: .connected,
                    timestamp: Date()
                )
            } else if let removedId = removed.first,
                      let device = snapshot.devices.first(where: { $0.id == removedId })
            {
                pendingEvent = .init(
                    deviceName: device.name,
                    address: device.address,
                    type: .disconnected,
                    timestamp: Date()
                )
            }
            
            await MainActor.run {
                if let event = pendingEvent {
                    self.register(event: event)
                }
                self.connectedDevices = mergedDevices
                self.connectedIds = newIds
            }
        }
    }
    
    private func register(event: BluetoothEvent) {
        eventDismissTask?.cancel()
        latestEvent = event
        
        eventDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(displayDuration))
            guard !Task.isCancelled else { return }
            if self.latestEvent?.timestamp == event.timestamp {
                self.latestEvent = nil
            }
        }
    }
    
    nonisolated private func fetchConnectedDevices() -> [BluetoothDeviceInfo] {
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        let recent = (IOBluetoothDevice.recentDevices(0) as? [IOBluetoothDevice]) ?? []
        
        let candidates = paired + recent
        
        let deduped: [BluetoothDeviceInfo] = Dictionary(
            grouping: candidates,
            by: { $0.addressString ?? UUID().uuidString }
        )
        .compactMap { key, group in
            guard let device = group.first(where: { $0.isConnected() }) ?? group.first else {
                return nil
            }
            
            guard device.isConnected() else { return nil }
            
            return BluetoothDeviceInfo(
                id: key,
                name: device.name ?? "알 수 없는 기기",
                address: device.addressString ?? key,
                isConnected: true
            )
        }
        .sorted { $0.name < $1.name }
        
        return deduped
    }
    
    nonisolated private func mergeDevices(classic: [BluetoothDeviceInfo], ble: [BluetoothDeviceInfo]) -> [BluetoothDeviceInfo] {
        let combined = classic + ble
        
        func dedupKey(_ device: BluetoothDeviceInfo) -> String {
            if !device.address.isEmpty {
                return device.address.lowercased()
            }
            if !device.id.isEmpty {
                return device.id.lowercased()
            }
            return device.name.lowercased()
        }
        
        let merged: [BluetoothDeviceInfo] = Dictionary(grouping: combined, by: { dedupKey($0) })
            .compactMap { _, group in
                // Prefer connected entries; fall back to first
                group.first(where: { $0.isConnected }) ?? group.first
            }
            .sorted { $0.name < $1.name }
        return merged
    }

    @MainActor
    func setListInteractionActive(_ active: Bool) {
        listInteractionActive = active
    }
    
    private func refreshBLEConnectedDevices() {
        guard let centralManager else {
            Task { @MainActor in
                self.bleConnectedDevices = []
            }
            return
        }
        
        // Common services for HID/battery/device info + GAP/GATT 
        let serviceUUIDs = [
            CBUUID(string: "180F"), // Battery
            CBUUID(string: "1812"), // HID
            CBUUID(string: "180A"), // Device Information
            CBUUID(string: "1800"), // Generic Access
            CBUUID(string: "1801"), // Generic Attribute
        ]
        
        guard centralManager.state == .poweredOn else {
            Task { @MainActor in
                self.bleConnectedDevices = []
            }
            return
        }
        
        let peripherals = centralManager.retrieveConnectedPeripherals(withServices: serviceUUIDs)
        let mapped = peripherals.map { peripheral in
            BluetoothDeviceInfo(
                id: peripheral.identifier.uuidString,
                name: peripheral.name ?? "알 수 없는 기기",
                address: peripheral.identifier.uuidString,
                isConnected: true
            )
        }
        
        Task { @MainActor in
            self.bleConnectedDevices = mapped
        }
    }
}

// MARK: - Bluetooth permission helper / Central delegate

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            refreshBLEConnectedDevices()
        default:
            Task { @MainActor in
                self.bleConnectedDevices = []
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheralChannel.send(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        disconnectedPeripheralChannel.send(peripheral)
    }
}
