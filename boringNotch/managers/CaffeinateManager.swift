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
    @Published private(set) var endDate: Date?

    private var assertionID: IOPMAssertionID = 0
    private var timer: Timer?

    private init() {}

    func enable(duration: TimeInterval? = nil) {
        guard assertionID == 0 else { return }
        let reason = "boring.notch caffeinate" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )
        guard result == kIOReturnSuccess else { return }
        isActive = true

        if let duration {
            endDate = Date().addingTimeInterval(duration)
            timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                self?.disable()
            }
        }
    }

    func disable() {
        timer?.invalidate()
        timer = nil
        endDate = nil
        guard assertionID != 0 else {
            isActive = false
            return
        }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isActive = false
    }

    deinit {
        timer?.invalidate()
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
        }
    }
}
