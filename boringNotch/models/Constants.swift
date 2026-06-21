//
//  Constants.swift
//  boringNotch
//
//  Created by Richard Kunkli on 2024. 10. 17..
//

import SwiftUI
import Defaults

private let availableDirectories = FileManager
    .default
    .urls(for: .documentDirectory, in: .userDomainMask)
let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
let bundleIdentifier = Bundle.main.bundleIdentifier!
let appVersion = "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))"

let temporaryDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
let spacing: CGFloat = 16

struct CustomVisualizer: Codable, Hashable, Equatable, Defaults.Serializable {
    let UUID: UUID
    var name: String
    var url: URL
    var speed: CGFloat = 1.0
}

enum CalendarSelectionState: Codable, Defaults.Serializable {
    case all
    case selected(Set<String>)
}

enum HideNotchOption: String, Defaults.Serializable {
    case always
    case nowPlayingOnly
    case never
}

// Define notification names at file scope
extension Notification.Name {
    static let mediaControllerChanged = Notification.Name("mediaControllerChanged")
}

// Media controller types for selection in settings
enum MediaControllerType: String, CaseIterable, Identifiable, Defaults.Serializable {
    case nowPlaying = "Now Playing"
    case appleMusic = "Apple Music"
    case spotify = "Spotify"
    case youtubeMusic = "YouTube Music"
    
    var id: String { self.rawValue }
}

// Sneak peek styles for selection in settings
enum SneakPeekStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case standard = "Default"
    case inline = "Inline"
    
    var id: String { self.rawValue }
}

// Action to perform when Option (⌥) is held while pressing media keys
enum OptionKeyAction: String, CaseIterable, Identifiable, Defaults.Serializable {
    case openSettings = "Open System Settings"
    case showHUD = "Show HUD"
    case none = "No Action"

    var id: String { self.rawValue }
}

extension Defaults.Keys {
    // MARK: General
    static let menubarIcon = Key<Bool>("menubarIcon", default: true)
    static let showOnAllDisplays = Key<Bool>("showOnAllDisplays", default: false)
    static let automaticallySwitchDisplay = Key<Bool>("automaticallySwitchDisplay", default: true)
    static let releaseName = Key<String>("releaseName", default: "Flying Rabbit 🐇🪽")
    
    // MARK: Behavior
    static let minimumHoverDuration = Key<TimeInterval>("minimumHoverDuration", default: 0.3)
    static let enableHaptics = Key<Bool>("enableHaptics", default: true)
    static let openNotchOnHover = Key<Bool>("openNotchOnHover", default: true)
    static let extendHoverArea = Key<Bool>("extendHoverArea", default: false)
    static let notchHeightMode = Key<WindowHeightMode>(
        "notchHeightMode",
        default: WindowHeightMode.matchRealNotchSize
    )
    static let nonNotchHeightMode = Key<WindowHeightMode>(
        "nonNotchHeightMode",
        default: WindowHeightMode.matchMenuBar
    )
    static let nonNotchHeight = Key<CGFloat>("nonNotchHeight", default: 32)
    static let notchHeight = Key<CGFloat>("notchHeight", default: 32)
    //static let openLastTabByDefault = Key<Bool>("openLastTabByDefault", default: false)
    static let showOnLockScreen = Key<Bool>("showOnLockScreen", default: false)
    static let hideFromScreenRecording = Key<Bool>("hideFromScreenRecording", default: false)
    
    // MARK: Appearance
    static let showEmojis = Key<Bool>("showEmojis", default: false)
    //static let alwaysShowTabs = Key<Bool>("alwaysShowTabs", default: true)
    static let showMirror = Key<Bool>("showMirror", default: false)
    static let mirrorShape = Key<MirrorShapeEnum>("mirrorShape", default: MirrorShapeEnum.rectangle)
    static let settingsIconInNotch = Key<Bool>("settingsIconInNotch", default: true)
    static let lightingEffect = Key<Bool>("lightingEffect", default: true)
    static let enableShadow = Key<Bool>("enableShadow", default: true)
    static let cornerRadiusScaling = Key<Bool>("cornerRadiusScaling", default: true)

    static let showNotHumanFace = Key<Bool>("showNotHumanFace", default: false)
    static let tileShowLabels = Key<Bool>("tileShowLabels", default: false)
    static let showCalendar = Key<Bool>("showCalendar", default: false)
    static let hideCompletedReminders = Key<Bool>("hideCompletedReminders", default: true)
    static let sliderColor = Key<SliderColorEnum>(
        "sliderUseAlbumArtColor",
        default: SliderColorEnum.white
    )
    static let playerColorTinting = Key<Bool>("playerColorTinting", default: true)
    static let useMusicVisualizer = Key<Bool>("useMusicVisualizer", default: true)
    static let customVisualizers = Key<[CustomVisualizer]>("customVisualizers", default: [])
    static let selectedVisualizer = Key<CustomVisualizer?>("selectedVisualizer", default: nil)
    
    // MARK: Gestures
    static let enableGestures = Key<Bool>("enableGestures", default: true)
    static let closeGestureEnabled = Key<Bool>("closeGestureEnabled", default: true)
    static let gestureSensitivity = Key<CGFloat>("gestureSensitivity", default: 200.0)
    
    // MARK: Media playback
    static let coloredSpectrogram = Key<Bool>("coloredSpectrogram", default: true)
    static let enableSneakPeek = Key<Bool>("enableSneakPeek", default: false)
    static let sneakPeekStyles = Key<SneakPeekStyle>("sneakPeekStyles", default: .standard)
    static let waitInterval = Key<Double>("waitInterval", default: 3)
    static let showShuffleAndRepeat = Key<Bool>("showShuffleAndRepeat", default: false)
    static let enableLyrics = Key<Bool>("enableLyrics", default: false)
    static let musicControlSlots = Key<[MusicControlButton]>(
        "musicControlSlots",
        default: MusicControlButton.defaultLayout
    )
    static let musicControlSlotLimit = Key<Int>(
        "musicControlSlotLimit",
        default: MusicControlButton.defaultLayout.count
    )
    
    // MARK: Battery
    static let showPowerStatusNotifications = Key<Bool>("showPowerStatusNotifications", default: true)
    static let showBatteryIndicator = Key<Bool>("showBatteryIndicator", default: true)
    static let showBatteryPercentage = Key<Bool>("showBatteryPercentage", default: true)
    static let showPowerStatusIcons = Key<Bool>("showPowerStatusIcons", default: true)
    
    // MARK: Downloads
    static let enableDownloadListener = Key<Bool>("enableDownloadListener", default: true)
    static let enableSafariDownloads = Key<Bool>("enableSafariDownloads", default: true)
    static let selectedDownloadIndicatorStyle = Key<DownloadIndicatorStyle>("selectedDownloadIndicatorStyle", default: DownloadIndicatorStyle.progress)
    static let selectedDownloadIconStyle = Key<DownloadIconStyle>("selectedDownloadIconStyle", default: DownloadIconStyle.onlyAppIcon)
    
    // MARK: HUD
    static let hudReplacement = Key<Bool>("hudReplacement", default: false)
    static let inlineHUD = Key<Bool>("inlineHUD", default: false)
    static let enableGradient = Key<Bool>("enableGradient", default: false)
    static let systemEventIndicatorShadow = Key<Bool>("systemEventIndicatorShadow", default: false)
    static let systemEventIndicatorUseAccent = Key<Bool>("systemEventIndicatorUseAccent", default: false)
    static let showOpenNotchHUD = Key<Bool>("showOpenNotchHUD", default: true)
    static let showOpenNotchHUDPercentage = Key<Bool>("showOpenNotchHUDPercentage", default: true)
    static let showClosedNotchHUDPercentage = Key<Bool>("showClosedNotchHUDPercentage", default: false)
    // Option key modifier behaviour for media keys
    static let optionKeyAction = Key<OptionKeyAction>("optionKeyAction", default: OptionKeyAction.openSettings)
    
    // MARK: Shelf
    static let boringShelf = Key<Bool>("boringShelf", default: true)
    static let openShelfByDefault = Key<Bool>("openShelfByDefault", default: true)
    static let shelfTapToOpen = Key<Bool>("shelfTapToOpen", default: true)
    static let quickShareProvider = Key<String>("quickShareProvider", default: QuickShareProvider.defaultProvider.id)
    static let copyOnDrag = Key<Bool>("copyOnDrag", default: false)
    static let autoRemoveShelfItems = Key<Bool>("autoRemoveShelfItems", default: false)
    static let expandedDragDetection = Key<Bool>("expandedDragDetection", default: true)
    
    // MARK: Calendar
    static let calendarSelectionState = Key<CalendarSelectionState>("calendarSelectionState", default: .all)
    static let hideAllDayEvents = Key<Bool>("hideAllDayEvents", default: false)
    static let showFullEventTitles = Key<Bool>("showFullEventTitles", default: false)
    static let autoScrollToNextEvent = Key<Bool>("autoScrollToNextEvent", default: true)
    
    // MARK: Fullscreen Media Detection
    static let hideNotchOption = Key<HideNotchOption>("hideNotchOption", default: .nowPlayingOnly)
    
    // MARK: Media Controller
    static let mediaController = Key<MediaControllerType>("mediaController", default: defaultMediaController)
    
    // MARK: Advanced Settings
    static let useCustomAccentColor = Key<Bool>("useCustomAccentColor", default: false)
    static let customAccentColorData = Key<Data?>("customAccentColorData", default: nil)
    // Show or hide the title bar
    static let hideTitleBar = Key<Bool>("hideTitleBar", default: true)
    
    // Helper to determine the default media controller based on NowPlaying deprecation status
    static var defaultMediaController: MediaControllerType {
        if MusicManager.shared.isNowPlayingDeprecated {
            return .appleMusic
        } else {
            return .nowPlaying
        }
    }

    static let didClearLegacyURLCacheV1 = Key<Bool>("didClearLegacyURLCache_v1", default: false)
}

// MARK: - Clipboard Shelf Integrations

import Combine
import CryptoKit

enum ClipboardItemType: String, Codable {
    case plainText
    case richText
    case image
    case url
    case file
    case codeSnippet
}

struct ClipboardItem: Identifiable, Codable, Hashable {
    let id: UUID
    let contentType: ClipboardItemType
    let contentValue: String // Text value, URL string, JSON array of file paths, or image filename
    let previewText: String
    let timestamp: Date
    var isPinned: Bool
    var imageHash: String?
    var rtfData: Data?
    var htmlData: Data?
    
    // Helper to check if a file path is a folder
    var isFolder: Bool {
        guard contentType == .file else { return false }
        if let paths = try? JSONDecoder().decode([String].self, from: contentValue.data(using: .utf8) ?? Data()),
           let firstPath = paths.first {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: firstPath, isDirectory: &isDir) {
                return isDir.boolValue
            }
        }
        return false
    }
}

@MainActor
final class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()
    
    @Published var items: [ClipboardItem] = [] {
        didSet {
            saveHistory()
        }
    }
    
    @Published var isTracking: Bool = true {
        didSet {
            UserDefaults.standard.set(isTracking, forKey: "clipboard_tracking_enabled")
        }
    }
    
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var timer: Timer?
    private let maxItemCount = 50
    
    private let fileManager = FileManager.default
    private let historyFileURL: URL
    private let imagesDirectoryURL: URL
    
    private init() {
        // Setup local storage paths
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let baseDir = appSupport.appendingPathComponent("boringNotch", isDirectory: true).appendingPathComponent("Clipboard", isDirectory: true)
        
        self.historyFileURL = baseDir.appendingPathComponent("history.json")
        self.imagesDirectoryURL = baseDir.appendingPathComponent("Images", isDirectory: true)
        
        // Ensure directories exist
        try? fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: imagesDirectoryURL, withIntermediateDirectories: true)
        
        // Load settings
        self.isTracking = UserDefaults.standard.object(forKey: "clipboard_tracking_enabled") as? Bool ?? true
        
        // Load history
        loadHistory()
        
        // Start pasteboard monitoring
        startMonitoring()
    }
    
    deinit {
        timer?.invalidate()
    }
    
    // MARK: - Monitoring Lifecycle
    
    func startMonitoring() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkPasteboard()
            }
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    // MARK: - Core Pasteboard Handling
    
    private func checkPasteboard() {
        guard isTracking else { return }
        
        let changeCount = NSPasteboard.general.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        
        processCurrentPasteboard()
    }
    
    private func processCurrentPasteboard() {
        let pasteboard = NSPasteboard.general
        
        // 1. Files & Folders
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [NSPasteboard.ReadingOptionKey.urlReadingFileURLsOnly: true]) as? [URL], !fileURLs.isEmpty {
            let paths = fileURLs.map { $0.path }
            if let pathsData = try? JSONEncoder().encode(paths),
               let pathsString = String(data: pathsData, encoding: .utf8) {
                let preview = fileURLs.count == 1 ? fileURLs[0].lastPathComponent : "\(fileURLs.count) files"
                addOrUpdateItem(type: .file, value: pathsString, preview: preview)
            }
            return
        }
        
        // 2. URLs (non-file URLs)
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], let url = urls.first, !url.isFileURL {
            addOrUpdateItem(type: .url, value: url.absoluteString, preview: url.absoluteString)
            return
        }
        
        // 3. Images
        if let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
            guard let pngData = image.pngData() else { return }
            let hash = sha256(data: pngData)
            
            // Check if this image already exists in history (deduplication)
            if let existingItem = items.first(where: { $0.imageHash == hash }) {
                // Move existing item to the top
                moveItemToTop(existingItem)
                return
            }
            
            // Save image to disk
            let filename = "\(UUID().uuidString).png"
            let targetURL = imagesDirectoryURL.appendingPathComponent(filename)
            do {
                try pngData.write(to: targetURL)
                addOrUpdateItem(type: .image, value: filename, preview: "Screenshot/Image", imageHash: hash)
            } catch {
                NSLog("❌ Failed to save clipboard image to disk: \(error.localizedDescription)")
            }
            return
        }
        
        // 4. Strings (Text/RichText/Code)
        if let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Check if it's a URL in string format
            if let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "http" || url.scheme == "https", url.host != nil {
                addOrUpdateItem(type: .url, value: text, preview: text)
                return
            }
            
            // Check if it's a code snippet
            if isCodeSnippet(text) {
                addOrUpdateItem(type: .codeSnippet, value: text, preview: text)
                return
            }
            
            // Check for Rich Text formats
            let rtfData = pasteboard.data(forType: .rtf)
            let htmlData = pasteboard.data(forType: .html)
            
            if rtfData != nil || htmlData != nil {
                addOrUpdateItem(type: .richText, value: text, preview: text, rtfData: rtfData, htmlData: htmlData)
            } else {
                addOrUpdateItem(type: .plainText, value: text, preview: text)
            }
            return
        }
    }
    
    func ingestDroppedProviders(_ providers: [NSItemProvider]) {
        Task {
            let droppedItems = await ShelfDropService.items(from: providers)
            await MainActor.run {
                for item in droppedItems {
                    switch item.kind {
                    case .file(let data):
                        let bookmark = Bookmark(data: data)
                        if let url = bookmark.resolveURL() {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.writeObjects([url as NSURL])
                            self.processCurrentPasteboard()
                        }
                    case .text(let string):
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(string, forType: .string)
                        self.processCurrentPasteboard()
                    case .link(let url):
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.writeObjects([url as NSURL])
                        self.processCurrentPasteboard()
                    }
                }
            }
        }
    }
    
    // MARK: - Item Insertion & Deduplication
    
    private func addOrUpdateItem(type: ClipboardItemType, value: String, preview: String, imageHash: String? = nil, rtfData: Data? = nil, htmlData: Data? = nil) {
        let trimmedPreview = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayPreview = trimmedPreview.count > 120 ? String(trimmedPreview.prefix(117)) + "..." : trimmedPreview
        
        if let firstItem = items.first {
            if firstItem.contentType == type {
                if type == .image, firstItem.imageHash == imageHash {
                    moveItemToTop(firstItem)
                    return
                } else if firstItem.contentValue == value {
                    moveItemToTop(firstItem)
                    return
                }
            }
        }
        
        if let existingIdx = items.firstIndex(where: {
            if type == .image {
                return $0.imageHash == imageHash
            } else {
                return $0.contentValue == value && $0.contentType == type
            }
        }) {
            var item = items.remove(at: existingIdx)
            item = ClipboardItem(
                id: item.id,
                contentType: item.contentType,
                contentValue: item.contentValue,
                previewText: displayPreview,
                timestamp: Date(),
                isPinned: item.isPinned,
                imageHash: item.imageHash,
                rtfData: rtfData ?? item.rtfData,
                htmlData: htmlData ?? item.htmlData
            )
            items.insert(item, at: 0)
            return
        }
        
        let newItem = ClipboardItem(
            id: UUID(),
            contentType: type,
            contentValue: value,
            previewText: displayPreview,
            timestamp: Date(),
            isPinned: false,
            imageHash: imageHash,
            rtfData: rtfData,
            htmlData: htmlData
        )
        
        items.insert(newItem, at: 0)
        enforceHistoryRules()
    }
    
    private func moveItemToTop(_ item: ClipboardItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items.remove(at: idx)
        
        let updatedItem = ClipboardItem(
            id: item.id,
            contentType: item.contentType,
            contentValue: item.contentValue,
            previewText: item.previewText,
            timestamp: Date(),
            isPinned: item.isPinned,
            imageHash: item.imageHash,
            rtfData: item.rtfData,
            htmlData: item.htmlData
        )
        items.insert(updatedItem, at: 0)
    }
    
    private func enforceHistoryRules() {
        guard items.count > maxItemCount else { return }
        
        if items.count > maxItemCount {
            var newItems = items
            var idx = newItems.count - 1
            
            while idx >= 0 && newItems.count > maxItemCount {
                let item = newItems[idx]
                if !item.isPinned {
                    if item.contentType == .image {
                        let path = imagesDirectoryURL.appendingPathComponent(item.contentValue)
                        try? fileManager.removeItem(at: path)
                    }
                    newItems.remove(at: idx)
                }
                idx -= 1
            }
            items = newItems
        }
    }
    
    // MARK: - Actions
    
    func restoreToClipboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        stopMonitoring()
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                self.lastChangeCount = NSPasteboard.general.changeCount
                self.startMonitoring()
            }
        }
        
        switch item.contentType {
        case .plainText, .codeSnippet:
            pasteboard.setString(item.contentValue, forType: .string)
            
        case .richText:
            pasteboard.setString(item.contentValue, forType: .string)
            if let rtf = item.rtfData {
                pasteboard.setData(rtf, forType: .rtf)
            }
            if let html = item.htmlData {
                pasteboard.setData(html, forType: .html)
            }
            
        case .url:
            if let url = URL(string: item.contentValue) {
                pasteboard.writeObjects([url as NSURL])
            } else {
                pasteboard.setString(item.contentValue, forType: .string)
            }
            
        case .file:
            if let paths = try? JSONDecoder().decode([String].self, from: item.contentValue.data(using: .utf8) ?? Data()) {
                let urls = paths.map { URL(fileURLWithPath: $0) as NSURL }
                pasteboard.writeObjects(urls)
            }
            
        case .image:
            let imagePath = imagesDirectoryURL.appendingPathComponent(item.contentValue)
            if let image = NSImage(contentsOf: imagePath) {
                pasteboard.writeObjects([image])
            }
        }
    }
    
    func togglePin(_ item: ClipboardItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].isPinned.toggle()
        items = items
    }
    
    func deleteItem(_ item: ClipboardItem) {
        if item.contentType == .image {
            let path = imagesDirectoryURL.appendingPathComponent(item.contentValue)
            try? fileManager.removeItem(at: path)
        }
        items.removeAll { $0.id == item.id }
    }
    
    func clearAllNonPinned() {
        let nonPinned = items.filter { !$0.isPinned }
        for item in nonPinned {
            if item.contentType == .image {
                let path = imagesDirectoryURL.appendingPathComponent(item.contentValue)
                try? fileManager.removeItem(at: path)
            }
        }
        items.removeAll { !$0.isPinned }
    }
    
    func imageURL(for item: ClipboardItem) -> URL? {
        guard item.contentType == .image else { return nil }
        return imagesDirectoryURL.appendingPathComponent(item.contentValue)
    }
    
    // MARK: - Helper Methods
    
    private func isCodeSnippet(_ text: String) -> Bool {
        let prefixes = ["npm ", "git ", "pod ", "brew ", "docker ", "npx ", "pip ", "cargo ", "swift ", "yarn ", "python ", "node ", "java ", "clang ", "gcc ", "make "]
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in prefixes {
            if lower.hasPrefix(prefix) { return true }
        }
        
        let codeKeywords = ["func ", "function ", "import ", "class ", "var ", "let ", "const ", "struct ", "<html>", "public ", "private ", "void ", "#include", "using namespace", "package ", "def ", "return ", "assert "]
        var keywordCount = 0
        for keyword in codeKeywords {
            if text.contains(keyword) {
                keywordCount += 1
            }
        }
        
        let hasBraces = text.contains("{") && text.contains("}")
        let hasLines = text.components(separatedBy: .newlines).count > 1
        
        return keywordCount >= 2 || (hasBraces && hasLines) || (keywordCount >= 1 && hasBraces)
    }
    
    private func sha256(data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Persistence
    
    private func saveHistory() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        
        do {
            let data = try encoder.encode(items)
            try data.write(to: historyFileURL, options: .atomic)
        } catch {
            NSLog("❌ Failed to save clipboard history: \(error.localizedDescription)")
        }
    }
    
    private func loadHistory() {
        guard fileManager.fileExists(atPath: historyFileURL.path) else { return }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        do {
            let data = try Data(contentsOf: historyFileURL)
            let loadedItems = try decoder.decode([ClipboardItem].self, from: data)
            self.items = loadedItems.filter { item in
                if item.contentType == .image {
                    let imagePath = imagesDirectoryURL.appendingPathComponent(item.contentValue)
                    return fileManager.fileExists(atPath: imagePath.path)
                }
                return true
            }
        } catch {
            NSLog("❌ Failed to load clipboard history: \(error.localizedDescription)")
        }
    }
}

extension NSImage {
    func pngData() -> Data? {
        guard let tiffRepresentation = tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffRepresentation) else { return nil }
        return bitmapImage.representation(using: .png, properties: [:])
    }
}

