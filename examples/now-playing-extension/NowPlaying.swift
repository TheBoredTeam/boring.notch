// SPDX-License-Identifier: GPL-3.0-only
// Minimal free extension. No product, payment service, or activation code is needed.
import AppKit
import SwiftUI

public typealias HostCommand = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Double) -> Void

@MainActor
final class NowPlaying: ObservableObject {
    struct Snapshot: Decodable {
        var title: String
        var artist: String
        var playing: Bool
    }
    @Published var track = Snapshot(title: "Nothing playing", artist: "Start music in your favorite player", playing: false)
    private let context: UnsafeMutableRawPointer?
    private let command: HostCommand
    private var configured = false
    private var settings: NSHostingController<AnyView>?
    init(context: UnsafeMutableRawPointer?, command: @escaping HostCommand) {
        self.context = context
        self.command = command
    }
    func update(_ data: Data) {
        guard let value = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        track = value
        if !configured {
            configured = true // Set before callbacks; the host may publish synchronously.
            "presentation.artwork".withCString { command(context, $0, 0) }
        }
    }
    func togglePlayback() { "media.toggle".withCString { command(context, $0, 0) } }
    var settingsController: NSViewController {
        if let settings { return settings }
        let controller = NSHostingController(rootView: AnyView(NowPlayingSettings(plugin: self)))
        controller.preferredContentSize = NSSize(width: 500, height: 200)
        settings = controller
        return controller
    }
    func stop() {
        settings?.rootView = AnyView(EmptyView())
        settings = nil
    }
}

private struct NowPlayingSettings: View {
    @ObservedObject var plugin: NowPlaying
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(plugin.track.title).font(.title2).lineLimit(2)
            Text(plugin.track.artist).foregroundStyle(.secondary).lineLimit(1)
            Button(plugin.track.playing ? "Pause" : "Play", action: plugin.togglePlayback)
            Text("A free example extension for Boring Notch.").font(.caption).foregroundStyle(.secondary)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
    }
}

@_cdecl("bn_extension_create_v1")
public func create(_ context: UnsafeMutableRawPointer?, _ command: @escaping HostCommand) -> UnsafeMutableRawPointer? {
    guard Thread.isMainThread else { return nil }
    var pointer: UnsafeMutableRawPointer?
    MainActor.assumeIsolated { pointer = Unmanaged.passRetained(NowPlaying(context: context, command: command)).toOpaque() }
    return pointer
}
@_cdecl("bn_extension_destroy_v1")
public func destroy(_ pointer: UnsafeMutableRawPointer) {
    guard Thread.isMainThread else { return }
    MainActor.assumeIsolated { Unmanaged<NowPlaying>.fromOpaque(pointer).takeRetainedValue().stop() }
}
@_cdecl("bn_extension_update_v1")
public func update(_ pointer: UnsafeMutableRawPointer, _ bytes: UnsafePointer<UInt8>, _ count: Int) {
    guard Thread.isMainThread, count > 0, count <= 4_000_000 else { return }
    MainActor.assumeIsolated { Unmanaged<NowPlaying>.fromOpaque(pointer).takeUnretainedValue().update(Data(bytes: bytes, count: count)) }
}
@_cdecl("bn_extension_event_v1")
public func event(_ pointer: UnsafeMutableRawPointer, _ name: UnsafePointer<CChar>) {
    // This example owns no windows or timers. Extensions that do should release
    // hidden work on sleep/session-inactive and react to lock/unlock as needed.
}
@_cdecl("bn_extension_settings_v1")
public func settings(_ pointer: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? {
    guard Thread.isMainThread else { return nil }
    var controller: UnsafeMutableRawPointer?
    MainActor.assumeIsolated {
        controller = Unmanaged.passUnretained(Unmanaged<NowPlaying>.fromOpaque(pointer).takeUnretainedValue().settingsController).toOpaque()
    }
    return controller
}
