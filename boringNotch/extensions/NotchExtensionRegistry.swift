import Combine
import SwiftUI

struct ClosedNotchExtensionContext {
    let surfaceID: String
    let closedNotchWidth: CGFloat
    let displayHeight: CGFloat
}

struct ClosedNotchExtensionActivity {
    let id: String
    let priority: ClosedNotchPresentationPriority
    let updatedAt: Date
    let metrics: ClosedNotchLayoutMetrics
    let content: AnyView
    let opensNotchOnHover: Bool
    let opensNotchOnTap: Bool
    let onSelect: (() -> Void)?
}

struct NotchExtensionDescriptor {
    let id: String
    let updates: AnyPublisher<Void, Never>
    let start: () -> Void
    let stop: () -> Void
    let closedActivities: (ClosedNotchExtensionContext) -> [ClosedNotchExtensionActivity]
}

@MainActor
final class NotchExtensionRegistry: ObservableObject {
    static let shared = NotchExtensionRegistry(extensions: [CodexNotificationExtension.descriptor])

    private let extensions: [NotchExtensionDescriptor]
    private var cancellables: Set<AnyCancellable> = []
    private var started = false

    init(extensions: [NotchExtensionDescriptor]) {
        self.extensions = extensions
        for descriptor in extensions {
            descriptor.updates
                .receive(on: RunLoop.main)
                .sink { [weak self] in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }
    }

    func start() {
        guard !started else { return }
        started = true
        extensions.forEach { $0.start() }
    }

    func stop() {
        guard started else { return }
        started = false
        extensions.forEach { $0.stop() }
    }

    func closedActivities(context: ClosedNotchExtensionContext) -> [ClosedNotchExtensionActivity] {
        extensions.flatMap { $0.closedActivities(context) }
    }
}
