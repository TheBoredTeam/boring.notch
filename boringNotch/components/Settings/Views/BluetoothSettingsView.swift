//
//  BluetoothSettingsView.swift
//  boringNotch
//
//  Created by Murat ŞENOL on 30.04.2026.
//

import SwiftUI
import Defaults
import SymbolPicker

struct BluetoothSettings: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject private var bluetoothManager = BluetoothManager.shared
    @Default(.bluetoothDeviceIconMappings) var deviceIconMappings
    @Default(.enableBluetoothSneakPeek) var enableBluetoothSneakPeek
    @Default(.bluetoothSneakPeekStyle) var bluetoothSneakPeekStyle
    
    @State private var selectedMapping: BluetoothDeviceIconMapping? = nil
    @State private var isPresented: Bool = false
    @State private var deviceName: String = ""
    @State private var sfSymbolName: String = ""
    @State private var iconPickerPresented: Bool = false
    
    var body: some View {
        Form {
            if bluetoothManager.bluetoothState == .unauthorized {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Bluetooth access is required to detect connected devices and display their battery status.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 12) {
                            Button("Open Bluetooth Settings") {
                                if let settingsURL = URL(
                                    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"
                                ) {
                                    NSWorkspace.shared.open(settingsURL)
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.top, 6)
                } header: {
                    Text("Bluetooth Access")
                }
            } else if bluetoothManager.bluetoothState == .poweredOff {
                Text("Bluetooth is currently turned off.")
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(4)
            }
            
            Section {
                Toggle(
                    "Show Bluetooth live activity",
                    isOn: $coordinator.bluetoothLiveActivityEnabled.animation()
                )
            } header: {
                Text("Live activity")
            } footer: {
                Text("Displays connected Bluetooth devices and their battery status inside the notch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(bluetoothManager.bluetoothState == .unauthorized)
            
            Section {
                Toggle("Show sneak peek on device changes", isOn: $enableBluetoothSneakPeek)
                Picker("Sneak Peek Style", selection: $bluetoothSneakPeekStyle) {
                    ForEach(SneakPeekStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .disabled(!enableBluetoothSneakPeek)
            } header: {
                Text("Sneak peek")
            } footer: {
                Text("Sneak peek shows the Bluetooth device name under the notch for a few seconds when a device connects or disconnects.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!coordinator.bluetoothLiveActivityEnabled || bluetoothManager.bluetoothState == .unauthorized)
            
            Section {
                List {
                    ForEach(deviceIconMappings, id: \.UUID) { mapping in
                        HStack {
                            Image(systemName: mapping.sfSymbolName)
                                .frame(width: 20, height: 20)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mapping.deviceName)
                                    .font(.body)
                                Text(mapping.sfSymbolName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.vertical, 2)
                        .background(
                            selectedMapping != nil && selectedMapping?.UUID == mapping.UUID
                                ? Color.effectiveAccent.opacity(0.1) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedMapping?.UUID == mapping.UUID {
                                selectedMapping = nil
                            } else {
                                selectedMapping = mapping
                            }
                        }
                    }
                }
                .frame(minHeight: 120)
                .actionBar {
                    HStack(spacing: 5) {
                        Button {
                            deviceName = ""
                            sfSymbolName = ""
                            selectedMapping = nil
                            isPresented.toggle()
                        } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                        }
                        .controlSize(.large)
                        Divider()
                        Button {
                            if let mapping = selectedMapping {
                                deviceName = mapping.deviceName
                                sfSymbolName = mapping.sfSymbolName
                                isPresented.toggle()
                            }
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                        }
                        .disabled(selectedMapping == nil)
                        .controlSize(.large)
                        Divider()
                        Button {
                            if let mapping = selectedMapping {
                                deviceIconMappings.removeAll { $0.UUID == mapping.UUID }
                                selectedMapping = nil
                            }
                        } label: {
                            Image(systemName: "minus")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 2)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                        }
                        .controlSize(.large)
                        .disabled(selectedMapping == nil)
                    }
                }
                .controlSize(.small)
                .buttonStyle(PlainButtonStyle())
                .overlay {
                    if deviceIconMappings.isEmpty {
                        Text("No custom device icons")
                            .foregroundStyle(Color(.secondaryLabelColor))
                            .padding(.bottom, 22)
                    }
                }
                .sheet(isPresented: $iconPickerPresented) {
                    SymbolPicker(symbol: $sfSymbolName)
                }
                .sheet(isPresented: $isPresented) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(selectedMapping == nil ? "Add Device Icon" : "Edit Device Icon")
                            .font(.largeTitle.bold())
                            .padding(.vertical)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Device Name")
                                .font(.headline)
                            TextField("e.g., AirPods Pro, Magic Mouse", text: $deviceName)
                            Text("Enter a keyword or part of the device name. Matching is case-insensitive.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SF Symbol")
                                .font(.headline)
                            Button {
                                isPresented = false
                                iconPickerPresented = true
                            } label: {
                                HStack {
                                    if !sfSymbolName.isEmpty {
                                        Image(systemName: sfSymbolName)
                                            .foregroundStyle(.primary)
                                            .frame(width: 24, height: 24)
                                        Text(sfSymbolName)
                                            .foregroundStyle(.primary)
                                    } else {
                                        Text("Select SF Symbol")
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                                .padding()
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            Text("Choose an SF Symbol to represent this device.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        HStack {
                            Button {
                                isPresented.toggle()
                            } label: {
                                Text("Cancel")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            
                            Button {
                                if !deviceName.isEmpty && !sfSymbolName.isEmpty {
                                    if let existing = selectedMapping {
                                        // Editing existing mapping
                                        let trimmedDeviceName = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
                                        
                                        // Check if device name changed to one that already exists (different UUID)
                                        if let conflictingIndex = deviceIconMappings.firstIndex(where: {
                                            $0.UUID != existing.UUID &&
                                            $0.deviceName.localizedCaseInsensitiveCompare(trimmedDeviceName) == .orderedSame
                                        }) {
                                            // Update the existing mapping with the same device name and remove the one being edited
                                            let conflictingMapping = deviceIconMappings[conflictingIndex]
                                            deviceIconMappings[conflictingIndex] = BluetoothDeviceIconMapping(
                                                UUID: conflictingMapping.UUID,
                                                deviceName: conflictingMapping.deviceName,
                                                sfSymbolName: sfSymbolName
                                            )
                                            // Remove the mapping being edited
                                            deviceIconMappings.removeAll { $0.UUID == existing.UUID }
                                        } else {
                                            // Normal update - device name is unique or unchanged
                                            if let index = deviceIconMappings.firstIndex(where: { $0.UUID == existing.UUID }) {
                                                deviceIconMappings[index] = BluetoothDeviceIconMapping(
                                                    UUID: existing.UUID,
                                                    deviceName: deviceName,
                                                    sfSymbolName: sfSymbolName
                                                )
                                            }
                                        }
                                    } else {
                                        // Adding new mapping - check if device name already exists
                                        let trimmedDeviceName = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
                                        if let existingIndex = deviceIconMappings.firstIndex(where: {
                                            $0.deviceName.localizedCaseInsensitiveCompare(trimmedDeviceName) == .orderedSame
                                        }) {
                                            // Update existing mapping with same device name
                                            let existingMapping = deviceIconMappings[existingIndex]
                                            deviceIconMappings[existingIndex] = BluetoothDeviceIconMapping(
                                                UUID: existingMapping.UUID,
                                                deviceName: existingMapping.deviceName,
                                                sfSymbolName: sfSymbolName
                                            )
                                        } else {
                                            // Add new mapping
                                            let mapping = BluetoothDeviceIconMapping(
                                                deviceName: deviceName,
                                                sfSymbolName: sfSymbolName
                                            )
                                            deviceIconMappings.append(mapping)
                                        }
                                    }
                                }
                                isPresented.toggle()
                            } label: {
                                Text(selectedMapping == nil ? "Add" : "Save")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .buttonStyle(BorderedProminentButtonStyle())
                            .disabled(deviceName.isEmpty || sfSymbolName.isEmpty)
                        }
                    } // VSTACK
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .controlSize(.extraLarge)
                    .padding()
                    .background(.regularMaterial)
                }
            } header: {
                HStack(spacing: 0) {
                    Text("Custom Device Icons")
                    if !deviceIconMappings.isEmpty {
                        Text(" – \(deviceIconMappings.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Create custom icon mappings for Bluetooth devices. When a device name contains your keyword, the specified SF Symbol will be used.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!coordinator.bluetoothLiveActivityEnabled || bluetoothManager.bluetoothState == .unauthorized)
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Bluetooth")
        .onAppear {
            Task { @MainActor in
                // Check if Bluetooth is already initialized
                if bluetoothManager.isInitialized == false {
                    // Initialize Bluetooth when user opens settings (this will trigger permission prompt)
                    bluetoothManager.initializeBluetooth()
                }
            }
        }
        .onChange(of: sfSymbolName) { _, _ in
            iconPickerPresented = false
            isPresented = true
        }
    }
}
