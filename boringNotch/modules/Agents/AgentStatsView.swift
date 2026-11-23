//
//  AgentStatsView.swift
//  boringNotch
//
//  Page « Stats » de l'onglet Agents : valeur API du jour, modèles, projets et grille d'activité.
//  Le balayage des journaux Claude Code (`~/.claude/projects`) tourne hors du main actor ;
//  la logique d'agrégation vit dans AgentStats.swift.
//

import SwiftUI

@MainActor final class AgentStatsStore: ObservableObject {
    static let shared = AgentStatsStore()

    @Published private(set) var summary: StatsSummary?
    /// Aucun journal `*.jsonl` trouvé (dossier absent ou vide).
    @Published private(set) var noSessions = false

    private var book: StatsBook?
    private var last = Date.distantPast
    private var scanning = false

    /// Dossier réel de l'utilisateur, pas celui du conteneur : l'entitlement n'ouvre que `~/.claude/` en lecture.
    nonisolated private static let root = String(cString: getpwuid(getuid())!.pointee.pw_dir) + "/.claude/projects"
    nonisolated private static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("agent-stats.json")
    }

    /// Ignoré si un balayage tourne déjà ou si le dernier date de moins de 60 s.
    func refresh() {
        guard !scanning, Date().timeIntervalSince(last) >= 60 else { return }
        scanning = true
        let known = book
        Task.detached(priority: .utility) {
            let r = Self.work(known)
            await MainActor.run {
                self.book = r.book
                self.summary = r.summary
                self.noSessions = r.files == 0
                self.last = Date()
                self.scanning = false
            }
        }
    }

    // ponytail: le livre est réécrit en entier quand il change ; à passer en incrémental s'il dépasse quelques Mo.
    nonisolated private static func work(_ known: StatsBook?) -> (book: StatsBook, summary: StatsSummary, files: Int) {
        let calendar = Calendar.current, now = Date()
        let disk = known == nil ? try? Data(contentsOf: file) : nil   // le disque ne se lit qu'au premier chargement
        var book = known ?? disk.flatMap { try? JSONDecoder().decode(StatsBook.self, from: $0) } ?? StatsBook()
        let before = book
        let files = book.scan(root: root, calendar: calendar, today: now)
        if book != before || (known == nil && disk == nil) {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder().encode(book).write(to: file, options: .atomic)
        }
        return (book, StatsSummary.make(book, today: now, calendar: calendar), files)
    }
}

struct AgentStatsView: View {
    @ObservedObject private var store = AgentStatsStore.shared

    private static let money: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: "fr_FR")
        f.currencyCode = "USD"
        f.currencySymbol = "$"
        return f
    }()
    private static let muted = Color.white.opacity(0.65)

    var body: some View {
        Group {
            if let s = store.summary, !store.noSessions {
                page(s)
            } else if store.noSessions {
                AgentEmptyState(symbol: "chart.bar.xaxis", message: "Aucune session Claude trouvée")
            } else {
                AgentEmptyState(symbol: "chart.bar.xaxis", message: "Calcul des statistiques…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { store.refresh() }
    }

    /// Texte à gauche, grille à droite : 3 lignes + 7 carrés tiennent largement dans la hauteur restante du notch (190 pt).
    private func page(_ s: StatsSummary) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text("Aujourd'hui").foregroundStyle(Self.muted)
                    Text(Self.money.string(from: s.today as NSNumber) ?? "—").font(.system(size: 15, weight: .semibold)).monospacedDigit()
                    if let t = s.trend {
                        Text("\(t >= 0 ? "▲" : "▼")\(Int((abs(t) * 100).rounded())) %").foregroundStyle(t >= 0 ? .green : .red)
                    }
                    Text("valeur API").foregroundStyle(Self.muted)
                }
                .lineLimit(1)
                shares("Modèles, 7 jours", s.models)
                shares("Projets, 7 jours", s.projects)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            grid(s.grid)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .agentSurface()
    }

    private func shares(_ title: String, _ items: [(name: String, share: Double)]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 9.5)).foregroundStyle(Self.muted)
            Text(items.isEmpty ? "—" : items.map { "\($0.name) \(Int(($0.share * 100).rounded())) %" }.joined(separator: " · "))
                .lineLimit(1).truncationMode(.tail)
        }
    }

    /// 12 semaines (colonnes) × 7 jours, du plus ancien (en haut à gauche) à aujourd'hui (en bas à droite) ;
    /// intensité = valeur / max de la grille.
    private func grid(_ days: [Double]) -> some View {
        let top = max(days.max() ?? 0, .leastNonzeroMagnitude)
        return HStack(spacing: 2) {
            ForEach(0..<12, id: \.self) { w in
                VStack(spacing: 2) {
                    ForEach(0..<7, id: \.self) { d in
                        let v = days.indices.contains(w * 7 + d) ? days[w * 7 + d] : 0
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(v > 0 ? Color.effectiveAccent.opacity(0.2 + 0.8 * v / top) : Color.white.opacity(0.08))
                            .frame(width: 8, height: 8)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
