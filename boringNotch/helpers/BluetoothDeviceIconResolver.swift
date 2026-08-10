//
//  BluetoothDeviceIconResolver.swift
//  boringNotch
//

import Foundation

/// Maps a device snapshot + user overrides to an SF Symbol name for the notch UI.
enum BluetoothDeviceIconResolver {
    static let fallbackSymbolName = "circle.badge.questionmark"

    static func sfSymbolName(for snapshot: BluetoothDeviceSnapshot, customMappings: [BluetoothDeviceIconMapping]) -> String {
        let deviceName = snapshot.name

        for mapping in customMappings {
            if deviceName.localizedCaseInsensitiveContains(mapping.deviceName) {
                return mapping.sfSymbolName
            }
        }

        if let iconName = sfSymbolForDeviceName(deviceName) {
            return iconName
        }

        if let minor = snapshot.minorDeviceClass,
           let iconName = sfSymbolForMinorDeviceClass(minor) {
            return iconName
        }

        return fallbackSymbolName
    }

    private static func sfSymbolForMinorDeviceClass(_ type: String) -> String? {
        let lowercasedType = type.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        switch lowercasedType {
        case "keyboard":
            return "keyboard.fill"
        case "mouse", "pointing device":
            return "computermouse.fill"
        case "gamepad", "joystick", "remote control", "gaming controller":
            return "gamecontroller.fill"
        case "headset", "hands-free device", "headphones":
            return "headphones"
        case "loudspeaker", "portable audio device", "car audio":
            return "hifispeaker.fill"
        case "microphone", "camcorder", "video camera", "video conferencing":
            return "speaker.wave.3.fill"
        case "cellular", "smart phone", "cordless phone", "modem":
            return "smartphone"
        case "desktop workstation", "server-class computer", "laptop", "handheld pc/pda", "palm sized pc/pda", "tablet":
            return "desktopcomputer"
        case "wristwatch", "pager", "jacket", "helmet", "glasses":
            return "watch.analog"
        case "blood pressure monitor", "thermometer", "weighing scale", "glucose meter", "pulse oximeter", "heart/pulse rate monitor":
            return "circle.badge.questionmark"
        default:
            return nil
        }
    }

    private static func sfSymbolForDeviceName(_ deviceName: String) -> String? {
        let name = deviceName.lowercased()

        if name.contains("airpods max") { return "airpodsmax" }
        if name.contains("airpods pro") { return "airpodspro" }
        if name.contains("airpods case") { return "airpodschargingcase" }
        if name.contains("airpods") { return "airpods" }

        if name.contains("beats studio buds") { return "beats.studiobuds" }
        if name.contains("beats solo buds") { return "beats.solobuds" }
        if name.contains("beats solo") { return "beats.headphones" }
        if name.contains("beats studio") { return "beats.headphones" }
        if name.contains("powerbeats pro") { return "beats.powerbeats.pro" }
        if name.contains("beats fit pro") { return "beats.fitpro" }
        if name.contains("beats flex") { return "beats.earphones" }

        if name.contains("buds") { return "earbuds" }
        if name.contains("headphone") || name.contains("headset") { return "headphones" }
        if name.contains("speaker") { return "hifispeaker.fill" }

        if name.contains("keyboard") { return "keyboard.fill" }
        if name.contains("mouse"), name.contains("magic") { return "magicmouse.fill" }
        if name.contains("mouse") { return "computermouse.fill" }

        if name.contains("gamepad") || name.contains("controller") || name.contains("joy-con") { return "gamecontroller.fill" }
        if name.contains("phone") { return "smartphone" }

        return nil
    }
}
