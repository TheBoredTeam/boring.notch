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

    private var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
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
        ExtensionLicenseStore.shared.$licensedProducts
            .dropFirst()
            .receive(on: DispatchQueue.main)
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
                    self?.send(event: event)
                }
            })
        }
    }

    func setScreenLocked(_ value: Bool) {
        locked = value
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
                guard ExtensionLicenseStore.shared.licensedProducts.contains(productID) else { return }
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
        publishSnapshot()
        runtime.send(event: locked ? "lock" : "unlock")
        runtime.send(event: awake ? "wake" : "sleep")
        runtime.send(event: sessionActive ? "session-active" : "session-inactive")
    }

    private func publishSnapshot() {
        guard !runtimes.isEmpty else { return }
        let music = MusicManager.shared
        if lastArtwork !== music.albumArt {
            lastArtwork = music.albumArt
            let image = NSImage(size: NSSize(width: 600, height: 600))
            image.lockFocus()
            music.albumArt.draw(in: NSRect(x: 0, y: 0, width: 600, height: 600))
            image.unlockFocus()
            artwork = image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))?
                .representation(using: .jpeg, properties: [.compressionFactor: 0.85])?.base64EncodedString()
        }
        let snapshot: [String: Any] = [
            "title": music.songTitle, "artist": music.artistName, "album": music.album,
            "duration": music.songDuration, "elapsed": music.estimatedPlaybackPosition(),
            "timestamp": Date().timeIntervalSince1970, "rate": music.playbackRate,
            "playing": music.isPlaying, "idle": music.isPlayerIdle,
            "artwork": artwork ?? "", "favorite": music.isFavoriteTrack,
            "canFavorite": music.canFavoriteTrack
        ]
        for (id, runtime) in runtimes {
            var licensedSnapshot = snapshot
            licensedSnapshot["licensed"] = ExtensionLicenseStore.shared.licensedProducts.contains(id)
            if let data = try? JSONSerialization.data(withJSONObject: licensedSnapshot) { runtime.send(snapshot: data) }
        }
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
            _ = try ExtensionPackage.inspect(staging)
            try ExtensionPackage.verifySignature(at: staging)
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
            } else {
                try FileManager.default.moveItem(at: staging, to: destination)
            }
            refresh()
            if loadedIDs.contains(manifest.id) {
                needsRestart = true
                message = "Extension updated. Restart Boring Notch to use the new version."
            } else {
                try load(manifest)
                message = "Extension installed. Open its settings to activate it."
            }
        } catch { message = error.localizedDescription }
    }

    func remove(_ manifest: ExtensionManifest) {
        do {
            try FileManager.default.trashItem(at: packageURL(manifest.id), resultingItemURL: nil)
            settingsControllers.removeValue(forKey: manifest.id)
            runtimes.removeValue(forKey: manifest.id)?.stop()
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
        ExtensionLicenseStore.shared.stop()
        subscriptions.removeAll()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        settingsControllers.removeAll()
        runtimes.values.forEach { $0.stop() }
        runtimes.removeAll()
    }
}
