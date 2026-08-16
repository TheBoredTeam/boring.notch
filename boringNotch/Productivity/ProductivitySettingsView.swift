import Defaults
import SwiftUI

struct ProductivitySettingsView: View {
    @Default(.productivityWidgetOrder) private var widgetOrder
    @Default(.enabledProductivityWidgets) private var enabledWidgets
    @Default(.enableDownloadListener) private var downloadsEnabled
    @Default(.enableSafariDownloads) private var safariDownloads
    @Default(.enableChromiumDownloads) private var chromiumDownloads
    @Default(.enableFirefoxDownloads) private var firefoxDownloads
    @Default(.enableHorizontalMediaGestures) private var horizontalGestures
    @Default(.gestureSensitivity) private var gestureSensitivity
    @Default(.bluetoothLiveActivityEnabled) private var bluetoothEnabled
    @Default(.weatherEnabled) private var weatherEnabled
    @Default(.weatherUseCurrentLocation) private var useCurrentLocation
    @Default(.weatherLatitude) private var latitude
    @Default(.weatherLongitude) private var longitude
    @Default(.weatherLocationName) private var locationName
    @Default(.clipboardHistoryEnabled) private var clipboardEnabled
    @Default(.persistClipboardHistory) private var persistClipboard
    @Default(.clipboardRetentionHours) private var clipboardRetentionHours
    @Default(.clipboardMaximumItemCount) private var clipboardMaximumItemCount
    @Default(.focusDurationMinutes) private var focusMinutes
    @Default(.shortBreakDurationMinutes) private var shortBreakMinutes
    @Default(.longBreakDurationMinutes) private var longBreakMinutes
    @Default(.autoStartFocusBreaks) private var autoStartBreaks
    @Default(.meetingCardEnabled) private var meetingEnabled
    @Default(.meetingLookAheadDays) private var meetingLookAheadDays

    var body: some View {
        Form {
            widgetLayoutSection
            downloadsSection
            gesturesSection
            bluetoothSection
            weatherSection
            clipboardSection
            timerSection
            meetingSection
        }
        .navigationTitle("Glances")
        .accentColor(.effectiveAccent)
    }

    private var widgetLayoutSection: some View {
        Section {
            ForEach(Array(normalizedOrder.enumerated()), id: \.element.id) { index, widget in
                HStack {
                    Toggle(
                        isOn: Binding(
                            get: { enabledWidgets.contains(widget) },
                            set: { setWidget(widget, enabled: $0) }
                        )
                    ) {
                        Label(widget.title, systemImage: widget.systemImage)
                    }
                    Spacer()
                    Button { moveWidget(at: index, offset: -1) } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == 0)
                    .accessibilityLabel("Move \(widget.title) earlier")
                    Button { moveWidget(at: index, offset: 1) } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == normalizedOrder.count - 1)
                    .accessibilityLabel("Move \(widget.title) later")
                }
            }
        } header: {
            Text("Glances layout")
        } footer: {
            Text("Choose which cards appear and arrange their order in the notch.")
        }
    }

    private var downloadsSection: some View {
        Section {
            Toggle("Show browser download progress", isOn: $downloadsEnabled)
            Toggle("Safari", isOn: $safariDownloads)
                .disabled(!downloadsEnabled)
            Toggle("Chromium browsers", isOn: $chromiumDownloads)
                .disabled(!downloadsEnabled)
            Toggle("Firefox", isOn: $firefoxDownloads)
                .disabled(!downloadsEnabled)
        } header: {
            Label("Downloads", systemImage: "arrow.down.circle")
        } footer: {
            Text("Monitors .download, .crdownload, and .part files in your Downloads folder. Unknown total sizes use an indeterminate indicator.")
        }
        .onChange(of: downloadsEnabled) { DownloadWatcher.shared.refreshConfiguration() }
        .onChange(of: safariDownloads) { DownloadWatcher.shared.refreshConfiguration() }
        .onChange(of: chromiumDownloads) { DownloadWatcher.shared.refreshConfiguration() }
        .onChange(of: firefoxDownloads) { DownloadWatcher.shared.refreshConfiguration() }
    }

    private var gesturesSection: some View {
        Section {
            Toggle("Swipe horizontally to change tracks", isOn: $horizontalGestures)
            LabeledContent("Swipe sensitivity") {
                Picker("Swipe sensitivity", selection: $gestureSensitivity) {
                    Text("High").tag(CGFloat(100))
                    Text("Medium").tag(CGFloat(200))
                    Text("Low").tag(CGFloat(300))
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 210)
            }
            .disabled(!horizontalGestures)
        } header: {
            Label("Media gestures", systemImage: "arrow.left.and.right")
        }
    }

    private var bluetoothSection: some View {
        Section {
            Toggle("Bluetooth and AirPods live activity", isOn: $bluetoothEnabled)
        } header: {
            Label("Bluetooth", systemImage: "airpodspro")
        }
        .onChange(of: bluetoothEnabled) { BluetoothActivityManager.shared.refreshConfiguration() }
    }

    private var weatherSection: some View {
        Section {
            Toggle("Show weather", isOn: $weatherEnabled)
            Toggle("Use current location", isOn: $useCurrentLocation)
                .disabled(!weatherEnabled)
            if !useCurrentLocation {
                TextField("Location name", text: $locationName)
                LabeledContent("Latitude") {
                    TextField("Latitude", value: $latitude, format: .number)
                        .frame(width: 120)
                }
                LabeledContent("Longitude") {
                    TextField("Longitude", value: $longitude, format: .number)
                        .frame(width: 120)
                }
            }
            Button("Refresh Weather") { WeatherActivityManager.shared.refresh() }
                .disabled(!weatherEnabled)
        } header: {
            Label("Weather", systemImage: "cloud.sun")
        } footer: {
            Text("WeatherKit requires a signed build whose App ID has the WeatherKit capability enabled.")
        }
        .onChange(of: weatherEnabled) { WeatherActivityManager.shared.refresh() }
        .onChange(of: useCurrentLocation) { WeatherActivityManager.shared.refresh() }
        .onChange(of: latitude) { WeatherActivityManager.shared.refresh() }
        .onChange(of: longitude) { WeatherActivityManager.shared.refresh() }
    }

    private var clipboardSection: some View {
        Section {
            Toggle("Keep text clipboard history", isOn: $clipboardEnabled)
            Toggle("Persist history across launches", isOn: $persistClipboard)
                .disabled(!clipboardEnabled)
            Stepper("Retention: \(clipboardRetentionHours) hours", value: $clipboardRetentionHours, in: 1...168)
                .disabled(!clipboardEnabled)
            Stepper("Maximum items: \(clipboardMaximumItemCount)", value: $clipboardMaximumItemCount, in: 5...100, step: 5)
                .disabled(!clipboardEnabled)
            Button("Clear Clipboard History", role: .destructive) {
                ClipboardHistoryManager.shared.clear()
            }
        } header: {
            Label("Private clipboard", systemImage: "clipboard")
        } footer: {
            Text("Off by default. Text stays local; password managers, transient pasteboards, private keys, and common API-token formats are excluded.")
        }
        .onChange(of: clipboardEnabled) { ClipboardHistoryManager.shared.refreshConfiguration() }
        .onChange(of: persistClipboard) { ClipboardHistoryManager.shared.refreshConfiguration() }
        .onChange(of: clipboardRetentionHours) { ClipboardHistoryManager.shared.refreshConfiguration() }
        .onChange(of: clipboardMaximumItemCount) { ClipboardHistoryManager.shared.refreshConfiguration() }
    }

    private var timerSection: some View {
        Section {
            Stepper("Focus: \(focusMinutes) minutes", value: $focusMinutes, in: 1...120)
            Stepper("Short break: \(shortBreakMinutes) minutes", value: $shortBreakMinutes, in: 1...60)
            Stepper("Long break: \(longBreakMinutes) minutes", value: $longBreakMinutes, in: 1...90)
            Toggle("Automatically start breaks", isOn: $autoStartBreaks)
        } header: {
            Label("Focus timer", systemImage: "timer")
        }
    }

    private var meetingSection: some View {
        Section {
            Toggle("Show next meeting", isOn: $meetingEnabled)
            Stepper("Look ahead: \(meetingLookAheadDays) days", value: $meetingLookAheadDays, in: 1...30)
                .disabled(!meetingEnabled)
            Button("Refresh Meetings") {
                Task { await MeetingActivityManager.shared.refresh() }
            }
            .disabled(!meetingEnabled)
        } header: {
            Label("Meeting card", systemImage: "video")
        } footer: {
            Text("Recognizes HTTPS links for Zoom, Google Meet, Microsoft Teams, and Webex in event URLs, locations, or notes.")
        }
        .onChange(of: meetingEnabled) { MeetingActivityManager.shared.refreshConfiguration() }
        .onChange(of: meetingLookAheadDays) { Task { await MeetingActivityManager.shared.refresh() } }
    }

    private var normalizedOrder: [ProductivityWidget] {
        widgetOrder + ProductivityWidget.allCases.filter { !widgetOrder.contains($0) }
    }

    private func setWidget(_ widget: ProductivityWidget, enabled: Bool) {
        if enabled {
            if !enabledWidgets.contains(widget) { enabledWidgets.append(widget) }
        } else {
            enabledWidgets.removeAll { $0 == widget }
        }
    }

    private func moveWidget(at index: Int, offset: Int) {
        var order = normalizedOrder
        let destination = index + offset
        guard order.indices.contains(index), order.indices.contains(destination) else { return }
        order.swapAt(index, destination)
        widgetOrder = order
    }
}
