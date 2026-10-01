// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

//
//  ExtensionRuntime.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import AppKit

private final class ExtensionCommandContext: NSObject {
    let id: String
    init(id: String) { self.id = id }
}

/// C ABI keeps extensions independent of the app's Swift module and compiler ABI.
/// All calls, including the command callback, run on the main thread.
@MainActor
final class ExtensionRuntime {
    // dyld can return a previously loaded image for a replaced path. Pin the
    // signed identity even when symbol resolution or instance creation fails.
    private static var loadedCodeHashes: [URL: Data] = [:]
    // Keep tiny callback identities unique even if create fails after retaining
    // a callback. The loader cannot safely unload the associated code either.
    private static var commandContexts: [ExtensionCommandContext] = []
    typealias Command = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Double) -> Void
    typealias Create = @convention(c) (UnsafeMutableRawPointer?, Command) -> UnsafeMutableRawPointer?
    typealias Destroy = @convention(c) (UnsafeMutableRawPointer) -> Void
    typealias Update = @convention(c) (UnsafeMutableRawPointer, UnsafePointer<UInt8>, Int) -> Void
    typealias Event = @convention(c) (UnsafeMutableRawPointer, UnsafePointer<CChar>) -> Void
    typealias Settings = @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?
    typealias Activities = @convention(c) (UnsafeMutableRawPointer) -> UnsafePointer<CChar>?
    typealias ActivityView = @convention(c) (
        UnsafeMutableRawPointer, UnsafePointer<CChar>, Int32, UnsafePointer<CChar>?
    ) -> UnsafeMutableRawPointer?
    typealias TabView = @convention(c) (
        UnsafeMutableRawPointer, UnsafePointer<CChar>, UnsafePointer<CChar>?
    ) -> UnsafeMutableRawPointer?
    typealias TabViewV2 = @convention(c) (
        UnsafeMutableRawPointer, UnsafePointer<CChar>, UnsafePointer<CChar>
    ) -> UnsafeMutableRawPointer?

    let manifest: ExtensionManifest
    private let handle: UnsafeMutableRawPointer
    private let commandContext: ExtensionCommandContext
    private var instance: UnsafeMutableRawPointer?
    private let destroy: Destroy
    private let update: Update
    private let event: Event
    private let settings: Settings
    private let activities: Activities?
    private let activityView: ActivityView?
    private let tabs: Activities?
    private let tabView: TabView?
    private let tabViewV2: TabViewV2?

    init(url: URL, command: Command) throws {
        let (manifest, executable) = try ExtensionPackage.inspect(url)
        let publisher = try ExtensionPackage.verifySignature(at: url)
        guard ExtensionTrustStore.isApproved(publisher, for: manifest.id) else { throw ExtensionError.unapprovedPublisher }
        guard let codeHash = publisher.codeHash else { throw ExtensionError.untrustedSignature }
        let packageURL = url.standardizedFileURL.resolvingSymlinksInPath()
        if let loadedHash = Self.loadedCodeHashes[packageURL], loadedHash != codeHash {
            throw ExtensionError.restartRequired
        }
        guard let handle = dlopen(executable.path, RTLD_NOW | RTLD_LOCAL) else {
            throw ExtensionError.incompatibleBinary
        }
        Self.loadedCodeHashes[packageURL] = codeHash
        // Do not dlclose Swift code: its metadata can outlive plugin instances in the runtime.
        self.handle = handle
        self.manifest = manifest
        self.commandContext = ExtensionCommandContext(id: manifest.id)
        func symbol<T>(_ name: String, _: T.Type) throws -> T {
            guard let address = dlsym(handle, name) else { throw ExtensionError.incompatibleBinary }
            return unsafeBitCast(address, to: T.self)
        }
        func optionalSymbol<T>(_ name: String, _: T.Type) -> T? {
            guard let address = dlsym(handle, name) else { return nil }
            return unsafeBitCast(address, to: T.self)
        }
        let create = try symbol("bn_extension_create_v1", Create.self)
        destroy = try symbol("bn_extension_destroy_v1", Destroy.self)
        update = try symbol("bn_extension_update_v1", Update.self)
        event = try symbol("bn_extension_event_v1", Event.self)
        settings = try symbol("bn_extension_settings_v1", Settings.self)
        if manifest.capabilities?.contains("liveActivities") == true {
            activities = try symbol("bn_extension_activities_v1", Activities.self)
            activityView = try symbol("bn_extension_activity_view_v1", ActivityView.self)
        } else {
            activities = nil
            activityView = nil
        }
        if manifest.capabilities?.contains("tabs") == true {
            tabs = try symbol("bn_extension_tabs_v1", Activities.self)
            tabView = optionalSymbol("bn_extension_tab_view_v1", TabView.self)
            tabViewV2 = optionalSymbol("bn_extension_tab_view_v2", TabViewV2.self)
            guard tabView != nil || tabViewV2 != nil else { throw ExtensionError.incompatibleBinary }
        } else {
            tabs = nil
            tabView = nil
            tabViewV2 = nil
        }
        Self.commandContexts.append(commandContext)
        guard let instance = create(Unmanaged.passUnretained(commandContext).toOpaque(), command) else {
            throw ExtensionError.incompatibleBinary
        }
        self.instance = instance
    }

    func send(snapshot: Data) {
        guard let instance else { return }
        snapshot.withUnsafeBytes { bytes in
            guard let address = bytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            update(instance, address, bytes.count)
        }
    }

    func send(event name: String) {
        guard let instance else { return }
        name.withCString { event(instance, $0) }
    }

    func settingsController() -> NSViewController? {
        guard let instance, let pointer = settings(instance) else { return nil }
        return Unmanaged<NSViewController>.fromOpaque(pointer).takeUnretainedValue()
    }

    func ownsCommandContext(_ pointer: UnsafeMutableRawPointer) -> Bool {
        instance != nil && Unmanaged.passUnretained(commandContext).toOpaque() == pointer
    }

    func activitySnapshot() throws -> ExtensionActivitySnapshot {
        guard let instance, let activities else { return ExtensionActivitySnapshot(activities: []) }
        let snapshot: ExtensionActivitySnapshot = try decodeSnapshot(activities(instance))
        try snapshot.validate()
        return snapshot
    }

    func tabSnapshot() throws -> ExtensionTabSnapshot {
        guard let instance, let tabs else { return ExtensionTabSnapshot(tabs: []) }
        let snapshot: ExtensionTabSnapshot = try decodeSnapshot(tabs(instance))
        try snapshot.validate()
        return snapshot
    }

    private func decodeSnapshot<Snapshot: Decodable>(_ pointer: UnsafePointer<CChar>?) throws -> Snapshot {
        guard let pointer else { throw ExtensionError.invalidPackage }
        let maximumBytes = 65_536
        let count = strnlen(pointer, maximumBytes + 1)
        guard count <= maximumBytes else { throw ExtensionError.invalidPackage }
        return try JSONDecoder().decode(Snapshot.self, from: Data(bytes: pointer, count: count))
    }

    func activityController(id: String, region: Int32, displayID: String?) -> NSViewController? {
        guard let instance, let activityView else { return nil }
        let pointer = id.withCString { activityID in
            if let displayID {
                return displayID.withCString { activityView(instance, activityID, region, $0) }
            }
            return activityView(instance, activityID, region, nil)
        }
        guard let pointer else { return nil }
        // Each call creates an independently owned controller; two display
        // windows must never try to reparent the same AppKit view.
        return Unmanaged<NSViewController>.fromOpaque(pointer).takeRetainedValue()
    }

    func supportsTabPresentation(_ presentation: ExtensionTabPresentation) -> Bool {
        guard instance != nil else { return false }
        return tabViewV2 != nil || (presentation == .regular && tabView != nil)
    }

    func tabController(id: String, context: ExtensionTabLayoutContext) -> NSViewController? {
        guard let instance, context.isValid, supportsTabPresentation(context.presentation),
              let descriptor = try? tabSnapshot().tabs.first(where: { $0.id == id }),
              descriptor.supports(context.presentation) else { return nil }
        let pointer: UnsafeMutableRawPointer?
        if let tabViewV2 {
            guard let data = try? JSONEncoder().encode(context),
                  let json = String(data: data, encoding: .utf8) else { return nil }
            pointer = id.withCString { tabID in
                json.withCString { tabViewV2(instance, tabID, $0) }
            }
        } else if context.presentation == .regular, let tabView {
            pointer = id.withCString { tabID in
                if let displayID = context.displayID {
                    return displayID.withCString { tabView(instance, tabID, $0) }
                }
                return tabView(instance, tabID, nil)
            }
        } else {
            // A legacy renderer never receives a compact request, even if its
            // metadata incorrectly claims to support that presentation.
            return nil
        }
        guard let pointer else { return nil }
        return Unmanaged<NSViewController>.fromOpaque(pointer).takeRetainedValue()
    }

    func stop() {
        guard let instance else { return }
        self.instance = nil
        destroy(instance)
    }
}
