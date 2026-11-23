//
//  AgentsView.swift
//  boringNotch
//
//  Surfaces et contrôles accordés aux Copies : fond sombre, liserés discrets,
//  aperçu d'activité et priorité aux questions / validations.
//

import Defaults
import SwiftUI

// MARK: - Style par agent / état

extension AgentState {
    var color: Color {
        switch self {
        case .thinking: .blue
        case .running: .green
        case .waiting: .orange
        case .done: .gray
        }
    }
    var label: String {
        switch self {
        case .thinking: "Réfléchit…"
        case .running(let tool): tool
        case .waiting: "Attend une approbation"
        case .done: "Terminé"
        }
    }
}

extension AgentStep {
    var symbol: String {
        switch tool {
        case "Bash": "terminal"
        case "Read": "doc.text"
        case "Edit", "Write", "MultiEdit": "pencil"
        case "Grep", "Glob": "magnifyingglass"
        case "Task", "Agent": "person.2"
        case "WebFetch", "WebSearch": "globe"
        default: "wrench.adjustable"
        }
    }
    var kind: String {
        switch tool {
        case "Bash": "Commande"
        case "Read": "Lecture"
        case "Edit", "Write", "MultiEdit": "Édition"
        case "Grep", "Glob": "Recherche"
        case "Task", "Agent": "Sous-agent"
        case "WebFetch", "WebSearch": "Web"
        default: tool
        }
    }
}

private func agentIcon(_ source: String) -> String {
    switch source {
    case "claude": "sparkle"
    case "codex": "chevron.left.forwardslash.chevron.right"
    case "cursor": "cursorarrow.rays"
    default: "terminal"
    }
}

private func accent(_ source: String) -> Color {
    switch source {
    case "claude": Color(red: 0.93, green: 0.50, blue: 0.27)
    case "codex": Color(red: 0.55, green: 0.68, blue: 1.0)
    default: .white
    }
}

extension AgentSession {
    /// Même code couleur que la bulle : rouge = validation, orange = travail, vert = repos.
    var tint: Color { state == .waiting ? .red : isActive ? .orange : awaitsReply ? .blue : .green }
    var stateText: String {
        switch state {
        case .waiting: questions != nil ? "Question pour vous" : plan != nil ? "Plan à valider" : "Validation requise"
        case .thinking where isActive: "Réfléchit…"
        case .running where isActive: "Au travail"
        default: awaitsReply ? "Attend votre réponse" : "Au repos"
        }
    }
}

private let secondary = Color.white.opacity(0.65)
private let cardFill = Color.white.opacity(0.065)
private let cardStroke = Color.white.opacity(0.08)

extension View {
    /// Surface de tuile des onglets du notch (Agents, Focus).
    func agentSurface(selected: Bool = false, tint: Color = .effectiveAccent) -> some View {
        background(selected ? tint.opacity(0.12) : cardFill, in: RoundedRectangle(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(selected ? tint.opacity(0.6) : cardStroke)
            }
    }
}

/// One control treatment for navigation, approvals and question actions (also used by Focus).
struct AgentActionStyle: ButtonStyle {
    var tint: Color? = nil
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(tint ?? .white.opacity(0.85))
            .padding(.horizontal, 10)
            .frame(minHeight: 24)
            .background((tint ?? .white).opacity(configuration.isPressed ? 0.22 : hovering ? 0.15 : tint == nil ? 0.065 : 0.12), in: Capsule())
            .overlay(Capsule().strokeBorder((tint ?? .white).opacity(hovering ? 0.45 : 0.12)))
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovering)
    }
}

private struct AgentEmptyState: View {
    let symbol: String
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 23, weight: .light))
                .foregroundStyle(Color.effectiveAccent)
                .frame(width: 44, height: 44)
                .background(Color.effectiveAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Onglet

struct AgentsView: View {
    private enum Mode { case progress, usage }

    @ObservedObject private var store = AgentStore.shared
    @State private var mode = Mode.progress
    @State private var selected: String?

    private var session: AgentSession? {
        store.sessions.first { $0.id == selected } ?? store.sessions.first
    }
    private var freshUsage: [(source: String, limits: UsageLimits)] {
        store.usage.compactMap { k, v in v.current().map { (k, $0) } }.sorted { $0.0 < $1.0 }.map { ($0.0, $0.1) }
    }

    /// Session qui attend une réponse, un plan ou une autorisation : elle prend tout l'onglet, quelle que soit la sélection.
    private var prompting: AgentSession? {
        store.sessions.first { $0.state == .waiting && ($0.questions?.isEmpty == false || $0.plan != nil || $0.ask != nil) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Pendant une question ou un plan : ni en-tête « Progression » ni en-tête de session,
            // la carte a besoin de toute la hauteur du notch (190 pt, barre d'onglets comprise).
            if let s = prompting, let qs = s.questions, !qs.isEmpty {
                QuestionCard(session: s, questions: qs).id(s.id + qs.map(\.question).joined())
            } else if let s = prompting, let plan = s.plan {
                PlanCard(session: s, plan: plan)
            } else if let s = prompting, let ask = s.ask {
                PermissionCard(session: s, ask: ask)
            } else {
                header
                switch mode {
                case .progress: progress
                case .usage: usagePage
                }
            }
        }
        .padding(.horizontal, 4)
        // Hauteur du notch ouvert fixe (190) : on ne déborde jamais, sinon la mise en page remonte hors de l'écran.
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
    }

    // MARK: En-tête

    private var header: some View {
        HStack(spacing: 8) {
            if let s = session {
                sessionPicker(s)
            } else {
                Label("Agents", systemImage: "sparkles")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(secondary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 3) {
                modeButton("Progression", icon: "checklist", mode: .progress)
                modeButton("Forfait", icon: "gauge.with.dots.needle.50percent", mode: .usage)
            }
        }
        .frame(height: 24)
    }

    /// Liste du sélecteur : ce qui demande l'utilisateur d'abord, puis ce qui travaille,
    /// puis seulement les 5 conversations au repos les plus récentes (le reste n'est que du bruit).
    private var groups: [(title: String, items: [AgentSession])] {
        let all = store.sessions
        let attention = all.filter { $0.state == .waiting || ($0.awaitsReply && !$0.isActive) }
        let ids = Set(attention.map(\.id))
        let working = all.filter { $0.isActive && !ids.contains($0.id) }
        let taken = ids.union(working.map(\.id))
        let recent = Array(all.filter { !taken.contains($0.id) }.prefix(5))
        return [("À traiter", attention), ("Au travail", working), ("Récentes", recent)].filter { !$0.1.isEmpty }
    }

    private func sessionPicker(_ s: AgentSession) -> some View {
        let hidden = store.sessions.count - groups.reduce(0) { $0 + $1.items.count }
        return Menu {
            ForEach(groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.items) { candidate in
                        Button { selected = candidate.id } label: {
                            Label("\(candidate.project) — \(String((candidate.title ?? candidate.stateText).prefix(52)))",
                                  systemImage: candidate.id == s.id ? "checkmark" : agentIcon(candidate.source))
                        }
                    }
                }
            }
            if hidden > 0 { Text("+ \(hidden) plus anciennes masquées") }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(s.tint).frame(width: 6, height: 6)
                Text(s.project).lineLimit(1).truncationMode(.middle)
                if store.sessions.count > 1 {
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                }
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.white.opacity(0.85))
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(AgentActionStyle())
        .fixedSize(horizontal: false, vertical: true)
        .help("Choisir une session")
        .accessibilityLabel("Session : \(s.project), \(s.source.capitalized)")
    }

    private func modeButton(_ title: String, icon: String, mode target: Mode) -> some View {
        Button { mode = target } label: {
            Label(title, systemImage: icon)
                .lineLimit(1)
        }
        .buttonStyle(AgentActionStyle(tint: mode == target ? .effectiveAccent : nil))
        .accessibilityAddTraits(mode == target ? [.isSelected] : [])
    }

    // MARK: Progression

    @ViewBuilder private var progress: some View {
        if let s = session {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    agentHeader(s)
                    stepList(s)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                ActivityCard(session: s).frame(width: 210)
            }
        } else {
            AgentEmptyState(symbol: "sparkles", message: "Aucune session en cours")
        }
    }

    private func agentHeader(_ s: AgentSession) -> some View {
        Button { AgentStore.shared.openTerminal(s) } label: { agentHeaderContent(s) }
            .buttonStyle(.plain)
            .help("\(s.title ?? s.project)\n\(s.openLabel)")
            .accessibilityLabel("\(s.title ?? s.project), \(s.source.capitalized), \(s.stateText)")
            .accessibilityHint(s.openLabel)
    }

    private func agentHeaderContent(_ s: AgentSession) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(s.tint.opacity(0.12))
                if s.source == "claude" {
                    Mascot(color: s.tint).scaleEffect(0.8)
                } else {
                    Image(systemName: agentIcon(s.source)).font(.system(size: 12)).foregroundStyle(s.tint)
                }
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.title ?? s.project)
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                HStack(spacing: 5) {
                    Text(s.source.capitalized).foregroundStyle(secondary)
                    if s.link != nil {
                        Text("·").foregroundStyle(secondary)
                        Text("T3 Code").foregroundStyle(secondary)
                    }
                    Text("·").foregroundStyle(secondary)
                    Text(s.stateText).foregroundStyle(s.tint)
                }
                .font(.system(size: 10, weight: .medium)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.up.forward.app").font(.system(size: 10)).foregroundStyle(secondary)
        }
        .contentShape(Rectangle())
    }

    private func stepList(_ s: AgentSession) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !s.isActive, let msg = s.lastMessage {
                // Au repos : ce que l'agent a dit en dernier, c'est ce qu'on veut relire (surtout sa question).
                HStack(alignment: .top, spacing: 8) {
                    Capsule().fill(s.awaitsReply ? s.tint : .white.opacity(0.18)).frame(width: 2)
                    Text(msg).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.85))
                        .lineLimit(4).fixedSize(horizontal: false, vertical: true)
                }
                .fixedSize(horizontal: false, vertical: true)
                .help(msg)
            } else if s.steps.isEmpty {
                Text(s.isActive ? s.state.label : "En attente d'un prompt")
                    .font(.system(size: 11)).foregroundStyle(secondary)
            }
            let steps = s.isActive || s.lastMessage == nil ? Array(s.steps.suffix(3)) : []
            ForEach(Array(steps.enumerated()), id: \.element.id) { i, step in
                HStack(spacing: 9) {
                    ZStack {
                        // fil de la timeline
                        Rectangle().fill(.white.opacity(0.12)).frame(width: 1)
                            .padding(.top, i == 0 ? 10 : 0).padding(.bottom, i == steps.count - 1 ? 10 : 0)
                        Circle().fill(.black).frame(width: 14, height: 14)
                        Image(systemName: step.done ? step.symbol : "circle.dotted")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(step.done ? secondary : s.tint)
                    }
                    .frame(width: 14, height: 18)
                    Text(step.label).font(.system(size: 11))
                        .foregroundStyle(.white.opacity(step.done ? 0.65 : 1)).lineLimit(1)
                    Spacer(minLength: 6)
                    if let d = step.duration {
                        Text(String(format: "%.1f s", d)).font(.system(size: 9.5).monospacedDigit()).foregroundStyle(secondary)
                    }
                }
                .help(step.file ?? step.label)
            }
        }
    }

    // MARK: Forfait

    @ViewBuilder private var usagePage: some View {
        if freshUsage.isEmpty {
            AgentEmptyState(symbol: "gauge.with.dots.needle.50percent",
                            message: "Aucune limite disponible : lancez une session Claude Code ou Codex.")
        } else {
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                HStack(alignment: .top, spacing: 8) {
                    ForEach(freshUsage, id: \.source) { UsageBlock(source: $0.source, limits: $0.limits) }
                }
            }
        }
    }
}

// MARK: - Carte d'activité

private struct ActivityCard: View {
    let session: AgentSession

    private var step: AgentStep? { session.steps.last }
    private var running: Bool { session.isActive && (step.map { !$0.done } ?? false) }
    private var tint: Color { session.tint }
    /// Au repos après une réponse de l'agent : la carte propose de reprendre la main.
    private var idleReply: Bool { !session.isActive && session.lastMessage != nil }
    private var diff: LineDiff? {
        guard step?.isEdit == true, let file = step?.file else { return nil }
        return session.diffs[file]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Image(systemName: idleReply ? (session.awaitsReply ? "bubble.left.fill" : "checkmark") : (step?.symbol ?? "folder.fill"))
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint.opacity(0.16)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1).truncationMode(.middle)
                    Text(status).font(.system(size: 10, weight: .medium))
                        .foregroundStyle(running ? tint : secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            if let detail {
                Text(detail).font(.system(size: 10, design: .monospaced)).foregroundStyle(secondary)
                    .lineLimit(2).truncationMode(.middle)
                    .help(detail)
            }
            Spacer(minLength: 0)
            if idleReply {
                pillButton(session.awaitsReply ? "Répondre" : "Ouvrir", tint: session.awaitsReply ? .effectiveAccent : nil) {
                    AgentStore.shared.openTerminal(session)
                }
            } else if running || diff != nil {
                HStack(spacing: 8) {
                    if running { ProgressLine(running: true, color: tint) }
                    if let diff {
                        Text("+\(diff.added)").foregroundStyle(.green)
                        Text("−\(diff.removed)").foregroundStyle(.red)
                    }
                }
                .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
            }
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .agentSurface()
    }

    private var title: String {
        if idleReply { return session.awaitsReply ? "Votre tour" : "Terminé" }
        if let f = step?.file { return (f as NSString).lastPathComponent }
        return step?.kind ?? session.project
    }

    private var status: String {
        if idleReply { return session.awaitsReply ? "\(session.source.capitalized) attend votre réponse" : "Prêt pour un prompt" }
        guard let step else { return session.stateText }
        if let d = step.duration { return String(format: "Terminé · %.1f s", d) }
        if !running { return session.stateText }
        return step.isEdit ? "Écriture…" : "En cours…"
    }

    private var detail: String? {
        if idleReply { return nil }
        guard let step, step.file == nil else { return nil }
        return step.label
    }
}

// MARK: - Question (AskUserQuestion) et plan (ExitPlanMode)

/// Même action capsule que les contrôles de navigation.
private func pillButton(_ label: String, tint: Color?, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(label).lineLimit(1)
    }
    .buttonStyle(AgentActionStyle(tint: tint))
}

/// Questions une par une ; un clic sur une option répond (choix unique) ou la coche (choix multiple).
/// Pas de champ libre (le notch ne prend pas le clavier) : « Autre… » ramène au terminal, où la question est aussi posée.
private struct QuestionCard: View {
    let session: AgentSession
    let questions: [AgentQuestion]
    @State private var index = 0
    @State private var answers: [String: String] = [:]
    @State private var checked: Set<String> = []
    @State private var hovered: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var q: AgentQuestion { questions[min(index, questions.count - 1)] }
    private var multi: Bool { q.multiSelect == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.bubble")
                    .font(.system(size: 12)).foregroundStyle(Color.effectiveAccent)
                Text(q.question).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .help(q.question)
            HStack(alignment: .top, spacing: 6) {
                ForEach(q.options, id: \.label) { option($0) }
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: 6) {
                Text(session.project).lineLimit(1).truncationMode(.middle)
                if let header = q.header, !header.isEmpty {
                    Text("·")
                    Text(header).lineLimit(1)
                }
                if questions.count > 1 {
                    Text("\(index + 1)/\(questions.count)").monospacedDigit()
                }
                Spacer(minLength: 4)
                pillButton("Autre…", tint: nil) { AgentStore.shared.openTerminal(session) }
                if multi {
                    pillButton("Valider", tint: .effectiveAccent) { record(checked.sorted().joined(separator: ", ")) }
                        .disabled(checked.isEmpty)
                }
            }
            .font(.system(size: 10, weight: .medium)).foregroundStyle(secondary)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func option(_ o: AgentQuestion.Option) -> some View {
        let on = checked.contains(o.label)
        return Button {
            if multi { if on { checked.remove(o.label) } else { checked.insert(o.label) } } else { record(o.label) }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if multi {
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 10))
                            .foregroundStyle(on ? Color.effectiveAccent : secondary)
                    }
                    Text(o.label).font(.system(size: 11, weight: .semibold)).lineLimit(2)
                }
                if let d = o.description {
                    Text(d).font(.system(size: 10)).foregroundStyle(secondary).lineLimit(2)
                }
            }
            .foregroundStyle(.white)
            .multilineTextAlignment(.leading)
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .agentSurface(selected: on || hovered == o.label)
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? o.label : nil }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovered)
        .help([o.label, o.description].compactMap { $0 }.joined(separator: "\n"))
        .accessibilityLabel(o.label)
        .accessibilityValue(multi ? (on ? "Sélectionné" : "Non sélectionné") : "")
        .accessibilityHint(o.description ?? "")
    }

    private func record(_ value: String) {
        answers[q.question] = value
        checked = []
        if index + 1 < questions.count { index += 1 } else { AgentStore.shared.answer(session.id, answers) }
    }
}

/// Demande d'autorisation : phrase française en grand, détails en dessous, décision en pied, pleine largeur.
private struct PermissionCard: View {
    let session: AgentSession
    let ask: PermissionAsk

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(session.tint)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(session.tint.opacity(0.16)))
                Text("Validation requise").font(.system(size: 11, weight: .semibold)).foregroundStyle(session.tint)
                Text("· \(session.project)").font(.system(size: 11, weight: .medium)).foregroundStyle(secondary).lineLimit(1)
                Spacer(minLength: 0)
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(ask.question).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(ask.details, id: \.self) {
                        Text($0).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.white.opacity(0.8))
                            .lineLimit(4).truncationMode(.middle).textSelection(.enabled)
                    }
                    Text(ask.tool).font(.system(size: 9, design: .monospaced)).foregroundStyle(secondary.opacity(0.7))
                        .lineLimit(1).truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            if session.canAnswer {
                HStack(spacing: 8) {
                    decision("Refuser", tint: nil) { AgentStore.shared.decide(session.id, allow: false) }
                    decision("Autoriser", tint: .effectiveAccent) { AgentStore.shared.decide(session.id, allow: true) }
                }
            } else {
                // Hook non bloquant : le notch ne peut pas répondre, la validation se fait dans le terminal.
                pillButton(session.openLabel, tint: nil) { AgentStore.shared.openTerminal(session) }
            }
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .agentSurface()
    }

    private func decision(_ label: String, tint: Color?, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(label).frame(maxWidth: .infinity, minHeight: 20) }
            .buttonStyle(AgentActionStyle(tint: tint))
    }
}

/// Plan Markdown défilant à gauche, décision à droite. Retoucher le plan = au terminal (saisie clavier).
private struct PlanCard: View {
    let session: AgentSession
    let plan: String

    private var text: AttributedString {
        (try? AttributedString(markdown: plan, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(plan)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ScrollView(.vertical) {
                Text(text).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    .padding(10)
            }
            .frame(maxWidth: .infinity)
            .agentSurface()
            VStack(alignment: .trailing, spacing: 6) {
                Text("Plan à valider").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                Text(session.project).font(.system(size: 10, weight: .medium)).foregroundStyle(secondary).lineLimit(1)
                Spacer(minLength: 0)
                pillButton("Retoucher…", tint: nil) { AgentStore.shared.openTerminal(session) }
                pillButton("Approuver", tint: .effectiveAccent) { AgentStore.shared.decide(session.id, allow: true) }
            }
            .frame(width: 122)
        }
        .frame(maxHeight: .infinity)
    }
}

/// Trait fin : segment qui glisse tant que l'étape tourne, plein sinon.
private struct ProgressLine: View {
    let running: Bool
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                if running && !reduceMotion {
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { t in
                        let phase = t.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                        Capsule().fill(color)
                            .frame(width: g.size.width * 0.3)
                            .offset(x: (g.size.width * 0.7) * phase)
                    }
                } else {
                    Capsule().fill(color)
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

// MARK: - Limites d'usage

private struct UsageBlock: View {
    let source: String
    let limits: UsageLimits

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: agentIcon(source)).font(.system(size: 11))
                Text(source.capitalized).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(accent(source))
            if let w = limits.fiveHour { UsageLine(title: "5 h", limit: w) }
            if let w = limits.sevenDay { UsageLine(title: "7 j", limit: w) }
            Spacer(minLength: 0)
            // Les sessions lancées hors terminal (SDK, T3 Code) n'envoient pas de status line : on dit l'âge de la mesure.
            if Date().timeIntervalSince(limits.updatedAt) > 15 * 60 {
                Text("Mesuré \(limits.updatedAt.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 10))
                    .foregroundStyle(secondary)
                    .help("Mis à jour par la status line de Claude Code dans un terminal")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .agentSurface()
    }
}

/// « 5 h ▬▬▬▬ 4 % 2 h 10 » sur une seule ligne.
private struct UsageLine: View {
    let title: String
    let limit: RateLimit

    private var color: Color { limit.usedPercent >= 90 ? .red : limit.usedPercent >= 70 ? .orange : .green }

    var body: some View {
        HStack(spacing: 8) {
            Text(title).frame(width: 18, alignment: .leading).foregroundStyle(secondary)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule().fill(color).frame(width: g.size.width * min(max(limit.usedPercent, 0), 100) / 100)
                }
            }
            .frame(height: 4)
            Text("\(Int(limit.usedPercent.rounded())) %").monospacedDigit().frame(width: 34, alignment: .trailing)
            Text(limit.resetsAt.map(Self.remaining) ?? "").frame(width: 44, alignment: .trailing).foregroundStyle(secondary)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) : \(Int(limit.usedPercent.rounded())) pour cent utilisés")
        .accessibilityValue(limit.resetsAt.map { "Réinitialisation dans \(Self.remaining($0))" } ?? "")
        .help(limit.resetsAt.map { "Réinitialisation : \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "")
    }

    static func remaining(_ date: Date) -> String {
        let m = max(0, Int(date.timeIntervalSinceNow / 60))
        if m >= 2880 { return "\(m / 1440) j" }
        if m >= 60 { return "\(m / 60) h \(String(format: "%02d", m % 60))" }
        return "\(m) min"
    }
}

// MARK: - Mascotte, point d'état et island

/// Petite mascotte en pixel art (clin d'œil à NotchNook).
private struct Mascot: View {
    let color: Color
    private static let rows = [".#.....#.", "#########", "##.###.##", "#########", ".#.#.#.#.", "#.#...#.#"]

    var body: some View {
        Canvas { ctx, _ in
            for (y, row) in Self.rows.enumerated() {
                for (x, c) in row.enumerated() where c == "#" {
                    ctx.fill(Path(CGRect(x: CGFloat(x) * 2.5, y: CGFloat(y) * 2.5, width: 2.5, height: 2.5)), with: .color(color))
                }
            }
        }
        .frame(width: 22.5, height: 15)
    }
}

/// Point d'état ; pulse tant que l'agent travaille.
struct StateDot: View {
    let state: AgentState
    @State private var pulse = false

    private var animated: Bool { state != .done }

    var body: some View {
        Circle().fill(state.color)
            .frame(width: 7, height: 7)
            .opacity(animated && pulse ? 0.35 : 1)
            .animation(animated ? .easeInOut(duration: 0.8).repeatForever() : .default, value: pulse)
            .onAppear { pulse = true }
    }
}

/// Bulle détachée à côté du notch (à la Droppy) : la mascotte pixel de l'agent, sans texte.
/// - travail : mascotte orange qui « marche » (deux images de pattes en alternance)
/// - validation : mascotte rouge qui se agite + liseré rouge qui pulse
/// - réponse attendue : mascotte bleue qui sautille + « ? » (une conversation attend votre suite)
/// - repos : bulle réduite, mascotte verte atténuée et immobile
private struct AgentBubble: View {
    enum Kind { case working, attention, reply, idle }
    let kind: Kind
    var badge = false      // une autre conversation attend une réponse
    let height: CGFloat
    @State private var pulse = false
    @State private var attentionSince = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Default(.agentAttentionStyle) private var style
    /// Style effectif : `system` devient animé ou doux selon Réduire les animations.
    private var effective: AgentAttentionStyle { style == .system ? (reduceMotion ? .soft : .full) : style }

    private var tint: Color { kind == .attention ? .red : kind == .idle ? .green : kind == .reply ? .blue : .orange }
    private var diameter: CGFloat { max(height - 8, 18) * (kind == .idle ? 0.78 : 1) }

    var body: some View {
        // Attention : tout dérive de l'horloge, pas d'un @State — une bulle déjà affichée qui passe en
        // .attention s'anime donc forcément (l'ancien repeatForever ne repartait pas, `pulse` étant déjà vrai).
        TimelineView(.animation(paused: kind != .attention || effective == .off)) { t in
            let e = t.date.timeIntervalSince(attentionSince)
            let sonar = e.truncatingRemainder(dividingBy: 1.6) / 1.6             // onde : 0 → 1 toutes les 1,6 s
            let shake = e.truncatingRemainder(dividingBy: 3)                    // secousse 0,4 s toutes les 3 s
            let angle = shake < 0.4 ? sin(shake * .pi * 2 / 0.13) * 8 * (1 - shake / 0.4) : 0
            let pop = e < 0.45 ? 1 + 0.2 * sin(e / 0.45 * .pi) : 1                // petit rebond à l'arrivée
            // Doux : rien ne bouge, l'anneau et le halo « respirent » (fondu, pas de mouvement).
            let breathe = effective == .soft ? 0.5 + 0.5 * cos(e * .pi * 2 / 1.4) : 1
            let animate = kind == .attention && effective == .full
            ZStack {
                if animate {
                    Circle().stroke(tint, lineWidth: 1.5)
                        .scaleEffect(1 + 0.6 * sonar).opacity(0.8 * (1 - sonar))
                }
                Circle().fill(.black)
                if kind == .attention { Circle().stroke(tint.opacity(0.2 + 0.7 * breathe), lineWidth: 1.5) }
                PixelMascot(color: tint, walking: kind == .working)
                    .scaleEffect(kind == .idle ? 0.8 : 1)
                    .offset(y: kind == .reply && pulse ? -1.5 : 0)
                    .animation(kind == .reply ? .easeInOut(duration: 0.55).repeatForever() : .default, value: pulse)
                    .opacity(kind == .idle ? 0.6 : 1)
                    .rotationEffect(.degrees(animate ? angle : 0))
            }
            .scaleEffect(animate ? pop : 1)
            .shadow(color: kind == .attention ? tint.opacity(0.8 * breathe) : .clear, radius: 4 + 3 * breathe)
        }
        .frame(width: diameter, height: diameter)
        .overlay(alignment: .topTrailing) {
            if kind == .reply || badge {
                Text("?").font(.system(size: 7, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 11, height: 11).background(Circle().fill(Color.blue))
                    .overlay(Circle().stroke(.black, lineWidth: 1.5))
                    .offset(x: 3, y: 1).transition(.scale) // y ≥ 0 : le haut de la notch rogne tout ce qui dépasse
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
        .animation(.spring(response: 0.45, dampingFraction: 0.78), value: kind)
        .onAppear { pulse = true }
        .onChange(of: kind) { _, new in
            if new == .attention { attentionSince = .now }
            pulse = false                                       // relance le rebond .reply, même bug que l'attention
            DispatchQueue.main.async { pulse = true }
        }
    }
}

private struct PixelMascot: View {
    let color: Color
    let walking: Bool
    private static let body = [".#.....#.", "#########", "##.###.##", "#########"]
    private static let legsA = [".#.#.#.#.", "#.#...#.#"]
    private static let legsB = ["#.#.#.#.#", ".#.....#."]
    private let px: CGFloat = 2.1

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.32)) { t in
            let alt = walking && Int(t.date.timeIntervalSinceReferenceDate / 0.32) % 2 == 1
            let rows = Self.body + (alt ? Self.legsB : Self.legsA)
            Canvas { ctx, _ in
                for (y, row) in rows.enumerated() {
                    for (x, c) in row.enumerated() where c == "#" {
                        ctx.fill(Path(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: px, height: px)), with: .color(color))
                    }
                }
            }
            .frame(width: px * 9, height: px * 6)
        }
    }
}

/// Bulle des agents parmi les activités de la notch fermée.
/// Visible tant qu'une conversation est ouverte ; priorité : validation > travail > réponse attendue > repos.
extension AgentStore {
    func activity(now: Date, height: CGFloat, onTap: @escaping () -> Void) -> Activity? {
        let open = sessions.contains { now.timeIntervalSince($0.updatedAt) < 4 * 3600 }
        let kind: AgentBubble.Kind? = needsAttention ? .attention
            : activeCount > 0 ? .working : needsReply ? .reply : open ? .idle : nil
        guard let kind else { return nil }
        let priority = [.attention: 95, .working: 80, .reply: 70][kind] ?? 30
        return Activity(id: "agents", priority: priority, view: AnyView(
            Button(action: onTap) {
                AgentBubble(kind: kind, badge: needsReply, height: height).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Ouvrir l'onglet Agents")
        ))
    }
}
