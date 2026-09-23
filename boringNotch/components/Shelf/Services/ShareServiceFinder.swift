import AppKit

struct NamedSharingService {
    let name: NSSharingService.Name
    let service: NSSharingService
}

@MainActor
final class ShareServiceFinder {
    /// Stable identities for built-ins; extensions retain their existing native title identity.
    static let builtInServiceNames: [NSSharingService.Name] = [
        .sendViaAirDrop, .composeEmail, .composeMessage,
        .addToSafariReadingList, .useAsDesktopPicture, .cloudSharing
    ]

    private let discover: @MainActor ([Any]) async -> [NSSharingService]

    init(discover: @escaping @MainActor ([Any]) async -> [NSSharingService] = { items in
        await SharingServiceDiscoveryRequest().services(for: items)
    }) {
        self.discover = discover
    }

    func findApplicableServices(for items: [Any]) async -> [NamedSharingService] {
        let proposed = await discover(items)
        let builtIns = Self.builtInServiceNames.compactMap { name -> NamedSharingService? in
            guard let service = NSSharingService(named: name), service.canPerform(withItems: items) else {
                return nil
            }
            return NamedSharingService(name: name, service: service)
        }
        var services = builtIns
        var titles = Set(builtIns.map { $0.service.title })
        for service in proposed where service.canPerform(withItems: items) {
            guard titles.insert(service.title).inserted else { continue }
            services.append(NamedSharingService(name: .init(service.title), service: service))
        }
        return services
    }
}

/// Each native discovery owns its delegate, picker and terminal callback. Concurrent
/// requests cannot overwrite each other's continuation. The caller owns presentation.
@MainActor
private final class SharingServiceDiscoveryRequest: NSObject, @preconcurrency NSSharingServicePickerDelegate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var discoveredServices: [NSSharingService] = []
    private var picker: NSSharingServicePicker?
    private var timeout: Task<Void, Never>?

    func services(for items: [Any]) async -> [NSSharingService] {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let picker = NSSharingServicePicker(items: items)
            self.picker = picker
            picker.delegate = self
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.finish([])
            }
            let anchor = NSView(frame: .zero)
            picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        }
        return discoveredServices
    }

    func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker,
        sharingServicesForItems items: [Any],
        proposedSharingServices proposed: [NSSharingService]
    ) -> [NSSharingService] {
        // Finish after AppKit has returned from discovery, before displaying choices.
        Task { self.finish(proposed) }
        return []
    }

    private func finish(_ services: [NSSharingService]) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        timeout = nil
        picker?.close()
        picker = nil
        discoveredServices = services
        continuation.resume()
    }
}
