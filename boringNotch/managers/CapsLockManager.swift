//
//  CapsLockManager.swift
//  boringNotch
//
//  Created by Lucas Walker on 5/11/26.
//

import Foundation
import AppKit

final class CapsLockManager: ObservableObject {
    static let shared = CapsLockManager()

    @Published private(set) var isOn: Bool = false

    private var globalMonitor: Any?
    private var localMonitor: Any?

    private init() {
        isOn = NSEvent.modifierFlags.contains(.capsLock)

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.update(from: event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.update(from: event)
            return event
        }
    }

    private func update(from event: NSEvent) {
        let newValue = event.modifierFlags.contains(.capsLock)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.isOn != newValue {
                self.isOn = newValue
            }
        }
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }
}
