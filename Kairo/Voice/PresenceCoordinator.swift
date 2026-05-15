import Foundation
import AVFoundation
import Combine

@MainActor
final class PresenceCoordinator {
    static let shared = PresenceCoordinator()

    private var amplitudeTimer: Timer?
    private var audioMonitor: AVAudioEngine?

    func beginListening() async {
        kairoDebug("beginListening: start")

        NowPlayingWatcher.shared.stop()

        Earcons.shared.play(.listenStart)
        try? await Task.sleep(for: .milliseconds(180))

        Task { await AudioDucker.shared.duck() }

        let ctl = KairoRuntime.shared.orbieController
        kairoDebug("beginListening: showing orb")
        await KairoRuntime.shared.coordinator?.showOrb()
        kairoDebug("beginListening: orb shown, setting state")
        ctl?.startListening()
        ctl?.setVoiceState(.listening(amplitude: 0))
        startAmplitudeMonitoring()
    }

    func endListening() async {
        kairoDebug("endListening: start")
        stopAmplitudeMonitoring()
        Earcons.shared.play(.listenEnd)
        try? await Task.sleep(for: .milliseconds(80))

        KairoRuntime.shared.orbieController?.setVoiceState(.thinking)
        kairoDebug("endListening: set thinking state")
    }

    func beginSpeaking(query: String, response: String) async {
        kairoDebug("beginSpeaking: start")
        Earcons.shared.play(.respond)
        try? await Task.sleep(for: .milliseconds(120))

        kairoDebug("beginSpeaking: calling presentAndWait")
        await KairoRuntime.shared.presentAndWait(
            .textResponse,
            payload: TextResponseData(query: query, response: response, icon: nil)
        )
        kairoDebug("beginSpeaking: presentAndWait returned")

        KairoRuntime.shared.orbieController?.setVoiceState(.speaking(amplitude: 0))
        startSpeakingAmplitude(duration: estimatedSpeechDuration(for: response))
        kairoDebug("beginSpeaking: done")
    }

    func endSpeaking() async {
        kairoDebug("endSpeaking: start")
        stopAmplitudeMonitoring()
        KairoRuntime.shared.orbieController?.setVoiceState(.idle)

        try? await Task.sleep(for: .seconds(2))
        KairoRuntime.shared.dismiss()
        kairoDebug("endSpeaking: dismissed")

        await AudioDucker.shared.restore()
        NowPlayingWatcher.shared.start()
        kairoDebug("endSpeaking: done")
    }

    func error() async {
        stopAmplitudeMonitoring()
        Earcons.shared.play(.error)
        KairoRuntime.shared.orbieController?.setVoiceState(.idle)
        KairoRuntime.shared.dismiss()
        await AudioDucker.shared.restore()
        NowPlayingWatcher.shared.start()
    }

    // MARK: - Amplitude monitoring (listening)

    private func startAmplitudeMonitoring() {
        let engine = AVAudioEngine()
        audioMonitor = engine

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frameLength {
                sum += abs(channelData[i])
            }
            let avg = sum / Float(frameLength)
            let normalized = min(1.0, avg * 8.0)

            Task { @MainActor in
                guard let self else { return }
                KairoRuntime.shared.orbieController?.updateAmplitude(normalized)
            }
        }

        do {
            try engine.start()
        } catch {
            print("[Kairo] amplitude monitor failed: \(error)")
        }
    }

    private func stopAmplitudeMonitoring() {
        audioMonitor?.inputNode.removeTap(onBus: 0)
        audioMonitor?.stop()
        audioMonitor = nil
        amplitudeTimer?.invalidate()
        amplitudeTimer = nil
    }

    // MARK: - Simulated speaking amplitude

    private func startSpeakingAmplitude(duration: TimeInterval) {
        stopAmplitudeMonitoring()

        let start = Date()
        amplitudeTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            let elapsed = Date().timeIntervalSince(start)
            if elapsed >= duration {
                timer.invalidate()
                return
            }
            let t = elapsed
            let amp: Float = Float(
                0.4 + 0.3 * sin(t * 6.0) + 0.2 * sin(t * 13.0) + 0.1 * sin(t * 23.0)
            )
            Task { @MainActor in
                guard self != nil else { return }
                KairoRuntime.shared.orbieController?.updateAmplitude(max(0.1, min(1.0, amp)))
            }
        }
    }

    private func estimatedSpeechDuration(for text: String) -> TimeInterval {
        let wordCount = text.split(separator: " ").count
        return max(1.5, Double(wordCount) / 2.5)
    }
}
