//
//  ShareServiceFinder.swift
//  boringNotch
//
//  Created by Alexander on 2025-10-06.
//

import Cocoa

class ShareServiceFinder: NSObject, NSSharingServicePickerDelegate {

    @MainActor
    private var onServicesCaptured: (([NSSharingService]) -> Void)?

    /// Returns share services asynchronously without blocking the UI
    @MainActor
    func findApplicableServices(for items: [Any], timeout: TimeInterval = 2.0) async -> [NSSharingService] {

        let dummyView = NSView(frame: .zero)
        let picker = NSSharingServicePicker(items: items)
        picker.delegate = self

        return await withCheckedContinuation { continuation in
            var didResume = false

            // Capture services callback
            Task { @MainActor in
                self.onServicesCaptured = { services in
                    guard !didResume else { return }
                    didResume = true
                    continuation.resume(returning: services)
                }
            }

            picker.show(relativeTo: dummyView.bounds, of: dummyView, preferredEdge: .minY)


            // Timeout task
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                guard !didResume else { return }
                didResume = true
                print("Warning: timed out waiting for sharing services")
                continuation.resume(returning: [])
            }
        }
    }

    // MARK: NSSharingServicePickerDelegate

    func sharingServicePicker(_ picker: NSSharingServicePicker,
                              sharingServicesForItems items: [Any],
                              proposedSharingServices proposed: [NSSharingService]) -> [NSSharingService] {
        Task { @MainActor in
            self.onServicesCaptured?(proposed)
        }
        return proposed
    }
}
