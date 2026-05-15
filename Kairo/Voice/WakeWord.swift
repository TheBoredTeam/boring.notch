import Foundation
import Speech
import AVFoundation

/// Pragmatic "Hey Kairo" wake-word detector. No Porcupine — uses Apple's
/// `SFSpeechRecognizer` in continuous mode and scans partial transcripts
/// for any of the trigger phrases.
///
/// Trade-offs:
/// - SFSpeechRecognizer's continuous session caps at ~60 seconds, so we
///   recycle the session every 50s.
/// - Speech is also consumed while running, so we pause this engine when
///   the ConversationLoop wants the microphone, then resume.
/// - Power cost is moderate — comparable to dictation.
///
/// Triggers fire `onWake` (debounced 2s to avoid double-firing).
@MainActor
final class KairoWakeWord: NSObject {

    var onWake: (() -> Void)?

    /// External call to pause/resume detection — used by ConversationLoop
    /// so the wake-word listener doesn't fight the conversation recognizer
    /// for the mic.
    @Published private(set) var isRunning: Bool = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recycleTask: Task<Void, Never>?
    private var lastWakeAt: Date = .distantPast

    /// Trigger phrases. Matched case-insensitive as substrings in partial
    /// transcripts so "hey kyro / hi kyro / kyro" variants also fire.
    private let triggers: [String] = [
        "hey kairo", "hi kairo", "okay kairo", "ok kairo",
        "hey kyro",  "hi kyro",  "okay kyro",  "ok kyro",
        "kairo",     "kyro"
    ]

    /// Minimum gap between consecutive wakes so a long partial transcript
    /// doesn't keep firing while the user is still saying the trigger.
    private let wakeDebounce: TimeInterval = 2.0

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        SFSpeechRecognizer.requestAuthorization { _ in }
        listen()
        scheduleRecycle()
        isRunning = true
        print("[Kairo] WakeWord: listening for \"hey kairo\"")
    }

    func stop() {
        guard isRunning else { return }
        teardownSession()
        recycleTask?.cancel()
        recycleTask = nil
        isRunning = false
        print("[Kairo] WakeWord: stopped")
    }

    /// Pause for the duration of the closure (so ConversationLoop can grab
    /// the microphone) and resume afterward.
    func pause<T>(_ body: () async throws -> T) async rethrows -> T {
        let wasRunning = isRunning
        stop()
        defer { if wasRunning { start() } }
        return try await body()
    }

    // MARK: - Internals

    private func listen() {
        guard recognizer?.isAvailable == true else {
            print("[Kairo] WakeWord: recognizer unavailable, will retry in 10s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                self?.listen()
            }
            return
        }

        let engine = AVAudioEngine()
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak req] buffer, _ in
            req?.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            print("[Kairo] WakeWord: audio engine failed: \(error)")
            return
        }

        let t = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let r = result {
                let text = r.bestTranscription.formattedString.lowercased()
                if self.containsTrigger(text), Date().timeIntervalSince(self.lastWakeAt) > self.wakeDebounce {
                    self.lastWakeAt = Date()
                    print("[Kairo] WakeWord: triggered on \"\(text)\"")
                    Task { @MainActor in self.onWake?() }
                }
            }
            if error != nil {
                // Recoverable — recycle the session
                Task { @MainActor in self.recycleNow() }
            }
        }

        self.audioEngine = engine
        self.request = req
        self.task = t
    }

    private func containsTrigger(_ text: String) -> Bool {
        let t = text.lowercased()
        return triggers.contains { t.contains($0) }
    }

    private func scheduleRecycle() {
        recycleTask?.cancel()
        recycleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(50))
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.recycleNow() }
            }
        }
    }

    private func recycleNow() {
        guard isRunning else { return }
        teardownSession()
        // small delay so the audio engine releases cleanly before we re-arm
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.isRunning else { return }
            self.listen()
        }
    }

    private func teardownSession() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
    }
}
