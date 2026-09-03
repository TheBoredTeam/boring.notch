//
//  DeepseekBalanceView.swift
//  boringNotch
//
//  Created on 2026-06-21.
//

import Defaults
import SwiftUI

struct DeepseekBalanceView: View {
    @ObservedObject private var manager = DeepseekManager.shared
    @State private var showPopover: Bool = false
    @State private var isHoveringButton: Bool = false
    @State private var isHoveringPopover: Bool = false
    @State private var hideTask: Task<Void, Never>? = nil

    @EnvironmentObject var vm: BoringViewModel

    var body: some View {
        Button(action: {
            withAnimation {
                showPopover.toggle()
            }
            if showPopover {
                Task { await manager.fetchBalance() }
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)

                if let totalBalance = manager.balanceInfos.first?.totalBalance {
                    Text("¥\(totalBalance)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                } else if manager.isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                } else {
                    Text("--")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.gray)
                }
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .popover(
            isPresented: $showPopover,
            arrowEdge: .bottom
        ) {
            DeepseekPopoverView(manager: manager, onDismiss: {
                showPopover = false
            })
            .onHover { hovering in
                isHoveringPopover = hovering
                if hovering {
                    hideTask?.cancel()
                    hideTask = nil
                } else {
                    scheduleHideIfNeeded()
                }
            }
        }
        .onChange(of: showPopover) {
            vm.isDeepseekPopoverActive = showPopover
        }
        .onDisappear {
            hideTask?.cancel()
            hideTask = nil
        }
    }

    private func scheduleHideIfNeeded() {
        if isHoveringButton || isHoveringPopover { return }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await MainActor.run { withAnimation { showPopover = false } }
        }
    }
}

// MARK: - Popover Detail View

struct DeepseekPopoverView: View {
    @ObservedObject var manager: DeepseekManager
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Deepseek API")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                if manager.isAvailable {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.headline)
                } else {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.headline)
                }
            }

            if manager.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading…")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                    Spacer()
                }
            } else if let error = manager.errorMessage {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Error")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            } else if !manager.balanceInfos.isEmpty {
                ForEach(manager.balanceInfos) { info in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(info.currency) Balance")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("¥\(info.totalBalance)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }

                        HStack {
                            Text("Topped up")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("¥\(info.toppedUpBalance)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Granted")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("¥\(info.grantedBalance)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } else {
                Text("No balance data")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            }

            Divider().background(Color.white.opacity(0.2))

            Button(action: {
                Task { await manager.fetchBalance() }
            }) {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .fontWeight(.regular)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .disabled(manager.isLoading)
            .padding(.vertical, 4)
        }
        .padding()
        .frame(width: 260)
        .foregroundColor(.white)
    }
}

#Preview {
    DeepseekBalanceView()
        .environmentObject(BoringViewModel())
        .frame(width: 200, height: 200)
        .background(.black)
}
