//
//  ExtensionManager.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class ExtensionManager: ObservableObject {
    static let shared = ExtensionManager()
    @Published private(set) var installed: [ExtensionManifest] = []
    @Published private(set) var settingsControllers: [String: NSViewController] = [:]
    @Published var message: String?
    @Published private(set) var needsRestart = false

    private var runtimes: [String: ExtensionRuntime] = [:]
    private var subscriptions = Set<AnyCancellable>()
    private var workspaceObservers: [NSObjectProtocol] = []
    private var locked = false
    private var awake = true
    private var sessionActive = true
    private var artwork: String?
    private var lastArtwork: NSImage?
    private var started = false
    private var loadedIDs = Set<String>()
    private var artworkDisabled = Set<String>()
    private var inactiveIDs = Set<String>()
    private var lockedNotchIDs = Set<String>()
    @Published private(set) var requestsLockedNotch = false

    private var directory: URL {
        #if DEBUG
        if ProcessInfo.processInfo.environment["BN_ALLOW_DEVELOPMENT_EXTENSIONS"] == "1",
           let path = ProcessInfo.processInfo.environment["BN_EXTENSION_TEST_DIRECTORY"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        #endif
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BoringNotch/Extensions", isDirectory: true)
    }

    func start() {
        guard !started else { return }
        started = true
        refresh()
        for manifest in installed {
            do { try load(manifest) } catch { message = error.localizedDescription }
        }
        MusicManager.shared.objectWillChange
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.publishSnapshot() }
            .store(in: &subscriptions)
        for (name, event) in [(NSWorkspace.screensDidSleepNotification, "sleep"),
                              (NSWorkspace.screensDidWakeNotification, "wake"),
                              (NSWorkspace.sessionDidResignActiveNotification, "session-inactive"),
                              (NSWorkspace.sessionDidBecomeActiveNotification, "session-active")] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    switch event {
                    case "wake": self?.awake = true
                    case "sleep": self?.awake = false
                    case "session-active": self?.sessionActive = true
                    case "session-inactive": self?.sessionActive = false
                    default: break
                    }
                    self?.publishSnapshot()
                    self?.send(event: event)
                }
            })
        }
    }

    func setScreenLocked(_ value: Bool) {
        locked = value
        publishSnapshot()
        send(event: value ? "lock" : "unlock")
    }

    private func send(event: String) {
        runtimes.values.forEach { $0.send(event: event) }
    }

    private func load(_ manifest: ExtensionManifest) throws {
        guard !loadedIDs.contains(manifest.id) else { throw ExtensionError.restartRequired }
        let runtime = try ExtensionRuntime(url: packageURL(manifest.id)) { context, command, value in
            guard Thread.isMainThread, let context, let command else { return }
            let productID = Unmanaged<NSString>.fromOpaque(context).takeUnretainedValue() as String
            let name = String(cString: command)
            MainActor.assumeIsolated {
                guard ExtensionManager.shared.runtimes[productID] != nil, value.isFinite else { return }
                if name == "presentation.artwork" {
                    ExtensionManager.shared.setArtworkRequested(value > 0, for: productID)
                    return
                }
                if name == "presentation.active" {
                    ExtensionManager.shared.setActive(value > 0, for: productID)
                    return
                }
                if name == "presentation.lockedNotch" {
                    ExtensionManager.shared.setLockedNotchRequested(value > 0, for: productID)
                    return
                }
                let music = MusicManager.shared
                switch name {
                case "media.toggle": music.playPause()
                case "media.next": music.nextTrack()
                case "media.previous": music.previousTrack()
                case "media.favorite": music.toggleFavoriteTrack()
                case "media.seek":
                    if value.isFinite { music.seek(to: min(max(0, value), music.songDuration)) }
                default: break
                }
            }
        }
        loadedIDs.insert(manifest.id)
        runtimes[manifest.id] = runtime
        settingsControllers[manifest.id] = runtime.settingsController()
        publishSnapshot(force: true)
        runtime.send(event: locked ? "lock" : "unlock")
        runtime.send(event: awake ? "wake" : "sleep")
        runtime.send(event: sessionActive ? "session-active" : "session-inactive")
    }

    private func publishSnapshot(force: Bool = false) {
        let visible = locked && awake && sessionActive
        let consumers = runtimes.filter { force || $0.value.manifest.receivesUpdates(
            locked: locked, awake: awake, sessionActive: sessionActive, requested: !inactiveIDs.contains($0.key)) }
        guard !consumers.isEmpty else {
            artwork = nil
            lastArtwork = nil
            return
        }
        let music = MusicManager.shared
        let needsArtwork = consumers.keys.contains { !artworkDisabled.contains($0) && !inactiveIDs.contains($0) &&
            runtimes[$0]?.manifest.receivesUpdates(locked: locked, awake: awake, sessionActive: sessionActive, requested: true) == true }
        if !needsArtwork {
            artwork = nil
            lastArtwork = nil
        } else if lastArtwork !== music.albumArt {
            lastArtwork = music.albumArt
            artwork = nil
            if let source = music.albumArt.cgImage(forProposedRect: nil, context: nil, hints: nil),
               let context = CGContext(data: nil, width: 600, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
                                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                context.interpolationQuality = .medium
                context.draw(source, in: CGRect(x: 0, y: 0, width: 600, height: 600))
                if let image = context.makeImage() {
                    artwork = NSBitmapImageRep(cgImage: image)
                        .representation(using: .jpeg, properties: [.compressionFactor: 0.85])?.base64EncodedString()
                }
            }
        }
        let snapshot: [String: Any] = [
            "title": music.songTitle, "artist": music.artistName, "album": music.album,
            "duration": music.songDuration, "elapsed": music.estimatedPlaybackPosition(),
            "timestamp": Date().timeIntervalSince1970, "rate": music.playbackRate,
            "playing": music.isPlaying, "idle": music.isPlayerIdle,
            "artwork": artwork ?? "", "favorite": music.isFavoriteTrack,
            "canFavorite": music.canFavoriteTrack
        ]
        for (id, runtime) in consumers {
            var extensionSnapshot = snapshot
            if artworkDisabled.contains(id) || !runtime.manifest.receivesUpdates(
                locked: locked, awake: awake, sessionActive: sessionActive, requested: !inactiveIDs.contains(id)) {
                extensionSnapshot["artwork"] = ""
            }
            if visible,
               let screen = NSScreen.screen(withUUID: BoringViewCoordinator.shared.selectedScreenUUID) ?? NSScreen.main {
                let size = getClosedNotchSize(screenUUID: screen.displayUUID)
                let height = max(32, max(size.height, screen.safeAreaInsets.top))
                extensionSnapshot["notchTarget"] = ["x": screen.frame.midX + size.width / 2 - 4,
                    "y": screen.frame.maxY - height / 2 - 12, "size": 24.0]
            }
            if let data = try? JSONSerialization.data(withJSONObject: extensionSnapshot) { runtime.send(snapshot: data) }
        }
    }

    private func setArtworkRequested(_ requested: Bool, for product: String) {
        let changed = requested ? artworkDisabled.remove(product) != nil : artworkDisabled.insert(product).inserted
        if changed { publishSnapshot(force: true) }
    }

    private func setActive(_ active: Bool, for id: String) {
        let changed = active ? inactiveIDs.remove(id) != nil : inactiveIDs.insert(id).inserted
        if changed { publishSnapshot(force: true) }
    }

    private func setLockedNotchRequested(_ requested: Bool, for id: String) {
        if requested { lockedNotchIDs.insert(id) } else { lockedNotchIDs.remove(id) }
        let value = !lockedNotchIDs.isEmpty
        if requestsLockedNotch != value { requestsLockedNotch = value }
    }

    private func approvePublisher(_ publisher: ExtensionPublisher, manifest: ExtensionManifest) -> Bool {
        guard !ExtensionTrustStore.isApproved(publisher, for: manifest.id) else { return true }
        let alert = NSAlert()
        alert.messageText = "Install \(manifest.name)?"
        alert.informativeText = "Publisher: \(publisher.name) (\(publisher.teamID)). Extensions run inside Boring Notch and share its access. Only install extensions from developers you trust."
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func enable(_ manifest: ExtensionManifest) {
        do {
            let publisher = try ExtensionPackage.verifySignature(at: packageURL(manifest.id))
            guard approvePublisher(publisher, manifest: manifest) else { return }
            ExtensionTrustStore.approve(publisher, for: manifest.id)
            try load(manifest)
            message = "Extension enabled."
        } catch { message = error.localizedDescription }
    }

    func choosePackage() {
        let panel = NSOpenPanel()
        panel.title = "Install Boring Notch Extension"
        panel.allowedContentTypes = [UTType(importedAs: "theboringteam.bnplugin", conformingTo: .bundle)]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { install(from: url) }
    }

    func install(from source: URL) {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        do {
            let (manifest, _) = try ExtensionPackage.inspect(source)
            try ExtensionPackage.verifySignature(at: source)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = packageURL(manifest.id)
            guard source.standardizedFileURL != destination.standardizedFileURL else { return }
            let staging = directory.appendingPathComponent("\(UUID().uuidString).bnplugin")
            defer { try? FileManager.default.removeItem(at: staging) }
            try FileManager.default.copyItem(at: source, to: staging)
            let (stagedManifest, _) = try ExtensionPackage.inspect(staging)
            guard stagedManifest == manifest else { throw ExtensionError.invalidPackage }
            let publisher = try ExtensionPackage.verifySignature(at: staging)
            guard approvePublisher(publisher, manifest: manifest) else { return }
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
            } else {
                try FileManager.default.moveItem(at: staging, to: destination)
            }
            ExtensionTrustStore.approve(publisher, for: manifest.id)
            refresh()
            if loadedIDs.contains(manifest.id) {
                needsRestart = true
                message = "Extension updated. Restart Boring Notch to use the new version."
            } else {
                try load(manifest)
                message = "Extension installed."
            }
        } catch { message = error.localizedDescription }
    }

    func remove(_ manifest: ExtensionManifest) {
        do {
            try FileManager.default.trashItem(at: packageURL(manifest.id), resultingItemURL: nil)
            settingsControllers.removeValue(forKey: manifest.id)
            runtimes.removeValue(forKey: manifest.id)?.stop()
            ExtensionTrustStore.remove(manifest.id)
            inactiveIDs.remove(manifest.id)
            artworkDisabled.remove(manifest.id)
            setLockedNotchRequested(false, for: manifest.id)
            refresh()
            message = "Extension moved to Trash."
        } catch { message = error.localizedDescription }
    }

    private func packageURL(_ id: String) -> URL { directory.appendingPathComponent("\(id).bnplugin") }

    private func refresh() {
        installed = ((try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: nil)) ?? []).compactMap { url in
                guard let (manifest, _) = try? ExtensionPackage.inspect(url),
                      url.lastPathComponent == "\(manifest.id).bnplugin" else { return nil }
                return manifest
            }.sorted { $0.name < $1.name }
    }

    func stop() {
        subscriptions.removeAll()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        settingsControllers.removeAll()
        runtimes.values.forEach { $0.stop() }
        runtimes.removeAll()
        inactiveIDs.removeAll()
        artworkDisabled.removeAll()
        lockedNotchIDs.removeAll()
        requestsLockedNotch = false
        artwork = nil
        lastArtwork = nil
    }
}
