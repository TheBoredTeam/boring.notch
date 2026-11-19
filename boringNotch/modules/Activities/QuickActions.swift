//
//  QuickActions.swift
//  boringNotch
//
//  Réglages rapides de l'onglet Focus : éjecter les disques externes, vider la corbeille.
//  Éjection par NSWorkspace (repli : Apple Event au Finder) ; corbeille par Apple Event au Finder
//  (l'app est sandboxée, elle ne peut pas toucher ~/.Trash). La confirmation vit dans la vue (ConfirmGate).
//

import AppKit

@MainActor
final class QuickActions: ObservableObject {
    static let shared = QuickActions()

    @Published private(set) var ejectable: [URL] = []
    /// false seulement si le Finder confirme que la corbeille est vide ; en cas de doute, le bouton reste actif.
    @Published private(set) var trashHasItems = true
    /// Message d'échec affiché 2 s puis remis à nil.
    @Published private(set) var failure: String?
    /// Opérations en cours : les boutons sont grisés et un second clic ne relance rien.
    @Published private(set) var ejecting = false
    @Published private(set) var emptying = false
    private var failureTask: Task<Void, Never>?

    private static let finderDenied = -1743   // errAEEventNotPermitted : autorisation Automatisation refusée

    private init() {
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
    }

    func refresh() {
        // Externe = éjectable ou amovible, et pas explicitement interne (nil = externe : ne jamais tester « == false »).
        let keys: [URLResourceKey] = [.volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsInternalKey]
        ejectable = (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? [])
            .filter { url in
                guard let v = try? url.resourceValues(forKeys: Set(keys)) else { return false }
                return (v.volumeIsEjectable == true || v.volumeIsRemovable == true) && v.volumeIsInternal != true
            }
        Task {
            // Le compte n'est demandé que si l'autorisation est déjà accordée : l'invite macOS doit venir au premier clic.
            guard await Self.finderAuthorized() else { trashHasItems = true; return }
            let count = try? await AppleScriptHelper.execute("tell application \"Finder\" to count items of trash")?.int32Value
            trashHasItems = count.map { $0 > 0 } ?? true
        }
    }

    /// Autorisation Automatisation → Finder déjà accordée ? Sans jamais ouvrir l'invite ; hors du main thread (peut bloquer).
    private nonisolated static func finderAuthorized() async -> Bool {
        await Task.detached {
            let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
            return AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false) == noErr
        }.value
    }

    func ejectAll() {
        let volumes = ejectable
        guard !volumes.isEmpty, !ejecting else { return }
        ejecting = true
        Task {
            defer { ejecting = false }
            var failed: [String] = []
            for url in volumes {
                let name = (try? url.resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? url.lastPathComponent
                // ponytail: après un démontage NSWorkspace, une image disque peut rester attachée en arrière-plan ; accepté.
                if (try? await Task.detached { try NSWorkspace.shared.unmountAndEjectDevice(at: url) }.value) != nil { continue }
                let escaped = name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                do { try await AppleScriptHelper.executeVoid("tell application \"Finder\" to eject disk \"\(escaped)\"") }
                catch { failed.append(name) }
            }
            refresh()
            if !failed.isEmpty { fail("Impossible d'éjecter : \(failed.joined(separator: ", "))") }
        }
    }

    /// La confirmation (double clic) est faite par l'appelant.
    func emptyTrash() {
        guard !emptying else { return }
        emptying = true
        Task {
            defer { emptying = false }
            do {
                try await AppleScriptHelper.executeVoid("tell application \"Finder\" to empty trash")
                refresh()
            } catch {
                let number = (error as NSError).userInfo[NSAppleScript.errorNumber] as? Int
                // Message long à lire (infobulle, délai de survol) : affiché 6 s au lieu de 2 s.
                if number == Self.finderDenied {
                    fail("Autorisation refusée : Réglages Système → Confidentialité → Automatisation", for: 6)
                } else {
                    fail("Impossible de vider la corbeille")
                }
            }
        }
    }

    private func fail(_ message: String, for seconds: Double = 2) {
        failure = message
        failureTask?.cancel()
        failureTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled { failure = nil }
        }
    }
}
