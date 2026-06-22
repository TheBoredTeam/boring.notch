//
//  LauncherManager.swift
//  boringNotch
//
//  Quick launcher: pin apps, folders, scripts, and files for one-click launch
//  from the notch. Items persist via Defaults; the app is non-sandboxed so it
//  launches them directly through NSWorkspace / a login shell.
//

import AppKit
import Defaults
import Foundation

struct LauncherItem: Codable, Defaults.Serializable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case app, folder, script, file
    }

    var id: UUID = UUID()
    var name: String
    var path: String
    var kind: Kind
}

@MainActor
enum LauncherManager {
    private static let scriptExtensions: Set<String> = [
        "sh", "command", "zsh", "bash", "py", "rb", "js", "pl", "swift"
    ]

    /// Classify a chosen URL so we know how to launch it later.
    static func makeItem(for url: URL) -> LauncherItem {
        let path = url.path
        let ext = url.pathExtension.lowercased()
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)

        let kind: LauncherItem.Kind
        if ext == "app" {
            kind = .app
        } else if isDir.boolValue {
            kind = .folder
        } else if scriptExtensions.contains(ext) {
            kind = .script
        } else {
            kind = .file
        }

        let name = ext == "app" ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent
        return LauncherItem(name: name, path: path, kind: kind)
    }

    static func launch(_ item: LauncherItem) {
        let url = URL(fileURLWithPath: item.path)
        guard FileManager.default.fileExists(atPath: item.path) else {
            NSSound(named: "Funk")?.play()
            return
        }

        switch item.kind {
        case .app:
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: url, configuration: config)
        case .folder, .file:
            NSWorkspace.shared.open(url)
        case .script:
            runInTerminal(url)
        }
    }

    /// Open a script in Terminal so its output is visible.
    private static func runInTerminal(_ url: URL) {
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url], withApplicationAt: terminal, configuration: config) { _, error in
            if let error {
                print("Launcher: failed to run script \(url.lastPathComponent): \(error)")
            }
        }
    }

    /// 32pt icon for a pinned item, from the file system.
    static func icon(for item: LauncherItem, size: CGFloat = 32) -> NSImage {
        let img = NSWorkspace.shared.icon(forFile: item.path)
        img.size = NSSize(width: size, height: size)
        return img
    }
}
