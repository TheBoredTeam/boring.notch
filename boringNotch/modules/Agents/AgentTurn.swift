//
//  AgentTurn.swift
//  boringNotch
//
//  Logique pure (Foundation seul) du suivi d'un tour : genre d'activité de chaque appel d'outil,
//  tranches de temps pour la bande de progression, liste de tâches de l'agent.
//

import Foundation

/// Ce que fait l'agent à un instant : sert à colorer la bande de progression.
enum ActivityKind: String, CaseIterable {
    case read, edit, run, other, wait

    static func of(tool: String) -> ActivityKind {
        switch tool {
        case "Read", "Grep", "Glob": return .read
        case "Edit", "Write", "MultiEdit": return .edit
        case "Bash": return .run
        default: return .other
        }
    }

    var label: String {
        switch self {
        case .read: return "lecture"
        case .edit: return "écriture"
        case .run: return "commandes"
        case .other: return "outils"
        case .wait: return "attente"
        }
    }
}

struct ActivityTick: Equatable {
    let kind: ActivityKind
    let at: Date
}

/// L'activité d'un tour (du prompt de l'utilisateur à la fin de la réponse de l'agent).
struct TurnActivity: Equatable {
    static let maxTicks = 2000

    var startedAt: Date
    var endedAt: Date?
    private(set) var ticks: [ActivityTick] = []   // chronologique ; les plus anciens tombent au-delà du plafond
    private(set) var files: Set<String> = []
    private(set) var added = 0
    private(set) var removed = 0

    init(startedAt: Date) { self.startedAt = startedAt }

    mutating func record(_ kind: ActivityKind, at: Date) {
        ticks.append(ActivityTick(kind: kind, at: at))
        // ponytail: plafond fixe, un tour de plusieurs heures perd le début de sa bande ; sous-échantillonner si ça gêne.
        if ticks.count > Self.maxTicks { ticks.removeFirst(ticks.count - Self.maxTicks) }
    }

    mutating func addDiff(file: String, added: Int, removed: Int) {
        files.insert(file)
        self.added += added
        self.removed += removed
    }

    func elapsed(now: Date) -> TimeInterval { (endedAt ?? now).timeIntervalSince(startedAt) }

    /// Durée lisible d'un coup d'œil : « 45 s », « 12 min », « 1 h 05 ».
    static func clock(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        if s < 60 { return "\(s) s" }
        if s < 3600 { return "\(s / 60) min" }
        return "\(s / 3600) h \(String(format: "%02d", s / 60 % 60))"
    }

    /// n tranches égales de startedAt à endedAt ?? now ; genre le plus fréquent de la tranche
    /// (égalité : le plus récent), nil si aucune activité.
    func buckets(_ n: Int, now: Date) -> [ActivityKind?] {
        guard n > 0 else { return [] }
        let end = endedAt ?? now
        let d = end.timeIntervalSince(startedAt) / Double(n)
        var counts = [[ActivityKind: Int]](repeating: [:], count: n)
        var last = [[ActivityKind: Int]](repeating: [:], count: n)   // rang du dernier tick de chaque genre
        for (rank, tick) in ticks.enumerated() where tick.at >= startedAt && tick.at <= end {
            let i = d > 0 ? min(n - 1, Int(tick.at.timeIntervalSince(startedAt) / d)) : 0
            counts[i][tick.kind, default: 0] += 1
            last[i][tick.kind] = rank
        }
        return (0..<n).map { i in
            if counts[i].isEmpty {
                // Une attente n'écrit qu'un tick : les tranches vides jusqu'au tick suivant (ou à la fin) en font partie.
                let from = startedAt + Double(i) * d
                return d > 0 && ticks.last(where: { $0.at >= startedAt && $0.at <= from })?.kind == .wait ? .wait : nil
            }
            return counts[i].max { a, b in
                a.value != b.value ? a.value < b.value : last[i][a.key]! < last[i][b.key]!
            }?.key
        }
    }

    /// Les 3 dernières phases distinctes (suites de tranches de même genre), dans l'ordre.
    func phases(now: Date) -> [ActivityKind] {
        var out: [ActivityKind] = []
        for k in buckets(28, now: now).compactMap({ $0 }) where out.last != k { out.append(k) }
        return Array(out.suffix(3))
    }
}

enum TaskStatus: String { case pending, inProgress = "in_progress", completed }

struct AgentTask: Equatable {
    var id: String
    var title: String
    var status: TaskStatus
}

/// La liste de tâches de l'agent, reconstruite depuis ses appels d'outil.
enum AgentTasks {
    /// Applique un appel d'outil de tâches à la liste ; renvoie nil si l'outil n'en est pas un.
    static func apply(tool: String, input: AgentEnvelope.ToolInput?, to list: [AgentTask]) -> [AgentTask]? {
        func status(_ s: String?) -> TaskStatus { s.flatMap(TaskStatus.init(rawValue:)) ?? .pending }
        func replaced(_ items: [AgentEnvelope.TaskItem]?) -> [AgentTask] {
            guard let items else { return list }   // liste absente ou illisible : on ne vide pas
            return items.enumerated().map { i, t in
                AgentTask(id: String(i + 1), title: t.content ?? t.subject ?? "", status: status(t.status))
            }
        }
        switch tool {
        case "TodoWrite": return replaced(input?.todos)
        case "mcp__ccd_turn__update_plan": return replaced(input?.items)
        case "TaskCreate":
            // ponytail: id = plus grand id numérique + 1, comme Claude Code les attribue ; faux si la dernière tâche
            // créée a été supprimée (son id serait réattribué) : lire tool_response si ça dérive.
            let next = (list.compactMap { Int($0.id) }.max() ?? 0) + 1
            return list + [AgentTask(id: String(next), title: input?.subject ?? "", status: .pending)]
        case "TaskUpdate":
            guard let id = input?.taskId, let i = list.firstIndex(where: { $0.id == id }) else { return list }
            var out = list
            if input?.status == "deleted" { out.remove(at: i) }
            else if let s = input?.status { out[i].status = status(s) }
            return out
        default: return nil
        }
    }
}
