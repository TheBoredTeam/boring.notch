//
//  AirPodsBatteryModel.swift
//  boringNotch
//

import Foundation

struct AirPodsBatteryDevice: Identifiable, Equatable {
    var id: String { address }

    let name: String
    let address: String
    let isConnected: Bool
    let isActiveAudioOutput: Bool

    var leftBattery: Int?
    var rightBattery: Int?
    var caseBattery: Int?
    var leftIsCharging: Bool?
    var rightIsCharging: Bool?
    var caseIsCharging: Bool?

    var hasBatteryData: Bool {
        leftBattery != nil || rightBattery != nil || caseBattery != nil
    }
}

struct AirPodsBatterySnapshot: Equatable {
    var devices: [AirPodsBatteryDevice] = []
    var statusMessage: String?

    static let unavailable = AirPodsBatterySnapshot(
        devices: [],
        statusMessage: "AirPods battery unavailable"
    )
}
