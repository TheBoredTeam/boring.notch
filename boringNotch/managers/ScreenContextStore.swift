// SPDX-License-Identifier: GPL-3.0-only

/// Retains resources for connected display identities. A topology change only
/// disposes removed identities; geometry changes are updates to existing owners.
@MainActor
final class ScreenContextStore<Context> {
    private(set) var contexts: [String: Context] = [:]

    func reconcile<Screen>(
        screens: [String: Screen],
        create: (String, Screen) -> Context,
        remove: (Context) -> Void
    ) {
        let desired = Set(screens.keys)
        for id in Array(contexts.keys) where !desired.contains(id) {
            if let context = contexts.removeValue(forKey: id) {
                remove(context)
            }
        }
        for (id, screen) in screens where contexts[id] == nil {
            contexts[id] = create(id, screen)
        }
    }
}
