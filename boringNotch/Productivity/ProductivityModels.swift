import AppKit
import Defaults
import Foundation

enum ProductivityWidget: String, CaseIterable, Codable, Defaults.Serializable, Identifiable, Sendable {
    case downloads
    case bluetooth
    case weather
    case clipboard
    case timer
    case meeting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .downloads: "Downloads"
        case .bluetooth: "Bluetooth"
        case .weather: "Weather"
        case .clipboard: "Clipboard"
        case .timer: "Focus Timer"
        case .meeting: "Next Meeting"
        }
    }

    var systemImage: String {
        switch self {
        case .downloads: "arrow.down.circle.fill"
        case .bluetooth: "airpodspro"
        case .weather: "cloud.sun.fill"
        case .clipboard: "clipboard.fill"
        case .timer: "timer"
        case .meeting: "video.fill"
        }
    }
}

enum DownloadBrowser: String, Codable, CaseIterable, Sendable {
    case safari
    case chromium
    case firefox

    var displayName: String {
        switch self {
        case .safari: "Safari"
        case .chromium: "Chromium"
        case .firefox: "Firefox"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .safari: "com.apple.Safari"
        case .chromium: "com.google.Chrome"
        case .firefox: "org.mozilla.firefox"
        }
    }
}

struct DownloadRecord: Identifiable, Equatable, Sendable {
    let id: String
    let sourceURL: URL
    let displayName: String
    let browser: DownloadBrowser
    let bytesReceived: Int64
    let totalBytes: Int64?
    let startedAt: Date

    var progress: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(max(Double(bytesReceived) / Double(totalBytes), 0), 1)
    }

    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: bytesReceived, countStyle: .file)
    }
}

struct BluetoothDeviceSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let isConnected: Bool
    let isAirPods: Bool
}

struct WeatherSnapshot: Equatable, Sendable {
    let temperatureCelsius: Double
    let apparentTemperatureCelsius: Double
    let symbolName: String
    let condition: String
    let locationName: String
    let fetchedAt: Date
}

struct ClipboardHistoryEntry: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let text: String
    let copiedAt: Date
    let sourceBundleIdentifier: String?

    var preview: String {
        text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum FocusTimerMode: String, CaseIterable, Codable, Defaults.Serializable, Identifiable, Sendable {
    case focus
    case shortBreak
    case longBreak
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: "Focus"
        case .shortBreak: "Short Break"
        case .longBreak: "Long Break"
        case .custom: "Timer"
        }
    }
}

extension Defaults.Keys {
    static let productivityWidgetOrder = Key<[ProductivityWidget]>(
        "productivityWidgetOrder",
        default: ProductivityWidget.allCases
    )
    static let enabledProductivityWidgets = Key<[ProductivityWidget]>(
        "enabledProductivityWidgets",
        default: ProductivityWidget.allCases
    )

    static let enableChromiumDownloads = Key<Bool>("enableChromiumDownloads", default: true)
    static let enableFirefoxDownloads = Key<Bool>("enableFirefoxDownloads", default: true)

    static let bluetoothLiveActivityEnabled = Key<Bool>(
        "bluetoothLiveActivityEnabled",
        default: true
    )

    static let weatherEnabled = Key<Bool>("weatherEnabled", default: false)
    static let weatherUseCurrentLocation = Key<Bool>("weatherUseCurrentLocation", default: true)
    static let weatherLatitude = Key<Double>("weatherLatitude", default: 43.6532)
    static let weatherLongitude = Key<Double>("weatherLongitude", default: -79.3832)
    static let weatherLocationName = Key<String>("weatherLocationName", default: "Toronto")

    static let clipboardHistoryEnabled = Key<Bool>("clipboardHistoryEnabled", default: false)
    static let persistClipboardHistory = Key<Bool>("persistClipboardHistory", default: false)
    static let clipboardRetentionHours = Key<Int>("clipboardRetentionHours", default: 24)
    static let clipboardMaximumItemCount = Key<Int>("clipboardMaximumItemCount", default: 30)
    static let clipboardExcludedBundleIdentifiers = Key<[String]>(
        "clipboardExcludedBundleIdentifiers",
        default: [
            "com.1password.1password",
            "com.agilebits.onepassword7",
            "com.bitwarden.desktop",
            "com.lastpass.LastPass",
            "org.keepassxc.keepassxc",
        ]
    )

    static let focusDurationMinutes = Key<Int>("focusDurationMinutes", default: 25)
    static let shortBreakDurationMinutes = Key<Int>("shortBreakDurationMinutes", default: 5)
    static let longBreakDurationMinutes = Key<Int>("longBreakDurationMinutes", default: 15)
    static let customTimerDurationMinutes = Key<Int>("customTimerDurationMinutes", default: 10)
    static let autoStartFocusBreaks = Key<Bool>("autoStartFocusBreaks", default: true)
    static let focusTimerMode = Key<FocusTimerMode>("focusTimerMode", default: .focus)
    static let focusTimerEndDate = Key<Date?>("focusTimerEndDate", default: nil)
    static let focusTimerRemainingSeconds = Key<Double>("focusTimerRemainingSeconds", default: 25 * 60)
    static let focusTimerIsRunning = Key<Bool>("focusTimerIsRunning", default: false)
    static let completedFocusSessions = Key<Int>("completedFocusSessions", default: 0)

    static let meetingCardEnabled = Key<Bool>("meetingCardEnabled", default: true)
    static let meetingLookAheadDays = Key<Int>("meetingLookAheadDays", default: 7)
}
