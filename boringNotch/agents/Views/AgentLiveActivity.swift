//
//  AgentLiveActivity.swift
//  boringCode
//
//  Notch fechado quando há agente e nenhuma música: informação dos dois lados,
//  no padrão do Open Island (github.com/Octane0411/open-vibe-island, GPL-3.0) —
//  status geral à esquerda, um quadradinho por sessão à direita — com a
//  geometria do NotificationLiveActivity do Boring Notch.
//

import Defaults
import SwiftUI

struct AgentLiveActivity: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var store = AgentSessionStore.shared
    let status: AgentSessionStatus

    private var itemSize: CGFloat {
        max(0, vm.effectiveClosedNotchHeight - 12)
    }

    var body: some View {
        HStack {
            AgentStatusIndicator(status: status, size: itemSize * 0.8)
                .frame(width: itemSize, height: itemSize)
                .opensAgentsTabOnHover()

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)

            AgentSessionCells(sessions: store.sessions, size: itemSize)
                .frame(width: itemSize, height: itemSize)
                .opensAgentsTabOnHover()
        }
        .frame(height: vm.effectiveClosedNotchHeight)
        .animation(.smooth(duration: 0.25), value: status)
    }
}

/// Lado direito do notch fechado com música tocando: entra no lugar do mini espectro.
struct AgentClosedIndicator: View {
    let status: AgentSessionStatus
    let size: CGFloat

    var body: some View {
        AgentStatusIndicator(status: status, size: max(0, size * 0.8))
            .frame(width: size, height: size)
            .animation(.smooth(duration: 0.25), value: status)
            .opensAgentsTabOnHover()
    }
}

/// Um quadradinho por sessão, colorido pelo status (grade balanceada, até 9; depois "+N").
struct AgentSessionCells: View {
    let sessions: [AgentSession]
    let size: CGFloat

    @State private var pulse = false

    private var rows: [[AgentSession?]] {
        let visible = sessions.count > 9 ? Array(sessions.prefix(8)) : sessions
        var cells: [AgentSession?] = visible
        if sessions.count > 9 { cells.append(nil) } // célula "+N"
        let rowCount = cells.count <= 3 ? 1 : (cells.count <= 6 ? 2 : 3)
        let perRow = Int((Double(cells.count) / Double(rowCount)).rounded(.up))
        return stride(from: 0, to: cells.count, by: max(perRow, 1)).map {
            Array(cells[$0..<min($0 + perRow, cells.count)])
        }
    }

    private var cellSize: CGFloat { rows.count >= 3 ? size * 0.28 : size * 0.38 }
    private var gap: CGFloat { rows.count >= 3 ? 1.5 : 2 }

    var body: some View {
        VStack(spacing: gap) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach(rows[row].indices, id: \.self) { column in
                        cell(rows[row][column])
                    }
                }
            }
        }
        .onAppear { pulse = true }
        .accessibilityElement()
        .accessibilityLabel(Text("\(sessions.count) agent sessions"))
    }

    @ViewBuilder
    private func cell(_ session: AgentSession?) -> some View {
        let shape = RoundedRectangle(cornerRadius: rows.count >= 3 ? 1 : 1.5, style: .continuous)
        if let session {
            let waiting = session.needsAnswer || session.status == .waitingInput
            shape
                .fill(session.status.cellTint)
                .frame(width: cellSize, height: cellSize)
                .opacity(waiting ? (pulse ? 1 : 0.35) : 1)
                .animation(waiting ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true) : .default, value: pulse)
        } else {
            shape
                .fill(Color.white.opacity(0.14))
                .frame(width: cellSize, height: cellSize)
        }
    }
}

private extension AgentSessionStatus {
    var cellTint: Color {
        switch self {
        case .idle: Color.white.opacity(0.22)
        default: tint
        }
    }
}

/// Passar o mouse aqui faz o notch abrir direto na aba Agentes.
/// Fora dessas áreas, o hover segue o comportamento normal do Boring Notch.
private struct OpensAgentsTabOnHover: ViewModifier {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var coordinator = BoringViewCoordinator.shared
    @State private var viewBeforeHover: NotchViews?

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onHover { hovering in
                guard Defaults[.agentsHoverOpensTab], vm.notchState == .closed else { return }
                if hovering {
                    if coordinator.currentView != .agents { viewBeforeHover = coordinator.currentView }
                    coordinator.currentView = .agents
                } else if let previous = viewBeforeHover {
                    // Saiu sem abrir o notch: volta a aba de antes.
                    coordinator.currentView = previous
                    viewBeforeHover = nil
                }
            }
            .onChange(of: vm.notchState) { _, state in
                if state == .open { viewBeforeHover = nil }
            }
    }
}

extension View {
    func opensAgentsTabOnHover() -> some View { modifier(OpensAgentsTabOnHover()) }
}
