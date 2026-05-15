import AVFoundation

/// Modern Kairo TTS — `AVSpeechSynthesizer` with a premium voice when one
/// is installed locally (Settings → Accessibility → Spoken Content →
/// System Voice → Manage Voices → English (US) → Premium / Enhanced).
///
/// Falls back to enhanced, then default en-US, so it works on any Mac.
@MainActor
final class KairoTTSEngine: NSObject {

    private let synth = AVSpeechSynthesizer()
    private var voice: AVSpeechSynthesisVoice?

    override init() {
        super.init()
        voice = Self.pickBestVoice()
        synth.delegate = self
    }

    func speak(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.96  // a hair slower than default
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0.1
        synth.speak(utterance)
    }

    /// Returns true if speech was actually playing (and is now stopping).
    @discardableResult
    func stop() -> Bool {
        guard synth.isSpeaking else { return false }
        synth.stopSpeaking(at: .immediate)
        return true
    }

    var isSpeaking: Bool { synth.isSpeaking }

    // MARK: - Voice selection

    /// Walk the installed voices preferring premium → enhanced → default.
    /// Picks the first match in English (US/UK/AU).
    private static func pickBestVoice() -> AVSpeechSynthesisVoice {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let englishLocales: Set<String> = ["en-US", "en-GB", "en-AU", "en-IE"]

        // Prefer premium (downloadable) voices in en-*
        if let premium = voices.first(where: { v in
            v.quality == .premium && englishLocales.contains(v.language)
        }) {
            print("[Kairo] TTS using premium voice: \(premium.name) (\(premium.identifier))")
            return premium
        }

        // Then enhanced
        if let enhanced = voices.first(where: { v in
            v.quality == .enhanced && englishLocales.contains(v.language)
        }) {
            print("[Kairo] TTS using enhanced voice: \(enhanced.name) (\(enhanced.identifier))")
            return enhanced
        }

        // Fall back to system default for en-US
        let fallback = AVSpeechSynthesisVoice(language: "en-US")
            ?? AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
            ?? AVSpeechSynthesisVoice.speechVoices().first!
        print("[Kairo] TTS using fallback voice: \(fallback.name)")
        return fallback
    }
}

// MARK: - Delegate (just for debugging)

extension KairoTTSEngine: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        // No-op; could pulse the orb based on this if we want speech-clock accuracy.
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // No-op.
    }
}
