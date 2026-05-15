import AppKit

final class KairoTTSEngine {
    private let synth = NSSpeechSynthesizer()

    func speak(_ text: String) {
        synth.startSpeaking(text)
    }

    func stop() {
        synth.stopSpeaking()
    }
}
