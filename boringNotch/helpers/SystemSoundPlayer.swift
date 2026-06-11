//
//  SystemSoundPlayer.swift
//  boringNotch
//

import AppKit
import Foundation

enum SystemSoundPlayer {
    private static var currentlyPlaying: NSSound?

    private static let supportedExtensions = ["aiff", "aif", "caf", "wav"]
    private static let systemSoundsDirectory = URL(fileURLWithPath: "/System/Library/Sounds")
    private static let userSoundsDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Sounds", isDirectory: true)

    static let defaultSoundName = "Glass"

    static func availableSoundNames() -> [String] {
        var names = Set<String>()

        for directory in soundDirectories() {
            guard
                let files = try? FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: nil
                )
            else { continue }

            for file in files {
                guard supportedExtensions.contains(file.pathExtension.lowercased()) else { continue }
                names.insert(file.deletingPathExtension().lastPathComponent)
            }
        }

        if names.isEmpty {
            return [defaultSoundName]
        }

        return names.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    static func resolvedSoundName(_ preferred: String) -> String {
        let sounds = availableSoundNames()
        if sounds.contains(preferred) {
            return preferred
        }
        if sounds.contains(defaultSoundName) {
            return defaultSoundName
        }
        return sounds.first ?? defaultSoundName
    }

    static func play(soundName: String) {
        currentlyPlaying?.stop()
        currentlyPlaying = nil

        let resolved = resolvedSoundName(soundName)

        if let sound = NSSound(named: NSSound.Name(resolved)) {
            currentlyPlaying = sound
            sound.play()
            return
        }

        if let url = url(for: resolved), let sound = NSSound(contentsOf: url, byReference: true) {
            currentlyPlaying = sound
            sound.play()
            return
        }

        NSSound.beep()
    }

    static func openSoundSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Sound-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.sound",
        ]

        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    private static func soundDirectories() -> [URL] {
        [systemSoundsDirectory, userSoundsDirectory]
    }

    private static func url(for soundName: String) -> URL? {
        for directory in soundDirectories() {
            for ext in supportedExtensions {
                let candidate = directory.appendingPathComponent("\(soundName).\(ext)")
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }
        return nil
    }
}
