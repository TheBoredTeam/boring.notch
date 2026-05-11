//
//  CaffeinateManager.swift
//  boringNotch
//
//  Created by Lucas Walker on 5/3/26.
//

import Foundation
import IOKit.pwr_mgt

final class CaffeinateManager: ObservableObject {
    static let shared = CaffeinateManager()

    @Published private(set) var isActive: Bool = false

    private var assertionID: IOPMAssertionID = 0

    private init() {}

    func toggle() {
        isActive ? disable() : enable()
    }

    private func enable() {
        guard assertionID == 0 else { return }
        let reason = "boring.notch caffeinate" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )
        if result == kIOReturnSuccess {
            isActive = true
        }
    }

    private func disable() {
        guard assertionID != 0 else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isActive = false
    }

    deinit {
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
        }
    }
}
