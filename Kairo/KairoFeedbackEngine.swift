//
//  KairoFeedbackEngine.swift
//  Kairo — Real-time voice feedback for every action
//
//  Like Alexa/Siri — never silent, always confirms.
//  Speak + show in pill simultaneously.
//

import AVFoundation
import Foundation
import SwiftUI

// ═══════════════════════════════════════════
// MARK: - Feedback Engine
// ═══════════════════════════════════════════

class KairoFeedbackEngine: ObservableObject {
    static let shared = KairoFeedbackEngine()

    @Published var currentText: String = ""
    @Published var isSpeaking: Bool = false

    private var currentPlayer: AVAudioPlayer?
    private var speechSynth: NSSpeechSynthesizer?
    private let queue = DispatchQueue(label: "kairo.feedback", qos: .userInitiated)

    enum FeedbackPriority: Int, Comparable {
        case low = 0, normal = 1, high = 2, urgent = 3
        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    // MARK: - Speak + Show in Pill

    /// Main feedback method — shows in pill, only speaks when speak=true
    func say(_ text: String, pillText: String? = nil, priority: FeedbackPriority = .normal, speak: Bool = false) {
        let display = pillText ?? text

        DispatchQueue.main.async {
            self.currentText = display
            self.isSpeaking = speak

            NotificationCenter.default.post(
                name: .kairoFeedback,
                object: nil,
                userInfo: ["text": display, "duration": Double(text.count) * 0.055 + 1.5]
            )
        }

        if speak {
            self.speak(text)
        }
    }

    /// Quick pill-only flash — no voice
    func flash(_ text: String, duration: Double = 2.0) {
        DispatchQueue.main.async {
            self.currentText = text
            NotificationCenter.default.post(
                name: .kairoFeedback,
                object: nil,
                userInfo: ["text": text, "duration": duration]
            )

            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                if self.currentText == text {
                    self.currentText = ""
                }
            }
        }
    }

    // MARK: - TTS

    func speak(_ text: String) {
        // Cancel current speech
        currentPlayer?.stop()
        speechSynth?.stopSpeaking()

        Task {
            await speakWithElevenLabs(text)
        }
    }

    private func speakWithElevenLabs(_ text: String) async {
        let apiKey = ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"] ?? ""
        let voiceID = ProcessInfo.processInfo.environment["ELEVENLABS_VOICE_ID"]
            ?? "QR57ghQmWinyEbqmRLVI"  // Adam — deep male

        guard !apiKey.isEmpty,
              let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)/stream")
        else {
            speakSystem(text)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_turbo_v2_5",
            "voice_settings": [
                "stability": 0.65,
                "similarity_boost": 0.85,
                "style": 0.1,
                "use_speaker_boost": true,
            ],
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            // Check for valid audio response
            let httpResponse = response as? HTTPURLResponse
            guard httpResponse?.statusCode == 200, !data.isEmpty else {
                speakSystem(text)
                return
            }

            // Save and play
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("kairo_feedback_\(UUID().uuidString).mp3")
            try data.write(to: tempURL)

            await MainActor.run {
                self.currentPlayer = try? AVAudioPlayer(contentsOf: tempURL)
                self.currentPlayer?.volume = 1.0
                self.currentPlayer?.play()

                // Clean up after playback
                let duration = self.currentPlayer?.duration ?? 3.0
                DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.5) {
                    self.isSpeaking = false
                    try? FileManager.default.removeItem(at: tempURL)
                }
            }
        } catch {
            print("[KairoFeedback] ElevenLabs failed: \(error)")
            speakSystem(text)
        }
    }

    /// Play pre-fetched audio data (e.g. from backend /welcome or /agent endpoints)
    func playAudioData(_ data: Data) {
        currentPlayer?.stop()
        speechSynth?.stopSpeaking()

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("kairo_remote_\(UUID().uuidString).mp3")
        do {
            try data.write(to: tempURL)
            currentPlayer = try AVAudioPlayer(contentsOf: tempURL)
            currentPlayer?.volume = 1.0
            currentPlayer?.play()

            let duration = currentPlayer?.duration ?? 5.0
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.5) {
                self.isSpeaking = false
                try? FileManager.default.removeItem(at: tempURL)
            }
        } catch {
            print("[KairoFeedback] Failed to play audio data: \(error)")
        }
    }

    /// System TTS fallback
    func speakSystem(_ text: String) {
        DispatchQueue.main.async {
            self.speechSynth = NSSpeechSynthesizer()
            // Use Daniel voice — closest to Kairo
            self.speechSynth?.setVoice(
                NSSpeechSynthesizer.VoiceName(rawValue: "com.apple.speech.synthesis.voice.daniel")
            )
            self.speechSynth?.startSpeaking(text)

            // Estimate duration and clear
            let wordCount = text.components(separatedBy: " ").count
            let estimatedDuration = Double(wordCount) * 0.4 + 1.0
            DispatchQueue.main.asyncAfter(deadline: .now() + estimatedDuration) {
                self.isSpeaking = false
            }
        }
    }
}

// ═══════════════════════════════════════════
// MARK: - Shorthand Global Access
// ═══════════════════════════════════════════

/// Global shorthand — use `Kairo.say("...")` anywhere
let KairoFeedback = KairoFeedbackEngine.shared

// ═══════════════════════════════════════════
// MARK: - Notification Extension
// ═══════════════════════════════════════════

extension Notification.Name {
    static let kairoFeedback = Notification.Name("kairoFeedback")
}
