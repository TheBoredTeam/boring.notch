//
//  AgentCompletionSound.swift
//  boringCode
//
//  Som sutil quando um agente termina o que estava fazendo. Usa os sons do
//  sistema, como o NotificationSoundService do Open Island
//  (github.com/Octane0411/open-vibe-island), GPL-3.0 — só que em volume baixo.
//

import AppKit
import Defaults

@MainActor
enum AgentCompletionSound {
    /// Baixo de propósito: é um aviso, não um alarme.
    static let volume: Float = 0.35

    static var availableSounds: [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? []
        return files.filter { $0.hasSuffix(".aiff") }.map { ($0 as NSString).deletingPathExtension }.sorted()
    }

    static func play() {
        guard Defaults[.agentsEnabled], Defaults[.agentsCompletionSound] else { return }
        preview(Defaults[.agentsCompletionSoundName])
    }

    static func preview(_ name: String) {
        guard let sound = NSSound(named: NSSound.Name(name))?.copy() as? NSSound else { return }
        sound.volume = volume
        sound.play()
    }
}
