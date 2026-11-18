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
    private struct Rate { let match: String; let input: Double; let output: Double; let cacheRead: Double; let family: String }

    // ponytail: grille à la main, à mettre à jour quand les tarifs changent. Relevée le 2026-11-19 dans le skill
    // claude-api (tableau « Current Models » et shared/model-migration.md). Dollars par million de jetons ;
    // `cacheRead` = multiple du tarif d'entrée (0,05 Opus 5.5 et Sonnet 5.5 ; 0,025 Fable 5.1/5.2 ; 0,1 le reste).
    // Première correspondance par sous-chaîne du nom ; les générations listées par le skill passent en premier,
    // la dernière ligne de chaque famille (génération courante) sert de repli, y compris pour les générations
    // dont le skill ne donne pas le tarif (Opus 4.5…). Haiku 5.5 : tarif jusqu'à 100 K jetons de prompt
    // (0,50 / 2,50 au-delà, ignoré). Les caches 5 min / 1 h valent toujours ×1,25 / ×2 l'entrée.
    private static let rates: [Rate] = [
        Rate(match: "opus-5-5", input: 4, output: 20, cacheRead: 0.05, family: "Opus"),
        Rate(match: "opus-5", input: 5, output: 25, cacheRead: 0.1, family: "Opus"),
        Rate(match: "opus-4-8", input: 5, output: 25, cacheRead: 0.1, family: "Opus"),
        Rate(match: "opus-4-7", input: 5, output: 25, cacheRead: 0.1, family: "Opus"),
        Rate(match: "opus-4-6", input: 5, output: 25, cacheRead: 0.1, family: "Opus"),
        Rate(match: "opus", input: 4, output: 20, cacheRead: 0.05, family: "Opus"),
        Rate(match: "sonnet-5-5", input: 2, output: 10, cacheRead: 0.05, family: "Sonnet"),
        Rate(match: "sonnet-5", input: 2, output: 10, cacheRead: 0.1, family: "Sonnet"),
        Rate(match: "sonnet-4-6", input: 3, output: 15, cacheRead: 0.1, family: "Sonnet"),
        Rate(match: "sonnet", input: 2, output: 10, cacheRead: 0.05, family: "Sonnet"),
        Rate(match: "haiku-4-5", input: 1, output: 5, cacheRead: 0.1, family: "Haiku"),
        Rate(match: "haiku", input: 0.10, output: 0.50, cacheRead: 0.1, family: "Haiku"),
        Rate(match: "fable-5-2", input: 8, output: 40, cacheRead: 0.025, family: "Fable"),
        Rate(match: "fable-5-1", input: 10, output: 50, cacheRead: 0.025, family: "Fable"),
        Rate(match: "fable-5", input: 10, output: 50, cacheRead: 0.1, family: "Fable"),
        Rate(match: "fable", input: 8, output: 40, cacheRead: 0.025, family: "Fable"),
    ]

    private static func rate(_ model: String) -> Rate? {
        let m = model.lowercased()
        return rates.first { m.contains($0.match) }
    }

    /// "Opus", "Sonnet", "Haiku", "Fable" ; l'identifiant brut pour un modèle inconnu.
    static func familyName(_ model: String) -> String { rate(model)?.family ?? model }

    /// Valeur API en dollars ; 0 pour un modèle inconnu ou "<synthetic>".
    static func value(model: String, _ u: TokenUsage) -> Double {
        guard let r = rate(model) else { return 0 }
        let write1h = min(max(u.cacheWrite1h, 0), u.cacheWrite)
        let write5m = u.cacheWrite - write1h
        let perM = Double(u.input) * r.input + Double(u.output) * r.output
            + Double(write5m) * r.input * 1.25 + Double(write1h) * r.input * 2
            + Double(u.cacheRead) * r.input * r.cacheRead
        return perM / 1_000_000
    }
}

/// "yyyy-MM-dd" dans le fuseau de `calendar`.
func statsDayKey(_ date: Date, calendar: Calendar) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
}

enum StatsLine {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain = ISO8601DateFormatter()  // .withInternetDateTime par défaut
    private static let assistantMarker = Data("\"type\":\"assistant\"".utf8)

    /// Une ligne de journal -> sa consommation ; nil si ce n'est pas un message assistant avec usage et modèle connu.
    static func parse(_ line: Data, calendar: Calendar) -> StatsUsage? {
        // Filtre bon marché avant le JSON : l'essentiel des lignes d'un journal ne sont pas des messages assistant.
        guard line.range(of: assistantMarker) != nil,
              let o = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              o["type"] as? String == "assistant",
              let msg = o["message"] as? [String: Any],
              let id = msg["id"] as? String,
              let model = msg["model"] as? String, model != "<synthetic>",
              let u = msg["usage"] as? [String: Any],
              let ts = o["timestamp"] as? String, let date = fractional.date(from: ts) ?? plain.date(from: ts) else { return nil }
        func n(_ d: [String: Any], _ k: String) -> Int { (d[k] as? NSNumber)?.intValue ?? 0 }
        let write = n(u, "cache_creation_input_tokens")
        let write1h = (u["cache_creation"] as? [String: Any]).map { n($0, "ephemeral_1h_input_tokens") } ?? 0
        return StatsUsage(
            messageID: id, day: statsDayKey(date, calendar: calendar), model: model,
            project: AgentSession.projectName(o["cwd"] as? String),
            usage: TokenUsage(input: n(u, "input_tokens"), output: n(u, "output_tokens"),
                              cacheWrite: write, cacheRead: n(u, "cache_read_input_tokens"), cacheWrite1h: write1h))
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
    /// message.id déjà compté -> jour ("yyyy-MM-dd"). Global, tous fichiers confondus : une session reprise ou
    /// dupliquée recopie les mêmes messages dans un autre journal. À purger avec `prune(today:calendar:)`.
    var seen: [String: String] = [:]

    /// Ajoute les lignes complètes de `chunk` (lu à partir de offsets[path]) ; avance l'offset jusqu'au dernier "\n".
    mutating func ingest(path: String, chunk: Data, calendar: Calendar) {
        guard let last = chunk.lastIndex(of: 0x0A) else { return }
        let complete = chunk[chunk.startIndex...last]
        offsets[path, default: 0] += UInt64(complete.count)
        for raw in complete.split(separator: 0x0A) {
            // Claude Code écrit plusieurs lignes par message (même message.id, même usage) : on ne compte qu'une fois.
            guard let l = StatsLine.parse(Data(raw), calendar: calendar), seen[l.messageID] == nil else { continue }
            seen[l.messageID] = l.day
            let v = Pricing.value(model: l.model, l.usage)
            guard v > 0 else { continue }
            days[l.day, default: DayStats()].value += v
            days[l.day]!.byModel[l.model, default: 0] += v
            days[l.day]!.byProject[l.project, default: 0] += v
        }
    }

    /// Oublie les id vus il y a plus de 84 jours (la grille n'en affiche pas davantage). À appeler après chaque
    /// balayage des journaux : sans cela `seen` grossirait indéfiniment. Les offsets empêchent de relire
    /// les anciennes lignes, donc ce qu'on oublie ici ne peut plus être recompté.
    mutating func prune(today: Date, calendar: Calendar) {
        guard let limit = calendar.date(byAdding: .day, value: -84, to: today) else { return }
        let oldest = statsDayKey(limit, calendar: calendar)
        seen = seen.filter { $0.value >= oldest }  // "yyyy-MM-dd" : l'ordre alphabétique est l'ordre chronologique
    }
}

extension StatsBook {
    /// Balaye `root` (récursif, `*.jsonl`) et ingère ce qui a été ajouté depuis les offsets connus, par blocs de
    /// `block` octets : la première passe couvre des centaines de Mo, on ne charge jamais un fichier entier.
    /// Un fichier plus petit que son offset (tronqué, réécrit) repart de 0 ; les offsets des fichiers disparus sont
    /// oubliés ; `prune` est appelé en fin de balayage. Renvoie le nombre de journaux trouvés (0 si `root` n'existe pas).
    @discardableResult
    mutating func scan(root: String, calendar: Calendar, today: Date, block: Int = 8 << 20) -> Int {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root),
              let walk = fm.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var found: Set<String> = []
        for case let url as URL in walk where url.pathExtension == "jsonl" {
            let path = url.path
            found.insert(path)
            let size = UInt64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            if size < (offsets[path] ?? 0) { offsets[path] = 0 }
            let start = offsets[path] ?? 0
            guard size > start, let h = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? h.close() }
            try? h.seek(toOffset: start)
            // `rest` : fin de bloc sans "\n" final, reportée sur le bloc suivant (une ligne peut dépasser `block`).
            var rest = Data()
            while let d = try? h.read(upToCount: block), !d.isEmpty {
                rest.append(d)
                let before = offsets[path] ?? start
                autoreleasepool { ingest(path: path, chunk: rest, calendar: calendar) }
                rest = Data(rest.dropFirst(Int((offsets[path] ?? before) - before)))
            }
        }
        offsets = offsets.filter { found.contains($0.key) }
        prune(today: today, calendar: calendar)
        return found.count
    }
}

struct StatsSummary: Equatable {
    var today: Double
    var trend: Double?                              // today / moyenne des 7 jours précédents - 1 ; nil si cette moyenne vaut 0
    var models: [(name: String, share: Double)]     // 7 derniers jours, par famille ("Opus"…), part de la valeur, décroissant
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
        func shares(_ pick: (DayStats) -> [String: Double], name: (String) -> String = { $0 }) -> [(name: String, share: Double)] {
            var sum: [String: Double] = [:]
            for d in week { for (k, v) in pick(d) { sum[name(k), default: 0] += v } }
            let total = sum.values.reduce(0, +)
            guard total > 0 else { return [] }
            return sum.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .map { (name: $0.key, share: $0.value / total) }
        }
        return StatsSummary(
            today: now,
            trend: avg > 0 ? now / avg - 1 : nil,
            models: shares(\.byModel, name: Pricing.familyName),
            projects: Array(shares(\.byProject).prefix(3)),
            grid: (0..<84).reversed().map { stats($0)?.value ?? 0 })
    }
}
