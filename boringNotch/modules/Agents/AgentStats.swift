//
//  AgentStats.swift
//  boringNotch
//
//  Logique pure (Foundation seul) des statistiques : lecture des lignes de journal Claude Code
//  (`~/.claude/projects/**/*.jsonl`) et agrégation de la « valeur API » par jour, modèle et projet.
//  La lecture des fichiers et la vue vivent ailleurs.
//

import Foundation

/// Jetons d'un message. `cacheWrite1h` est la part de `cacheWrite` en cache d'une heure (le reste : 5 min).
struct TokenUsage: Equatable {
    var input: Int
    var output: Int
    var cacheWrite: Int
    var cacheRead: Int
    var cacheWrite1h: Int = 0
}

// Nommé StatsUsage (et non UsageLine) : AgentsView.swift déclare déjà une vue privée UsageLine.
struct StatsUsage: Equatable {
    let messageID: String
    let day: String
    let model: String
    let project: String
    let usage: TokenUsage
}

enum Pricing {
    // ponytail: grille à la main, à mettre à jour quand les tarifs changent. Relevée le 2026-11-19 dans le skill
    // claude-api, génération courante de chaque famille (les anciennes générations, plus chères, sont comptées
    // au même tarif : reconnaissance par sous-chaîne du nom). Dollars par million de jetons : (entrée, sortie).
    // Haiku : tarif jusqu'à 100 K jetons de prompt (0,50 / 2,50 au-delà, ignoré).
    private static let families: [(name: String, input: Double, output: Double)] = [
        ("opus", 4, 20),     // claude-opus-5-5
        ("sonnet", 2, 10),   // claude-sonnet-5-5
        ("haiku", 0.10, 0.50), // claude-haiku-5-5
        ("fable", 8, 40),    // claude-fable-5-2
    ]

    /// Valeur API en dollars ; 0 pour un modèle inconnu ou "<synthetic>".
    static func value(model: String, _ u: TokenUsage) -> Double {
        let m = model.lowercased()
        guard let f = families.first(where: { m.contains($0.name) }) else { return 0 }
        let write1h = min(max(u.cacheWrite1h, 0), u.cacheWrite)
        let write5m = u.cacheWrite - write1h
        let perM = Double(u.input) * f.input + Double(u.output) * f.output
            + Double(write5m) * f.input * 1.25 + Double(write1h) * f.input * 2
            + Double(u.cacheRead) * f.input * 0.1
        return perM / 1_000_000
    }
}

/// "yyyy-MM-dd" dans le fuseau de `calendar`.
func statsDayKey(_ date: Date, calendar: Calendar) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
}

enum StatsLine {
    /// Une ligne de journal -> sa consommation ; nil si ce n'est pas un message assistant avec usage et modèle connu.
    static func parse(_ line: Data, calendar: Calendar) -> StatsUsage? {
        guard let o = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              o["type"] as? String == "assistant",
              let msg = o["message"] as? [String: Any],
              let id = msg["id"] as? String,
              let model = msg["model"] as? String, model != "<synthetic>",
              let u = msg["usage"] as? [String: Any],
              let ts = o["timestamp"] as? String, let date = parseDate(ts) else { return nil }
        func n(_ d: [String: Any], _ k: String) -> Int { (d[k] as? NSNumber)?.intValue ?? 0 }
        let write = n(u, "cache_creation_input_tokens")
        let write1h = (u["cache_creation"] as? [String: Any]).map { n($0, "ephemeral_1h_input_tokens") } ?? 0
        return StatsUsage(
            messageID: id, day: statsDayKey(date, calendar: calendar), model: model,
            project: AgentSession.projectName(o["cwd"] as? String),
            usage: TokenUsage(input: n(u, "input_tokens"), output: n(u, "output_tokens"),
                              cacheWrite: write, cacheRead: n(u, "cache_read_input_tokens"), cacheWrite1h: write1h))
    }

    private static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

struct DayStats: Codable, Equatable {
    var value = 0.0
    var byModel: [String: Double] = [:]
    var byProject: [String: Double] = [:]
}

struct StatsBook: Codable, Equatable {
    var days: [String: DayStats] = [:]       // "yyyy-MM-dd", fuseau local
    var offsets: [String: UInt64] = [:]      // chemin de fichier -> octets déjà lus
    var recentIDs: [String: [String]] = [:]  // chemin -> 50 derniers message.id vus (dédoublonnage)

    /// Ajoute les lignes complètes de `chunk` (lu à partir de offsets[path]) ; avance l'offset jusqu'au dernier "\n".
    mutating func ingest(path: String, chunk: Data, calendar: Calendar) {
        guard let last = chunk.lastIndex(of: 0x0A) else { return }
        let complete = chunk[chunk.startIndex...last]
        offsets[path, default: 0] += UInt64(complete.count)
        var seen = recentIDs[path] ?? []
        for raw in complete.split(separator: 0x0A) {
            // Claude Code écrit plusieurs lignes par message (même message.id, même usage) : on ne compte qu'une fois.
            guard let l = StatsLine.parse(Data(raw), calendar: calendar), !seen.contains(l.messageID) else { continue }
            seen.append(l.messageID)
            let v = Pricing.value(model: l.model, l.usage)
            guard v > 0 else { continue }
            days[l.day, default: DayStats()].value += v
            days[l.day]!.byModel[l.model, default: 0] += v
            days[l.day]!.byProject[l.project, default: 0] += v
        }
        // ponytail: 50 derniers id seulement ; les doublons d'un même message sont voisins dans le fichier.
        recentIDs[path] = Array(seen.suffix(50))
    }
}

struct StatsSummary: Equatable {
    var today: Double
    var trend: Double?                              // today / moyenne des 7 jours précédents - 1 ; nil si cette moyenne vaut 0
    var models: [(name: String, share: Double)]     // 7 derniers jours, part de la valeur, décroissant
    var projects: [(name: String, share: Double)]   // idem, 3 premiers
    var grid: [Double]                              // 84 jours, du plus ancien à aujourd'hui

    static func == (a: StatsSummary, b: StatsSummary) -> Bool {
        a.today == b.today && a.trend == b.trend && a.grid == b.grid
            && a.models.map(\.name) == b.models.map(\.name) && a.models.map(\.share) == b.models.map(\.share)
            && a.projects.map(\.name) == b.projects.map(\.name) && a.projects.map(\.share) == b.projects.map(\.share)
    }

    static func make(_ book: StatsBook, today: Date, calendar: Calendar) -> StatsSummary {
        func stats(_ back: Int) -> DayStats? {
            guard let d = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            return book.days[statsDayKey(d, calendar: calendar)]
        }
        let now = stats(0)?.value ?? 0
        let avg = (1...7).reduce(0.0) { $0 + (stats($1)?.value ?? 0) } / 7
        let week = (0..<7).compactMap { stats($0) }
        func shares(_ pick: (DayStats) -> [String: Double]) -> [(name: String, share: Double)] {
            var sum: [String: Double] = [:]
            for d in week { for (k, v) in pick(d) { sum[k, default: 0] += v } }
            let total = sum.values.reduce(0, +)
            guard total > 0 else { return [] }
            return sum.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .map { (name: $0.key, share: $0.value / total) }
        }
        return StatsSummary(
            today: now,
            trend: avg > 0 ? now / avg - 1 : nil,
            models: shares(\.byModel),
            projects: Array(shares(\.byProject).prefix(3)),
            grid: (0..<84).reversed().map { stats($0)?.value ?? 0 })
    }
}
