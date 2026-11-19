//
//  NotchModule.swift
//  boringNotch
//
//  Point d'extension : un module = un onglet dans le notch ouvert.
//  Ajouter une fonction = créer un module et l'ajouter à `NotchModules.all`.
//

import SwiftUI

protocol NotchModule {
    var id: String { get }
    var label: String { get }
    var icon: String { get }
    /// Appelé une fois au lancement de l'app.
    func start()
    @MainActor func makeView() -> AnyView
}

enum NotchModules {
    static let all: [any NotchModule] = [CalendarModule(), FocusModule(), AgentsModule(), AppVolumeModule(), ClipboardModule(), NotesModule()]

    static func startAll() { all.forEach { $0.start() } }

    @MainActor static func view(for id: String) -> AnyView {
        all.first { $0.id == id }?.makeView() ?? AnyView(EmptyView())
    }
}
