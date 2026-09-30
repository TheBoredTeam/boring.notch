//
//  AgentLiveActivity.swift
//  boringCode
//
//  Conteúdo do notch fechado quando há agente rodando e nenhuma música:
//  mesma geometria do NotificationLiveActivity (ícone | notch | indicador).
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
            leading
                .frame(width: itemSize, height: itemSize)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)

            AgentClosedIndicator(status: status, size: itemSize)
        }
        .frame(height: vm.effectiveClosedNotchHeight)
    }

    /// Lado esquerdo: quantas sessões estão ativas (ou o ícone do terminal, se só uma).
    @ViewBuilder
    private var leading: some View {
        let count = store.activeSessions.count
        if count > 1 {
            Text("\(count)")
                .font(.system(size: itemSize * 0.62, weight: .semibold, design: .rounded))
                .foregroundStyle(.gray)
                .contentTransition(.numericText())
        } else {
            Image(systemName: "apple.terminal.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.gray)
                .padding(itemSize * 0.12)
        }
    }
}

/// O indicador do lado direito do notch fechado. Passar o mouse sobre ele
/// faz o notch abrir direto na aba de agentes.
struct AgentClosedIndicator: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var coordinator = BoringViewCoordinator.shared
    let status: AgentSessionStatus
    let size: CGFloat

    @State private var viewBeforeHover: NotchViews?

    var body: some View {
        AgentStatusIndicator(status: status, size: max(0, size * 0.8))
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .animation(.smooth(duration: 0.25), value: status)
            .onHover { hovering in
                guard Defaults[.agentsHoverOpensTab], vm.notchState == .closed else { return }
                if hovering {
                    if coordinator.currentView != .agents { viewBeforeHover = coordinator.currentView }
                    coordinator.currentView = .agents
                } else if let previous = viewBeforeHover {
                    // Saiu do indicador sem abrir o notch: volta a aba de antes.
                    coordinator.currentView = previous
                    viewBeforeHover = nil
                }
            }
            .onChange(of: vm.notchState) { _, state in
                if state == .open { viewBeforeHover = nil }
            }
    }
}
