//
//  ExtensionRuntime.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import AppKit

/// C ABI keeps private extensions independent of the app's Swift module and compiler ABI.
/// All calls, including the command callback, run on the main thread.
@MainActor
final class ExtensionRuntime {
    typealias Command = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Double) -> Void
    typealias Create = @convention(c) (UnsafeMutableRawPointer?, Command) -> UnsafeMutableRawPointer?
    typealias Destroy = @convention(c) (UnsafeMutableRawPointer) -> Void
    typealias Update = @convention(c) (UnsafeMutableRawPointer, UnsafePointer<UInt8>, Int) -> Void
    typealias Event = @convention(c) (UnsafeMutableRawPointer, UnsafePointer<CChar>) -> Void
    typealias Settings = @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?

    let manifest: ExtensionManifest
    private let handle: UnsafeMutableRawPointer
    private let commandContext: NSString
    private var instance: UnsafeMutableRawPointer?
    private let destroy: Destroy
    private let update: Update
    private let event: Event
    private let settings: Settings

    init(url: URL, command: Command) throws {
        let (manifest, executable) = try ExtensionPackage.inspect(url)
        try ExtensionPackage.verifySignature(at: url)
        guard let handle = dlopen(executable.path, RTLD_NOW | RTLD_LOCAL) else {
            throw ExtensionError.incompatibleBinary
        }
        // Do not dlclose Swift code: its metadata can outlive plugin instances in the runtime.
        self.handle = handle
        self.manifest = manifest
        self.commandContext = manifest.id as NSString
        func symbol<T>(_ name: String, _: T.Type) throws -> T {
            guard let address = dlsym(handle, name) else { throw ExtensionError.incompatibleBinary }
            return unsafeBitCast(address, to: T.self)
        }
        let create = try symbol("bn_extension_create_v1", Create.self)
        destroy = try symbol("bn_extension_destroy_v1", Destroy.self)
        update = try symbol("bn_extension_update_v1", Update.self)
        event = try symbol("bn_extension_event_v1", Event.self)
        settings = try symbol("bn_extension_settings_v1", Settings.self)
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

    func stop() {
        guard let instance else { return }
        destroy(instance)
        self.instance = nil
    }
}
