// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

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
    @Published private(set) var isInstalling = false
    @Published private(set) var enabledIDs = Set<String>()

    private var runtimes: [String: ExtensionRuntime] = [:]
    private var subscriptions = Set<AnyCancellable>()
    private var workspaceObservers: [NSObjectProtocol] = []
    private var locked = false
    private var awake = true
    private var sessionActive = true
    private var artwork: String?
    private var lastArtwork: NSImage?
    private var started = false
    private var restartIDs = Set<String>()
    // Retired contexts stay alive so late cooperative callbacks can be rejected
    // by identity without dereferencing freed memory. Swift code stays loaded.
    private var retiredRuntimes: [ExtensionRuntime] = []
    private var activityRegistrations: [String: [String: NotchActivityRegistration]] = [:]
    private var activityValues: [String: [String: ExtensionActivityDescriptor]] = [:]
    private enum Contribution: Hashable { case activities, tabs }
    private struct PendingContribution: Hashable {
        let providerID: String
        let kind: Contribution
    }
    private var pendingContributionUpdates = Set<PendingContribution>()
    private var disabledIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "disabledExtensions") ?? []) }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: "disabledExtensions") }
    }
    private var artworkDisabled = Set<String>()
    private var inactiveIDs = Set<String>()

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
        for manifest in installed where !disabledIDs.contains(manifest.id) {
            do { try load(manifest) } catch { report(error) }
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
                    case "wake":
                        self?.awake = true
                        LiveActivityCenter.shared.updateSession(awake: true)
                    case "sleep":
                        self?.awake = false
                        LiveActivityCenter.shared.updateSession(awake: false)
                    case "session-active":
                        self?.sessionActive = true
                        LiveActivityCenter.shared.updateSession(active: true)
                    case "session-inactive":
                        self?.sessionActive = false
                        LiveActivityCenter.shared.updateSession(active: false)
                    default: break
                    }
                    self?.publishSnapshot(force: true)
                    self?.send(event: event)
                }
            })
        }
    }

    func setScreenLocked(_ value: Bool) {
        locked = value
        if value {
            LiveActivityCenter.shared.updateSession(locked: true)
            publishSnapshot(force: true)
            send(event: "lock")
        } else {
            // Providers may capture their own visible region for an independent
            // exit animation. Keep the secure surface alive through this call.
            send(event: "unlock")
            LiveActivityCenter.shared.updateSession(locked: false)
            publishSnapshot(force: true)
        }
    }

    private func send(event: String) {
        runtimes.values.forEach { $0.send(event: event) }
    }

    private func load(_ manifest: ExtensionManifest) throws {
        guard runtimes[manifest.id] == nil else { return }
        guard !restartIDs.contains(manifest.id) else { throw ExtensionError.restartRequired }
        let runtime = try ExtensionRuntime(url: packageURL(manifest.id)) { context, command, value in
            guard Thread.isMainThread, let context, let command else { return }
            let name = String(cString: command)
            MainActor.assumeIsolated {
                let manager = ExtensionManager.shared
                guard let runtime = manager.runtimes.values.first(where: { $0.ownsCommandContext(context) }),
                      value.isFinite else { return }
                let productID = runtime.manifest.id
                if name == "activities.changed" {
                    manager.scheduleContributionUpdate(.activities, for: productID)
                    return
                }
                if name == "tabs.changed" {
                    manager.scheduleContributionUpdate(.tabs, for: productID)
                    return
                }
                if name == "presentation.artwork" {
                    manager.setArtworkRequested(value > 0, for: productID)
                    return
                }
                if name == "presentation.active" {
                    manager.setActive(value > 0, for: productID)
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
        runtimes[manifest.id] = runtime
        enabledIDs.insert(manifest.id)
        settingsControllers[manifest.id] = runtime.settingsController()
        publishSnapshot(force: true)
        // Establish restrictive session gates before the first lock event so a
        // re-enabled provider cannot briefly show while asleep or inactive.
        runtime.send(event: awake ? "wake" : "sleep")
        runtime.send(event: sessionActive ? "session-active" : "session-inactive")
        runtime.send(event: locked ? "lock" : "unlock")
        scheduleContributionUpdate(.activities, for: manifest.id)
        scheduleContributionUpdate(.tabs, for: manifest.id)
    }

    private func publishSnapshot(force: Bool = false) {
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
            let presentationAllowed = runtime.manifest.receivesUpdates(
                locked: locked, awake: awake, sessionActive: sessionActive, requested: !inactiveIDs.contains(id))
            extensionSnapshot["presentationAllowed"] = presentationAllowed
            extensionSnapshot["activitySurfaces"] = LiveActivitySurface.allCases.map(\.rawValue)
            if artworkDisabled.contains(id) || !presentationAllowed {
                extensionSnapshot["artwork"] = ""
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
        guard !isInstalling else { return }
        do {
            let publisher = try ExtensionPackage.verifySignature(at: packageURL(manifest.id))
            guard approvePublisher(publisher, manifest: manifest) else { return }
            ExtensionTrustStore.approve(publisher, for: manifest.id)
            try load(manifest)
            disabledIDs.remove(manifest.id)
            message = "Extension enabled."
        } catch { report(error) }
    }

    func choosePackage() {
        let panel = NSOpenPanel()
        panel.title = "Install Boring Notch Extension"
        panel.allowedContentTypes = [UTType(importedAs: "theboringteam.bnplugin", conformingTo: .bundle), .zip]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { install(from: url) }
    }

    func install(
        from source: URL,
        expected: ExtensionInstallation.Requirement? = nil,
        completion: @escaping @MainActor () -> Void = {}
    ) {
        guard !isInstalling else {
            message = "Another extension is being installed. Try again when it finishes."
            completion()
            return
        }
        isInstalling = true
        message = nil
        let access = source.startAccessingSecurityScopedResource()
        let destinationDirectory = directory
        Task {
            defer {
                if access { source.stopAccessingSecurityScopedResource() }
                isInstalling = false
                completion()
            }
            do {
                // Keep extraction, copying and signature checks off the UI thread.
                let staged = try await Task.detached(priority: .userInitiated) {
                    try ExtensionInstallation.stage(source: source, directory: destinationDirectory, expected: expected)
                }.value
                defer { staged.cleanup() }
                try installStaged(staged)
            } catch { report(error) }
        }
    }

    private func installStaged(_ staged: ExtensionInstallation.StagedPackage) throws {
        let manifest = staged.manifest
        let publisher = staged.publisher
        let destination = packageURL(manifest.id)
        guard approvePublisher(publisher, manifest: manifest) else { return }
        let wasLoaded = runtimes[manifest.id] != nil || retiredRuntimes.contains { $0.manifest.id == manifest.id }
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: staged.url)
        } else {
            try FileManager.default.moveItem(at: staged.url, to: destination)
        }
        ExtensionTrustStore.approve(publisher, for: manifest.id)
        disabledIDs.remove(manifest.id)
        refresh()
        if wasLoaded {
            stopRuntime(manifest.id)
            restartIDs.insert(manifest.id)
            needsRestart = true
            message = "Extension updated. Restart Boring Notch to use the new version."
        } else {
            try load(manifest)
            message = "Extension installed."
        }
    }

    func disable(_ manifest: ExtensionManifest) {
        guard !isInstalling else { return }
        disabledIDs.insert(manifest.id)
        stopRuntime(manifest.id)
        message = "Extension disabled."
    }

    func remove(_ manifest: ExtensionManifest) {
        guard !isInstalling else { return }
        do {
            try FileManager.default.trashItem(at: packageURL(manifest.id), resultingItemURL: nil)
            stopRuntime(manifest.id)
            ExtensionTrustStore.remove(manifest.id)
            disabledIDs.remove(manifest.id)
            refresh()
            message = "Extension moved to Trash."
        } catch { message = error.localizedDescription }
    }

    private func scheduleContributionUpdate(_ kind: Contribution, for id: String) {
        let contribution = PendingContribution(providerID: id, kind: kind)
        guard pendingContributionUpdates.insert(contribution).inserted else { return }
        // Commands can originate during an ABI call. Reconcile after it returns
        // to avoid reentrant lifecycle mutation and to coalesce bursts of updates.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingContributionUpdates.remove(contribution)
            switch kind {
            case .activities: self.reconcileActivities(for: id)
            case .tabs: self.reconcileTabs(for: id)
            }
        }
    }

    private func reconcileTabs(for id: String) {
        guard let runtime = runtimes[id] else { return }
        do {
            let snapshot = try runtime.tabSnapshot()
            ExtensionTabRegistry.shared.replace(providerID: id, tabs: snapshot.tabs, runtime: runtime)
        } catch {
            ExtensionTabRegistry.shared.remove(providerID: id)
            message = "\(runtime.manifest.name) published invalid tabs."
        }
    }

    private func reconcileActivities(for id: String) {
        guard let runtime = runtimes[id] else { return }
        do {
            let snapshot = try runtime.activitySnapshot()
            let next = Dictionary(uniqueKeysWithValues: snapshot.activities.map { ($0.id, $0) })
            var registrations = activityRegistrations[id] ?? [:]
            for localID in Array(registrations.keys) where next[localID] == nil {
                registrations.removeValue(forKey: localID)?.unregister()
            }
            for value in snapshot.activities {
                let activity = ExtensionNotchActivity(value: value, runtime: runtime)
                if let registration = registrations[value.id] {
                    if activityValues[id]?[value.id] != value { try registration.update(activity) }
                } else {
                    registrations[value.id] = try LiveActivityCenter.shared.register(activity)
                }
            }
            activityRegistrations[id] = registrations
            activityValues[id] = next
        } catch {
            // Invalid publication withdraws this provider's content; other
            // providers and the extension's own settings remain usable.
            clearActivities(for: id)
            message = "\(runtime.manifest.name) published an invalid live activity."
        }
    }

    private func clearActivities(for id: String) {
        activityRegistrations.removeValue(forKey: id)?.values.forEach { $0.unregister() }
        activityValues.removeValue(forKey: id)
    }

    private func stopRuntime(_ id: String) {
        clearActivities(for: id)
        ExtensionTabRegistry.shared.remove(providerID: id)
        pendingContributionUpdates = pendingContributionUpdates.filter { $0.providerID != id }
        settingsControllers.removeValue(forKey: id)
        enabledIDs.remove(id)
        inactiveIDs.remove(id)
        artworkDisabled.remove(id)
        if let runtime = runtimes.removeValue(forKey: id) {
            runtime.stop()
            retiredRuntimes.append(runtime)
        }
    }

    private func packageURL(_ id: String) -> URL { directory.appendingPathComponent("\(id).bnplugin") }

    private func report(_ error: Error) {
        if case ExtensionError.restartRequired = error { needsRestart = true }
        message = error.localizedDescription
    }

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
        for id in Array(runtimes.keys) { stopRuntime(id) }
        inactiveIDs.removeAll()
        artworkDisabled.removeAll()
        started = false
        artwork = nil
        lastArtwork = nil
    }
}
