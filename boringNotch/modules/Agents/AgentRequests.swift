//
//  AgentRequests.swift
//  boringNotch
//
//  File des validations en attente, une entrée par demande (et non par session) : la carte affichée
//  ne change pas sous le curseur quand une autre demande arrive, et chaque hook est libéré
//  individuellement. Logique pure, testée par scripts/agents-suivi-selftest.
//

import Foundation

/// Une demande de validation (PermissionRequest bloquant) en attente d'une décision.
struct PendingRequest: Identifiable, Equatable {
    let id: String            // UUID généré par l'app
    let sessionID: String
    let tool: String
    let toolUseID: String?    // si le payload PermissionRequest en a un
    var ask: PermissionAsk?   // action en attente de validation, déjà mise en français
    var questions: [AgentQuestion]?   // AskUserQuestion en attente de réponse
    var plan: String?                 // ExitPlanMode : plan (Markdown) en attente d'approbation
    var canAnswer: Bool       // le hook est bloquant : le notch peut répondre (sinon : au terminal)
    let at: Date
}

struct RequestQueue: Equatable {
    private(set) var items: [PendingRequest] = []     // ordre d'arrivée
    var current: PendingRequest? { items.first }

    mutating func add(_ r: PendingRequest) { items.append(r) }

    mutating func remove(id: String) -> PendingRequest? {
        items.firstIndex { $0.id == id }.map { items.remove(at: $0) }
    }

    /// Retire les demandes traitées ailleurs ; renvoie leurs ids (pour libérer les hooks).
    /// PostToolUse : la première demande de la session au même tool_use_id, ou, faute d'id sur la demande, au même outil.
    /// UserPromptSubmit / Stop / SessionEnd : toutes celles de la session. Tout autre événement ne retire rien.
    mutating func resolve(session: String, event: String, tool: String?, toolUseID: String?) -> [String] {
        switch event {
        case "PostToolUse":
            guard let i = items.firstIndex(where: {
                $0.sessionID == session && ($0.toolUseID != nil ? $0.toolUseID == toolUseID : $0.tool == tool)
            }) else { return [] }
            return [items.remove(at: i).id]
        case "UserPromptSubmit", "Stop", "SessionEnd":
            return drop { $0.sessionID == session }
        default:
            return []
        }
    }

    /// Demandes plus vieilles que le délai du hook (il a rendu la main à l'agent) ; renvoie leurs ids.
    mutating func expire(now: Date, after: TimeInterval) -> [String] {
        drop { now.timeIntervalSince($0.at) > after }
    }

    func pending(in session: String) -> Bool { items.contains { $0.sessionID == session } }

    private mutating func drop(_ match: (PendingRequest) -> Bool) -> [String] {
        let ids = items.filter(match).map(\.id)
        items.removeAll(where: match)
        return ids
    }
}
