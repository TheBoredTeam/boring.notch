//
//  FocusModule.swift
//  boringNotch
//
//  Onglet « Focus » : trois tuiles (minuteur, Pomodoro, rester éveillé) au même gabarit
//  que les cartes Agents : en-tête, valeur principale + bouton rond, réglages en bas.
//

import Defaults
import SwiftUI

struct FocusModule: NotchModule {
    let id = "focus"
    let label = "Focus"
    let icon = "timer"

    func start() {}

    @MainActor func makeView() -> AnyView { AnyView(FocusView()) }
}

private let dim = Color.white.opacity(0.6)

private struct FocusView: View {
    @ObservedObject private var quick = QuickActions.shared
    @State private var gate = ConfirmGate(window: 3)

    var body: some View {
        // Une seconde de résolution pour les temps restants.
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            HStack(spacing: 8) {
                TimerTile(now: ctx.date).frame(maxWidth: .infinity)
                PomodoroTile(now: ctx.date).frame(width: 154)
                AwakeTile(now: ctx.date).frame(width: 154)
                quickColumn(now: ctx.date)
            }
        }
        .onAppear { quick.refresh() }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Colonne étroite : éjecter les disques externes, vider la corbeille (second clic dans les 3 s).
    private func quickColumn(now: Date) -> some View {
        let armed = gate.isArmed(at: now)
        let failed = quick.failure != nil
        let ejectTip = quick.failure.flatMap { $0.hasPrefix("Impossible d'éjecter") ? $0 : nil }
            ?? (quick.ejectable.isEmpty ? "Aucun disque à éjecter" : "Éjecter les disques externes")
        let trashTip = armed ? "Cliquer à nouveau pour vider la corbeille"
            : quick.failure.flatMap { $0.hasPrefix("Impossible d'éjecter") ? nil : $0 } ?? "Vider la corbeille"
        return VStack(spacing: 8) {
            QuickButton(symbol: "eject", badge: quick.ejectable.count, tint: failed && ejectTip == quick.failure ? .red : nil,
                        help: ejectTip, enabled: !quick.ejectable.isEmpty) { quick.ejectAll() }
            QuickButton(symbol: "trash", label: armed ? "Confirmer ?" : nil,
                        tint: armed || (failed && trashTip == quick.failure) ? .red : nil,
                        help: trashTip, enabled: quick.trashHasItems) {
                if gate.press(at: Date()) { quick.emptyTrash() }
            }
        }
        .frame(width: 44)
    }
}

// MARK: - Minuteur

private struct TimerTile: View {
    let now: Date
    @ObservedObject private var timer = NotchTimer.shared
    @State private var minutes = Double(Defaults[.timerShortcutMinutes])

    private var chosen: Binding<Int> {
        Binding { Int(minutes.rounded()) } set: { minutes = Double($0) }
    }

    var body: some View {
        // Le Pomodoro partage le moteur du minuteur : ici, seul le minuteur simple compte comme « en cours ».
        let end = timer.phase == nil ? timer.end : nil
        FocusTile(title: "Minuteur", icon: "timer", tint: end == nil ? nil : .orange) {
            if end == nil, timer.finishedAt != nil {
                Text("Terminé").foregroundStyle(.orange)
            }
        } hero: {
            if let end {
                BigValue(activityDuration(end.timeIntervalSince(now).rounded(.up)))
                Spacer(minLength: 6)
                RoundButton(symbol: "stop.fill", help: "Arrêter le minuteur") { timer.stop() }
            } else {
                BigValue("\(chosen.wrappedValue)", unit: "min")
                Spacer(minLength: 6)
                RoundButton(symbol: "play.fill", tint: .effectiveAccent,
                            help: timer.phase == nil ? "Lancer le minuteur" : "Lancer le minuteur (arrête le Pomodoro)") {
                    timer.start(minutes: chosen.wrappedValue)
                }
            }
        } controls: {
            if let end {
                Elapsed(remaining: end.timeIntervalSince(now), total: timer.duration, tint: .orange)
                Text("Fin à \(end.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(dim)
            } else {
                Slider(value: $minutes, in: 1...120)
                    .controlSize(.mini)
                    .tint(.effectiveAccent)
                    .accessibilityLabel("Durée du minuteur")
                    .accessibilityValue("\(chosen.wrappedValue) minutes")
                Segments(values: NotchTimer.presets, selection: chosen, label: { "\($0)" }, a11y: { "\($0) minutes" })
            }
        }
    }
}

// MARK: - Pomodoro

private struct PomodoroTile: View {
    let now: Date
    @ObservedObject private var timer = NotchTimer.shared
    @Default(.pomodoroFocusMinutes) private var focus
    @Default(.pomodoroShortMinutes) private var short
    @Default(.pomodoroLongMinutes) private var long
    @Default(.pomodoroLongEvery) private var every

    /// Classiques focus / pause courte ; un réglage personnalisé (Réglages → Activités) ne sélectionne aucun segment.
    static let presets = [(focus: 25, pause: 5), (focus: 50, pause: 10), (focus: 90, pause: 20)]
    static func pause(_ focus: Int) -> Int { presets.first { $0.focus == focus }?.pause ?? 5 }

    private var preset: Binding<Int> {
        Binding { short == Self.pause(focus) ? focus : -1 } set: { f in
            focus = f
            short = Self.pause(f)
        }
    }

    var body: some View {
        let phase = timer.phase
        let tint: Color? = switch phase {
        case .focus: .orange
        case .shortBreak, .longBreak: .green
        case nil: nil
        }
        FocusTile(title: "Pomodoro", icon: "brain.head.profile", tint: tint) {
            Rounds(phase: phase, total: every, tint: tint ?? dim)
        } hero: {
            if let end = timer.end, phase != nil {
                BigValue(activityDuration(end.timeIntervalSince(now).rounded(.up)))
                Spacer(minLength: 6)
                RoundButton(symbol: "stop.fill", help: "Arrêter le Pomodoro") { timer.stop() }
            } else {
                BigValue("\(focus)", unit: "min")
                Spacer(minLength: 6)
                RoundButton(symbol: "play.fill", tint: .effectiveAccent,
                            help: timer.isOn ? "Démarrer le Pomodoro (arrête le minuteur)" : "Démarrer le Pomodoro") {
                    timer.startPomodoro()
                }
            }
        } controls: {
            if let end = timer.end, let phase, let tint {
                Elapsed(remaining: end.timeIntervalSince(now), total: timer.duration, tint: tint)
                HStack(spacing: 6) {
                    Text(phaseName(phase)).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(tint)
                    Spacer(minLength: 4)
                    Button("Passer") { timer.skip() }
                        .buttonStyle(AgentActionStyle())
                        .help("Passer à la phase suivante")
                }
            } else {
                Text("Pause \(short) · longue \(long) min")
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(dim)
                    .lineLimit(1)
                    .help("Pause longue après \(every) focus. Durées détaillées : Réglages → Activités → Pomodoro")
                Segments(values: Self.presets.map(\.focus), selection: preset,
                         label: { f in "\(f)/\(Self.pause(f))" },
                         a11y: { f in "\(f) minutes de focus, \(Self.pause(f)) de pause" })
            }
        }
    }

    private func phaseName(_ p: FocusPhase) -> String {
        switch p {
        case .focus: "Focus"
        case .shortBreak: "Pause"
        case .longBreak: "Pause longue"
        }
    }
}

/// Un point par focus du cycle : passés atténués, en cours dans la teinte de la phase.
private struct Rounds: View {
    let phase: FocusPhase?
    let total: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...max(total, 1), id: \.self) { i in
                Circle()
                    .fill(fill(i))
                    .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1).opacity(fill(i) == .clear ? 1 : 0))
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(label)
    }

    private func fill(_ i: Int) -> Color {
        switch phase {
        case .focus(let r): i < r ? .white.opacity(0.5) : i == r ? tint : .clear
        case .shortBreak(let r): i <= r ? .white.opacity(0.5) : .clear
        case .longBreak: .white.opacity(0.5)
        case nil: .clear
        }
    }

    private var label: String {
        switch phase {
        case .focus(let r): "Focus \(r) sur \(total)"
        case .shortBreak(let r): "Pause après le focus \(r) sur \(total)"
        case .longBreak: "Pause longue"
        case nil: "Cycle de \(total) focus"
        }
    }
}

// MARK: - Rester éveillé

private struct AwakeTile: View {
    let now: Date
    @ObservedObject private var awake = StayAwake.shared
    @Default(.stayAwakeDisplay) private var display
    @State private var minutes = Defaults[.stayAwakeShortcutMinutes]   // 0 = indéfiniment

    var body: some View {
        FocusTile(title: "Rester éveillé", icon: "cup.and.saucer", tint: awake.isOn ? .orange : nil) {
            EmptyView()
        } hero: {
            if let until = awake.until {
                if until == .distantFuture {
                    BigValue("∞").accessibilityLabel("Indéfiniment")
                } else {
                    BigValue(remaining(until.timeIntervalSince(now)))
                }
                Spacer(minLength: 6)
                RoundButton(symbol: "stop.fill", help: "Laisser le Mac se mettre en veille") { awake.stop() }
            } else {
                if minutes == 0 {
                    BigValue("∞").accessibilityLabel("Indéfiniment")
                } else {
                    BigValue("\(minutes / 60)", unit: "h")
                }
                Spacer(minLength: 6)
                RoundButton(symbol: "play.fill", tint: .effectiveAccent, help: "Empêcher la mise en veille") {
                    awake.start(for: minutes > 0 ? TimeInterval(minutes * 60) : nil)
                }
            }
        } controls: {
            if let until = awake.until {
                Text(until == .distantFuture ? "Jusqu'à l'arrêt" : "Jusqu'à \(until.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 10.5))
                    .foregroundStyle(dim)
                Text(display ? "Le Mac et l'écran restent allumés" : "L'écran peut s'éteindre")
                    .font(.system(size: 10.5))
                    .foregroundStyle(dim)
                    .lineLimit(1)
            } else {
                Segments(values: [60, 120, 240, 0], selection: $minutes,
                         label: { $0 == 0 ? "∞" : "\($0 / 60) h" },
                         a11y: { $0 == 0 ? "Indéfiniment" : "\($0 / 60) heures" })
                Toggle("Écran allumé", isOn: $display)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 10.5))
                    .foregroundStyle(dim)
            }
        }
    }

    /// Le temps restant à la minute près : rester éveillé n'est pas un compte à rebours.
    private func remaining(_ t: TimeInterval) -> String {
        let m = max(0, Int((t / 60).rounded(.up)))
        return m >= 60 ? "\(m / 60) h \(String(format: "%02d", m % 60))" : "\(m) min"
    }
}

// MARK: - Briques

/// Gabarit commun des tuiles : en-tête, valeur + action, réglages calés en bas.
private struct FocusTile<Accessory: View, Hero: View, Controls: View>: View {
    let title: String
    let icon: String
    let tint: Color?
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var hero: Hero
    @ViewBuilder var controls: Controls

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Label(title, systemImage: icon)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(tint ?? dim)
                    .lineLimit(1)
                Spacer(minLength: 4)
                accessory
                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(dim)
            }
            .frame(height: 14)
            HStack(alignment: .center, spacing: 0) { hero }
                .padding(.top, 6)
            Spacer(minLength: 6)
            VStack(alignment: .leading, spacing: 7) { controls }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .agentSurface(selected: tint != nil, tint: tint ?? .effectiveAccent)
        .animation(.smooth(duration: 0.25), value: tint)
    }
}

private struct BigValue: View {
    let value: String
    var unit: String?

    init(_ value: String, unit: String? = nil) {
        self.value = value
        self.unit = unit
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.system(size: 26, weight: .medium).monospacedDigit())
                .tracking(-0.5)
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            if let unit {
                Text(unit).font(.system(size: 12, weight: .medium)).foregroundStyle(dim)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .combine)
    }
}

/// Bouton rond de la tuile : lecture (teinte d'accent) au repos, arrêt pendant l'activité.
private struct RoundButton: View {
    let symbol: String
    var tint: Color?
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint ?? .white.opacity(0.9))
                .frame(width: 28, height: 28)
                .background((tint ?? .white).opacity(hovering ? 0.28 : 0.16), in: Circle())
                .overlay(Circle().strokeBorder((tint ?? .white).opacity(hovering ? 0.5 : 0.14)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Bouton carré de la colonne d'actions rapides, même surface que les tuiles.
private struct QuickButton: View {
    let symbol: String
    var badge = 0
    var label: String?
    var tint: Color?
    let help: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                if let label {
                    Text(label).font(.system(size: 8.5, weight: .semibold)).lineLimit(2).minimumScaleFactor(0.8)
                        .multilineTextAlignment(.center)
                }
            }
            .foregroundStyle(tint ?? .white.opacity(0.9))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                if badge > 0 {
                    Text("\(badge)").font(.system(size: 9, weight: .bold).monospacedDigit()).foregroundStyle(dim)
                        .padding(.top, 5).padding(.trailing, 6)
                }
            }
            .agentSurface(selected: tint != nil, tint: tint ?? .effectiveAccent)
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .animation(.smooth(duration: 0.25), value: tint)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Choix exclusif compact, même pastille de sélection que la barre d'onglets.
private struct Segments<V: Hashable>: View {
    let values: [V]
    @Binding var selection: V
    let label: (V) -> String
    let a11y: (V) -> String
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(values, id: \.self) { v in
                let on = v == selection
                Button {
                    withAnimation(.smooth(duration: 0.2)) { selection = v }
                } label: {
                    Text(label(v))
                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(on ? .white : dim)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, minHeight: 20)
                        .background {
                            if on {
                                Capsule().fill(.white.opacity(0.16)).matchedGeometryEffect(id: "selection", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(a11y(v))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(.white.opacity(0.065), in: Capsule())
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Barre du temps écoulé dans la teinte de l'activité.
private struct Elapsed: View {
    let remaining: TimeInterval
    let total: TimeInterval
    let tint: Color

    var body: some View {
        let done = total > 0 ? min(max(1 - remaining / total, 0), 1) : 0
        GeometryReader { geo in
            Capsule().fill(.white.opacity(0.1))
                .overlay(alignment: .leading) {
                    Capsule().fill(tint).frame(width: max(geo.size.width * done, 4))
                }
        }
        .frame(height: 4)
        .animation(.linear(duration: 1), value: done)
        .accessibilityElement()
        .accessibilityLabel("Temps écoulé")
        .accessibilityValue("\(Int(done * 100)) %")
    }
}

