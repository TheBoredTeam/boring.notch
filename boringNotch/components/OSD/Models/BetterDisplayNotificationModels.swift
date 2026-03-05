//
//  BetterDisplayNotificationModels.swift
//  boringNotch
//
//  Created by Alexander on 2026-02-07.
//

import Foundation

// MARK: - BetterDisplay OSD Notification Data
// Matches the struct documented at:
// https://github.com/waydabber/BetterDisplay/wiki/Integration-features,-CLI#osd-notification-dispatch-integration
struct BetterDisplayOSDNotification: Codable {
    var displayID: Int?          // Which display should show the OSD
    var systemIconID: Int?       // 1 = brightness, 3 = volume, 4 = mute, 0 = no icon
    var customSymbol: String?    // SF Symbol name if a custom icon is used
    var text: String?
    var lock: Bool?
    var controlTarget: String?   // "combinedBrightness", "hardwareBrightness", "softwareBrightness", "volume", "mute", etc.
    var value: Double?           // OSD value (scale: 0–maxValue)
    var maxValue: Double?        // max value
    var symbolFadeAfter: Int?
    var symbolSizeMultiplier: Double?
    var textFadeAfter: Int?
}

// MARK: - BetterDisplay Request Notification Data
// For sending requests to BetterDisplay via DistributedNotificationCenter
struct BetterDisplayNotificationRequestData: Codable {
    var uuid: String?
    var commands: [String] = []
    var parameters: [String: String?] = [:]
}

struct BetterDisplayNotificationResponseData: Codable {
    var uuid: String?
    var result: Bool?
    var payload: String?
}
