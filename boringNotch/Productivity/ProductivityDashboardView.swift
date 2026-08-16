import AppKit
import Defaults
import EventKit
import SwiftUI

struct ProductivityDashboardView: View {
    @Default(.productivityWidgetOrder) private var widgetOrder
    @Default(.enabledProductivityWidgets) private var enabledWidgets

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 10) {
                ForEach(visibleWidgets) { widget in
                    widgetView(widget)
                        .frame(width: 184, height: 112)
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("productivity-dashboard")
        .onAppear {
            DownloadWatcher.shared.refreshConfiguration()
            BluetoothActivityManager.shared.refreshConfiguration()
            ClipboardHistoryManager.shared.refreshConfiguration()
            MeetingActivityManager.shared.refreshConfiguration()
            WeatherActivityManager.shared.refresh()
        }
    }

    private var visibleWidgets: [ProductivityWidget] {
        let enabled = Set(enabledWidgets)
        let ordered = widgetOrder.filter(enabled.contains)
        let missing = ProductivityWidget.allCases.filter { enabled.contains($0) && !ordered.contains($0) }
        return ordered + missing
    }

    @ViewBuilder
    private func widgetView(_ widget: ProductivityWidget) -> some View {
        switch widget {
        case .downloads: DownloadWidgetView()
        case .bluetooth: BluetoothWidgetView()
        case .weather: WeatherWidgetView()
        case .clipboard: ClipboardWidgetView()
        case .timer: FocusTimerWidgetView()
        case .meeting: MeetingWidgetView()
        }
    }
}

private struct WidgetCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(10)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        }
    }
}

private struct DownloadWidgetView: View {
    @ObservedObject private var watcher = DownloadWatcher.shared

    var body: some View {
        WidgetCard(title: "Downloads", systemImage: "arrow.down.circle.fill") {
            DownloadArea(watcher: watcher)
                .font(.caption)
        }
        .accessibilityIdentifier("widget-downloads")
    }
}

private struct BluetoothWidgetView: View {
    @ObservedObject private var manager = BluetoothActivityManager.shared

    var body: some View {
        WidgetCard(title: "Bluetooth", systemImage: "airpodspro") {
            if manager.connectedDevices.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("No connected devices")
                        .font(.subheadline.weight(.medium))
                    Text("AirPods and paired Bluetooth devices appear here.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(manager.connectedDevices.prefix(3)) { device in
                        Label(device.name, systemImage: device.isAirPods ? "airpodspro" : "dot.radiowaves.left.and.right")
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
            }
        }
        .accessibilityIdentifier("widget-bluetooth")
    }
}

private struct WeatherWidgetView: View {
    @ObservedObject private var manager = WeatherActivityManager.shared
    @Default(.weatherEnabled) private var weatherEnabled

    var body: some View {
        WidgetCard(title: "Weather", systemImage: "cloud.sun.fill") {
            if !weatherEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Weather is off")
                        .font(.subheadline.weight(.medium))
                    Button("Enable in Settings") {
                        SettingsWindowController.shared.showWindow()
                    }
                    .buttonStyle(.link)
                }
            } else if let snapshot = manager.snapshot {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            Text(snapshot.temperatureCelsius, format: .number.precision(.fractionLength(0)))
                                .font(.title2.bold())
                            Text("°C")
                                .font(.caption)
                        }
                        Text(snapshot.condition)
                            .font(.caption)
                            .lineLimit(1)
                        Text(snapshot.locationName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: snapshot.symbolName)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 30))
                }
            } else if manager.isLoading {
                ProgressView("Loading…")
                    .controlSize(.small)
            } else if let issue = manager.issue {
                VStack(alignment: .leading, spacing: 4) {
                    Text(issue.title)
                        .font(.subheadline.weight(.medium))
                    Text(issue.message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    HStack(spacing: 10) {
                        if issue.offersSettings {
                            Button("Settings") {
                                SettingsWindowController.shared.showWindow()
                            }
                        }
                        Button("Retry") {
                            manager.refresh()
                        }
                    }
                    .buttonStyle(.link)
                    .controlSize(.small)
                }
            } else {
                Text("Weather is ready to refresh.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("widget-weather")
    }
}

private struct ClipboardWidgetView: View {
    @ObservedObject private var manager = ClipboardHistoryManager.shared
    @Default(.clipboardHistoryEnabled) private var enabled

    var body: some View {
        WidgetCard(title: "Clipboard", systemImage: "clipboard.fill") {
            if !enabled {
                VStack(alignment: .leading, spacing: 5) {
                    Text("History is off by default")
                        .font(.subheadline.weight(.medium))
                    Text("Enable it in Settings. Password-manager copies stay excluded.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if let entry = manager.entries.first {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.preview)
                        .font(.caption)
                        .lineLimit(3)
                    HStack {
                        Button("Copy") { manager.copy(entry) }
                            .buttonStyle(.borderless)
                        Spacer()
                        Text(entry.copiedAt, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Copy text in another app to begin.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("widget-clipboard")
    }
}

private struct FocusTimerWidgetView: View {
    @ObservedObject private var timer = FocusTimerManager.shared

    var body: some View {
        WidgetCard(title: timer.mode.title, systemImage: "timer") {
            VStack(spacing: 7) {
                HStack {
                    Text(timer.formattedRemaining)
                        .font(.title2.monospacedDigit().bold())
                    Spacer()
                    ProgressView(value: timer.progress)
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                }
                HStack(spacing: 12) {
                    Button {
                        timer.toggle()
                    } label: {
                        Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                    }
                    Button { timer.reset() } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    Menu {
                        ForEach(FocusTimerMode.allCases.filter { $0 != .custom }) { mode in
                            Button(mode.title) { timer.selectMode(mode) }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    Spacer()
                    Text("\(timer.completedFocusSessions) sessions")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityIdentifier("widget-focus-timer")
    }
}

private struct MeetingWidgetView: View {
    @ObservedObject private var manager = MeetingActivityManager.shared

    var body: some View {
        WidgetCard(title: "Next Meeting", systemImage: "video.fill") {
            if manager.authorizationStatus != .fullAccess {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Calendar access required")
                        .font(.subheadline.weight(.medium))
                    Button("Allow Calendar") {
                        Task { await manager.requestAccessAndRefresh() }
                    }
                    .buttonStyle(.link)
                }
            } else if let meeting = manager.nextMeeting {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(meeting.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                        Text(relativeStart(for: meeting, now: context.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if manager.joinURL != nil {
                            Button("Join") { manager.join() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                        }
                    }
                }
            } else {
                Text("No upcoming events")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("widget-next-meeting")
    }

    private func relativeStart(for meeting: EventModel, now: Date) -> String {
        if meeting.start <= now, meeting.end > now { return "In progress" }
        return meeting.start.formatted(.relative(presentation: .named, unitsStyle: .wide))
    }
}

struct CompactProductivityActivity: View {
    let type: SneakContentType
    @ObservedObject private var bluetooth = BluetoothActivityManager.shared
    @ObservedObject private var timer = FocusTimerManager.shared
    @ObservedObject private var meeting = MeetingActivityManager.shared

    var body: some View {
        HStack(spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Rectangle().fill(.black).frame(minWidth: 90)
            Text(detail)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
    }

    private var title: String {
        switch type {
        case .bluetooth: bluetooth.lastChangedDevice?.name ?? "Bluetooth"
        case .timer: timer.mode.title
        case .meeting: meeting.nextMeeting?.title ?? "Meeting"
        default: "Activity"
        }
    }

    private var icon: String {
        switch type {
        case .bluetooth: bluetooth.lastChangedDevice?.isAirPods == true ? "airpodspro" : "dot.radiowaves.left.and.right"
        case .timer: "timer"
        case .meeting: "video.fill"
        default: "sparkles"
        }
    }

    private var detail: String {
        switch type {
        case .bluetooth:
            bluetooth.lastChangedDevice?.isConnected == true ? "Connected" : "Disconnected"
        case .timer: timer.formattedRemaining
        case .meeting:
            meeting.nextMeeting?.start.formatted(date: .omitted, time: .shortened) ?? "Soon"
        default: ""
        }
    }
}
