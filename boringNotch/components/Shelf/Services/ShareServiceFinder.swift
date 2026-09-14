//
//  ShareServiceFinder.swift
//  boringNotch
//
//  Created by Alexander on 2025-10-06.
//

import AppKit

struct NamedSharingService {
    let name: NSSharingService.Name
    let service: NSSharingService
}

@MainActor
final class ShareServiceFinder {
    /// Public stable identities available through `NSSharingService(named:)`.
    static let supportedServiceNames: [NSSharingService.Name] = [
        .sendViaAirDrop,
        .composeEmail,
        .composeMessage,
        .addToSafariReadingList,
        .useAsDesktopPicture,
        .cloudSharing
    ]

    func findApplicableServices(for items: [Any]) async -> [NamedSharingService] {
        Self.supportedServiceNames.compactMap { name in
            guard let service = NSSharingService(named: name),
                  service.canPerform(withItems: items) else {
                return nil
            }
            return NamedSharingService(name: name, service: service)
        }
    }
}
