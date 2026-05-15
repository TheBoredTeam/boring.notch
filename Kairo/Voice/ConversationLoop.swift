import Foundation
import Speech

/// One-shot voice turn through the new Brain pipeline:
///
///   1. Pause wake word so it doesn't steal the mic
///   2. Begin Orbie presence (.listening) + caption-HUD optional
///   3. Start SFSpeechRecognizer; stop on silence or hard 8s cap
///   4. Send transcript to KairoBrain.handle (which may tool-loop)
///   5. Speak the reply via KairoTTSEngine
///   6. End presence + resume wake word
@MainActor
final class KairoConversationLoop {
    let wake: KairoWakeWord
    let recognizer: KairoSpeechRecognizer
    let brain: KairoBrain
    let tts: KairoTTSEngine

    private var inFlight: Task<Void, Never>?

    /// Hard cap on how long we listen before forcing a stop.
    private let maxListenSeconds: TimeInterval = 8.0

    /// Silence cap — stop listening if no new transcript text comes in for
    /// this long after the user has spoken at least one word.
    private let silenceTimeoutSeconds: TimeInterval = 1.2

    init(wake: KairoWakeWord, recognizer: KairoSpeechRecognizer, brain: KairoBrain, tts: KairoTTSEngine) {
        self.wake = wake
        self.recognizer = recognizer
        self.brain = brain
        self.tts = tts
        wake.onWake = { [weak self] in
            Task { @MainActor in self?.startTurn() }
        }
    }

    /// Begin a turn. Idempotent — calling while one is in flight is a no-op.
    func startTurn() {
        guard inFlight == nil else {
            kairoDebug("ConversationLoop.startTurn: already in flight")
            return
        }
        inFlight = Task { [weak self] in
            guard let self else { return }
            defer { Task { @MainActor in self.inFlight = nil } }
            await self.runOne()
        }
    }

    // MARK: - Turn body

    private func runOne() async {
        kairoDebug("Conversation turn: begin")

        // Don't fight the wake-word listener for the mic — pause it for the
        // duration of this turn. (No-op when wake word isn't running.)
        await wake.pause {
            await listenAndRespond()
        }

        kairoDebug("Conversation turn: complete")
    }

    private func listenAndRespond() async {
        // Begin presence
        await PresenceCoordinator.shared.beginListening()

        // Capture transcript
        let transcript = await captureTranscript()
        await PresenceCoordinator.shared.endListening()

        guard !transcript.isEmpty else {
            await PresenceCoordinator.shared.endSpeaking()
            return
        }
        kairoDebug("Conversation transcript: \(transcript)")

        // Call brain
        let reply: String
        do {
            reply = try await brain.handle(input: transcript, ambient: KairoAmbientContext.current())
        } catch {
            kairoDebug("Conversation brain error: \(error.localizedDescription)")
            await PresenceCoordinator.shared.beginSpeaking(
                query: transcript,
                response: "Brain isn't responding. Ollama may be down."
            )
            tts.speak("Brain isn't responding. Ollama may be down.")
            try? await Task.sleep(for: .seconds(3))
            await PresenceCoordinator.shared.endSpeaking()
            return
        }

        // Speak + present
        await PresenceCoordinator.shared.beginSpeaking(query: transcript, response: reply)
        tts.speak(reply)

        // Hold until TTS roughly finishes (estimated; AVSpeechSynthesizer
        // doesn't give exact duration up-front for unknown phonemes)
        let dwell = max(2.0, min(15.0, Double(reply.count) * 0.045))
        try? await Task.sleep(for: .seconds(dwell))
        await PresenceCoordinator.shared.endSpeaking()
    }

    // MARK: - Speech capture with silence detection

    private func captureTranscript() async -> String {
        do { try await recognizer.start() } catch {
            kairoDebug("Conversation recognizer start failed: \(error.localizedDescription)")
            return ""
        }

        var last: String = recognizer.transcript
        var lastChange = Date()
        let started = Date()

        // Poll transcript; stop on max time or silence-after-speech
        while true {
            try? await Task.sleep(for: .milliseconds(120))
            let now = recognizer.transcript
            if now != last {
                last = now
                lastChange = Date()
            }
            if Date().timeIntervalSince(started) > maxListenSeconds { break }
            if !now.isEmpty, Date().timeIntervalSince(lastChange) > silenceTimeoutSeconds { break }
        }

        recognizer.stop()
        return last.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
