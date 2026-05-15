import Foundation
import Combine
import AppKit

extension Notification.Name {
    static let kairoIncomingNotification = Notification.Name("KairoIncomingNotification")
}

@MainActor
final class KairoNotificationBridge: ObservableObject {
    @Published var items: [NotificationData] = []

    func start() {
        NotificationCenter.default.addObserver(
            forName: .kairoIncomingNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let data = note.object as? NotificationData else { return }
            Task { @MainActor in self?.prepend(data) }
        }
    }

    func prepend(_ item: NotificationData) {
        items.insert(item, at: 0)
        if items.count > 100 { items.removeLast() }
        KairoRuntime.shared.present(.notification, payload: item)
    }

    func dismiss(_ item: NotificationData) {
        items.removeAll { $0 == item }
    }

    func clearAll() { items.removeAll() }
}
