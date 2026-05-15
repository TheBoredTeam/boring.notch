import Foundation

@MainActor
final class KairoConversationLoop {
    let wake: KairoWakeWord
    let recognizer: KairoSpeechRecognizer
    let brain: KairoBrain
    let tts: KairoTTSEngine
    private var followUpWindow: Task<Void, Never>?

    init(wake: KairoWakeWord, recognizer: KairoSpeechRecognizer, brain: KairoBrain, tts: KairoTTSEngine) {
        self.wake = wake
        self.recognizer = recognizer
        self.brain = brain
        self.tts = tts
        wake.onWake = { [weak self] in Task { await self?.startTurn() } }
    }

    func startTurn() async {
        try? await recognizer.start()
        try? await Task.sleep(for: .seconds(5))
        recognizer.stop()
        let input = recognizer.transcript
        guard !input.isEmpty else { return }
        let reply = (try? await brain.handle(input: input, ambient: KairoAmbientContext.current())) ?? ""
        tts.speak(reply)
        followUpWindow?.cancel()
        followUpWindow = Task {
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            recognizer.stop()
        }
    }
}
