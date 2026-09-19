//
//  SystemMonitorView.swift
//  boringNotch
//
//  The system monitor tab: a grid of metric cards inside the opened notch.
//
//  Sized to fit the existing 640x190 notch window rather than growing it —
//  every other surface in the app shares that window, and a feature that
//  resizes it would change the shelf and home layouts too.
//

import AppKit
import Defaults
import SwiftUI

struct SystemMonitorView: View {
    @ObservedObject private var monitor = SystemMonitorManager.shared
    @ObservedObject private var battery = BatteryStatusViewModel.shared
    @Default(.systemMonitorMetrics) private var enabledMetrics

    /// Three across, matching the reference layout. Fixed rather than
    /// adaptive: the notch width never changes, so an adaptive grid would
    /// only ever resolve to the same three columns while making the row
    /// height harder to reason about.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    private var visibleMetrics: [SystemMetricKind] {
        SystemMetricKind.displayOrder.filter { enabledMetrics.contains($0) }
    }

    var body: some View {
        Group {
            if visibleMetrics.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(visibleMetrics) { metric in
                        SystemMonitorCard(
                            kind: metric,
                            content: content(for: metric)
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { monitor.beginObserving() }
        .onDisappear { monitor.endObserving() }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 22))
                .foregroundStyle(SystemMonitorPalette.label)
            Text("No metrics selected")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
            Text("Choose which metrics to show in Settings › System Monitor.")
                .font(.system(size: 10))
                .foregroundStyle(SystemMonitorPalette.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func content(for metric: SystemMetricKind) -> SystemMetricCardContent {
        SystemMetricCardBuilder.content(
            for: metric,
            snapshot: monitor.snapshot,
            battery: batterySummary,
            coreCount: ProcessInfo.processInfo.processorCount
        )
    }

    /// Bridges the existing battery view model into the builder's plain
    /// value type. `timeToDischarge`/`timeToFullCharge` are minutes, and are
    /// 0 while macOS has no estimate.
    private var batterySummary: BatterySummary {
        BatterySummary(
            chargePercent: Double(battery.levelBattery),
            isCharging: battery.isCharging,
            isPluggedIn: battery.isPluggedIn,
            minutesRemaining: battery.isCharging ? battery.timeToFullCharge : battery.timeToDischarge,
            health: monitor.snapshot.batteryHealth
        )
    }
}

// MARK: - Card

/// One metric: ring gauge, label, value and a one-line detail.
///
/// The whole card is the button. The reference design puts a separate action
/// button at the foot of each card, which needs roughly 30pt more height per
/// row than the notch has — folding the action into the card keeps the
/// affordance without a scroll view or a taller window.
struct SystemMonitorCard: View {
    let kind: SystemMetricKind
    let content: SystemMetricCardContent

    @State private var isHovering = false

    private var action: SystemMonitorAction { SystemMonitorAction.action(for: kind) }

    var body: some View {
        Button {
            action.perform()
        } label: {
            HStack(spacing: 8) {
                SystemMonitorRing(
                    fraction: content.fraction,
                    tint: kind.tint,
                    systemImage: kind.systemImage,
                    isIndeterminate: content.isIndeterminate
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.localizedTitle.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .kerning(0.6)
                        .foregroundStyle(SystemMonitorPalette.label)
                        .lineLimit(1)

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(content.value)
                            .font(.system(size: 19, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        if let unit = content.unit {
                            Text(unit)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(SystemMonitorPalette.secondary)
                                .lineLimit(1)
                        }
                    }

                    Text(content.subtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(SystemMonitorPalette.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(SystemMonitorPalette.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isHovering ? kind.tint.opacity(0.45) : SystemMonitorPalette.cardBorder, lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(isHovering ? kind.tint : SystemMonitorPalette.label.opacity(0.5))
                    .padding(6)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
        .help(action.localizedTitle)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityHint(Text(action.localizedTitle))
        .accessibilityAddTraits(.isButton)
    }

    /// VoiceOver reads the card as one sentence. The raw `value`/`unit` split
    /// exists for typography; spoken, it should just be "CPU, 49.0 %, 8 cores".
    private var accessibilityLabel: String {
        let value = content.isIndeterminate
            ? NSLocalizedString("system_metric_no_reading", comment: "Accessibility value when a metric has no reading yet")
            : [content.value, content.unit].compactMap { $0 }.joined(separator: " ")
        return [kind.localizedTitle, value, content.subtitle]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

// MARK: - Card actions

/// What clicking a card does.
///
/// Every action here is something a sandboxed app can genuinely do — open
/// another app, or open a System Settings pane or URL. Deliberately *not*
/// offered: "Free RAM", "Empty Trash" and toggling Low Power Mode, all of
/// which need privileges this app does not and should not have.
struct SystemMonitorAction {
    let localizedTitle: String
    let systemImage: String
    private let handler: @MainActor () -> Void

    @MainActor
    func perform() { handler() }

    static func action(for kind: SystemMetricKind) -> SystemMonitorAction {
        switch kind {
        case .cpu, .memory:
            return SystemMonitorAction(
                localizedTitle: NSLocalizedString("system_monitor_open_activity_monitor", comment: "Card action: open Activity Monitor"),
                systemImage: "chart.bar.xaxis",
                handler: { openApplication(bundleID: "com.apple.ActivityMonitor") }
            )
        case .battery:
            return SystemMonitorAction(
                localizedTitle: NSLocalizedString("system_monitor_open_battery_settings", comment: "Card action: open Battery settings"),
                systemImage: "arrow.up.forward.app",
                handler: { openSettings("com.apple.Battery-Settings.extension") }
            )
        case .disk:
            return SystemMonitorAction(
                localizedTitle: NSLocalizedString("system_monitor_open_storage_settings", comment: "Card action: open Storage settings"),
                systemImage: "arrow.up.forward.app",
                handler: { openSettings("com.apple.settings.Storage") }
            )
        case .network:
            return SystemMonitorAction(
                localizedTitle: NSLocalizedString("system_monitor_speed_test", comment: "Card action: run an internet speed test"),
                systemImage: "speedometer",
                handler: {
                    if let url = URL(string: "https://fast.com") {
                        NSWorkspace.shared.open(url)
                    }
                }
            )
        case .wifi:
            return SystemMonitorAction(
                localizedTitle: NSLocalizedString("system_monitor_open_wifi_settings", comment: "Card action: open Wi-Fi settings"),
                systemImage: "arrow.up.forward.app",
                handler: { openSettings("com.apple.wifi-settings-extension") }
            )
        }
    }

    @MainActor
    private static func openApplication(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            Log.general.error("System monitor: no application for bundle ID \(bundleID)")
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// System Settings pane IDs changed with Ventura's rewrite. If the modern
    /// identifier doesn't resolve, fall back to opening Settings itself
    /// rather than silently doing nothing.
    @MainActor
    private static func openSettings(_ paneID: String) {
        if let url = URL(string: "x-apple.systempreferences:\(paneID)"), NSWorkspace.shared.open(url) {
            return
        }
        openApplication(bundleID: "com.apple.systempreferences")
    }
}
