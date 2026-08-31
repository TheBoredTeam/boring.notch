//
//  BluetoothHeadphoneProfile.swift
//  boringNotch
//
//  Adapted from Cris2907/not-so-boring-notch.
//

import CoreAudio
import Foundation

struct BluetoothAudioDevice: Equatable, Identifiable {
    let audioObjectID: AudioObjectID
    let name: String
    let manufacturer: String?
    let modelUID: String?
    let transportType: UInt32
    let bluetoothAddress: String?
    let isBluetooth: Bool
    let detectedAt: Date

    var id: AudioObjectID { audioObjectID }

    var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Bluetooth headphones" : trimmedName
    }
}

struct BluetoothHeadphoneProfile: Equatable, Identifiable {
    let id: String
    let displayName: String
    let symbolName: String
    let modelKeys: [String]
    let manufacturerKeys: [String]
    let namePatterns: [String]

    init(
        id: String,
        displayName: String,
        symbolName: String = "headphones",
        modelKeys: [String] = [],
        manufacturerKeys: [String] = [],
        namePatterns: [String] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.symbolName = symbolName
        self.modelKeys = modelKeys.map(BluetoothHeadphoneProfileStore.normalize)
        self.manufacturerKeys = manufacturerKeys.map(BluetoothHeadphoneProfileStore.normalize)
        self.namePatterns = namePatterns.map(BluetoothHeadphoneProfileStore.normalize)
    }

    func resolvedDisplayName(for device: BluetoothAudioDevice) -> String {
        device.displayName == "Bluetooth headphones" ? displayName : device.displayName
    }
}

enum BluetoothHeadphoneProfileStore {
    static let fallbackProfile = BluetoothHeadphoneProfile(
        id: "generic-bluetooth-headphones",
        displayName: "Bluetooth headphones",
        symbolName: "headphones"
    )

    static let profiles: [BluetoothHeadphoneProfile] = [
        BluetoothHeadphoneProfile(
            id: "airpods-pro",
            displayName: "AirPods Pro",
            symbolName: "airpodspro",
            modelKeys: ["airpodspro", "airpods pro", "appleairpodspro", "apple airpods pro"],
            manufacturerKeys: ["apple"],
            namePatterns: ["airpods pro", "airpodspro"]
        ),
        BluetoothHeadphoneProfile(
            id: "airpods-max",
            displayName: "AirPods Max",
            symbolName: "airpodsmax",
            modelKeys: ["airpodsmax", "airpods max", "appleairpodsmax", "apple airpods max"],
            manufacturerKeys: ["apple"],
            namePatterns: ["airpods max", "airpodsmax"]
        ),
        BluetoothHeadphoneProfile(
            id: "airpods",
            displayName: "AirPods",
            symbolName: "airpods",
            modelKeys: ["airpods", "appleairpods", "apple airpods"],
            manufacturerKeys: ["apple"],
            namePatterns: ["airpods"]
        ),
        BluetoothHeadphoneProfile(
            id: "beats",
            displayName: "Beats",
            symbolName: "beats.headphones",
            manufacturerKeys: ["apple", "beats"],
            namePatterns: ["beats", "powerbeats", "studio buds", "studio pro", "fit pro"]
        ),
        BluetoothHeadphoneProfile(
            id: "sony",
            displayName: "Sony headphones",
            manufacturerKeys: ["sony"],
            namePatterns: ["wh-1000", "wh1000", "wf-1000", "wf1000", "linkbuds"]
        ),
        BluetoothHeadphoneProfile(
            id: "bose",
            displayName: "Bose headphones",
            manufacturerKeys: ["bose"],
            namePatterns: ["quietcomfort", "qc", "bose"]
        )
    ]

    static func profile(for device: BluetoothAudioDevice) -> BluetoothHeadphoneProfile {
        guard device.isBluetooth else { return fallbackProfile }

        let normalizedModel = normalize(device.modelUID)
        let normalizedManufacturer = normalize(device.manufacturer)
        let normalizedName = normalize(device.name)

        if let exactMatch = profiles.first(where: { profile in
            matchesAny(profile.modelKeys, in: normalizedModel)
        }) {
            return exactMatch
        }

        if let manufacturerMatch = profiles.first(where: { profile in
            matchesAny(profile.manufacturerKeys, in: normalizedManufacturer)
                && matchesAny(profile.namePatterns, in: normalizedName)
        }) {
            return manufacturerMatch
        }

        if let nameMatch = profiles.first(where: { profile in
            matchesAny(profile.namePatterns, in: normalizedName)
        }) {
            return nameMatch
        }

        return fallbackProfile
    }

    static func normalize(_ value: String?) -> String {
        value?
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func matchesAny(_ patterns: [String], in candidate: String) -> Bool {
        guard !candidate.isEmpty else { return false }
        return patterns.contains { pattern in
            !pattern.isEmpty && candidate.contains(pattern)
        }
    }
}
