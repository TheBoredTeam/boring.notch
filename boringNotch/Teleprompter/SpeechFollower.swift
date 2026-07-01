//
//  SpeechFollower.swift
//  boringNotch
//
//  Listens to the microphone with on-device speech recognition and reports how
//  far the speaker has read into the script. The matching is forward-only and
//  tolerant: it skips filler words and small misrecognitions, and never jumps
//  backwards on its own, so the highlight tracks the voice smoothly.
//

import Foundation
import AVFoundation
import Speech

@MainActor
final class SpeechFollower: ObservableObject {
    enum Status: Equatable {
        case idle
        case listening
        case denied        // mic or speech permission refused
        case unavailable   // recognizer not available for this locale/device
        case error(String)
    }

    @Published private(set) var status: Status = .idle
    /// Index of the next script word we expect to hear. Monotonic while listening.
    @Published private(set) var matchIndex: Int = 0

    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// Normalized words of the current script.
    private var scriptWords: [String] = []
    /// Normalized words heard so far in the current recognition session.
    private var lastSpoken: [String] = []
    /// How far ahead of the current position we look for the next spoken word.
    private let lookAhead = 8

    var isListening: Bool { status == .listening }

    init(localeIdentifier: String = Locale.current.identifier) {
        self.recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
            ?? SFSpeechRecognizer()
    }

    // MARK: - Script

    func setScript(words: [String], resetPosition: Bool) {
        scriptWords = words
        if resetPosition { matchIndex = 0 }
        lastSpoken = []
    }

    /// Move the expected position (e.g. after manual scrubbing) without losing
    /// the audio session.
    func seek(to index: Int) {
        matchIndex = max(0, min(index, scriptWords.count))
        lastSpoken = []
    }

    // MARK: - Control

    func start() async {
        guard status != .listening else { return }
        guard let recognizer, recognizer.isAvailable else {
            status = .unavailable
            return
        }
        guard await Self.requestAuthorization() else {
            status = .denied
            return
        }
        do {
            try beginSession(with: recognizer)
            status = .listening
        } catch {
            status = .error(error.localizedDescription)
            teardown()
        }
    }

    func stop() {
        teardown()
        status = .idle
    }

    // MARK: - Session

    private func beginSession(with recognizer: SFSpeechRecognizer) throws {
        teardown()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request
        lastSpoken = []

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            // The callback arrives on a private queue. Pull out only Sendable
            // values (plain strings/bools), then hop to the main actor.
            let spoken: [String]? = result.map { r in
                r.bestTranscription.segments
                    .map { TeleprompterTokenizer.normalize($0.substring) }
                    .filter { !$0.isEmpty }
            }
            let isFinal = result?.isFinal ?? false
            let failure = error?.localizedDescription
            Task { @MainActor [weak self] in
                self?.handle(spoken: spoken, isFinal: isFinal, failure: failure)
            }
        }
    }

    private func handle(spoken: [String]?, isFinal: Bool, failure: String?) {
        if let spoken { ingest(spoken: spoken) }

        // Recognizers periodically finalize a segment (and macOS caps a single
        // request's duration). Restart transparently so a long script keeps
        // following, preserving our place via `matchIndex`.
        if isFinal {
            restart()
            return
        }
        if let failure, status == .listening {
            NSLog("Teleprompter speech recognition error: \(failure)")
            restart()
        }
    }

    private func restart() {
        guard status == .listening, let recognizer else { return }
        do {
            try beginSession(with: recognizer)
        } catch {
            status = .error(error.localizedDescription)
            teardown()
        }
    }

    private func teardown() {
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    // MARK: - Matching

    private func ingest(spoken: [String]) {
        guard !scriptWords.isEmpty else { return }
        // Process only words appended since the previous callback.
        let common = commonPrefix(lastSpoken, spoken)
        if spoken.count > common {
            for word in spoken[common...] {
                advance(with: word)
            }
        }
        lastSpoken = spoken
    }

    private func advance(with spoken: String) {
        guard matchIndex < scriptWords.count else { return }
        let end = min(scriptWords.count, matchIndex + lookAhead)
        var i = matchIndex
        while i < end {
            if wordsMatch(scriptWords[i], spoken) {
                matchIndex = i + 1
                return
            }
            i += 1
        }
        // No match nearby: likely a filler word or misrecognition — ignore it
        // and wait for the next word rather than jumping.
    }

    private func commonPrefix(_ a: [String], _ b: [String]) -> Int {
        var i = 0
        let n = min(a.count, b.count)
        while i < n && a[i] == b[i] { i += 1 }
        return i
    }

    private func wordsMatch(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        // Tolerate shared stems (plurals, verb endings).
        if a.count >= 4 && b.count >= 4 && (a.hasPrefix(b) || b.hasPrefix(a)) {
            return true
        }
        // Tolerate a single-character difference for longer words.
        if a.count >= 5 && b.count >= 5 {
            return levenshtein(a, b) <= 1
        }
        return false
    }

    private func levenshtein(_ a: String, _ b: String) -> Int {
        let s = Array(a), t = Array(b)
        guard !s.isEmpty else { return t.count }
        guard !t.isEmpty else { return s.count }
        var prev = Array(0...t.count)
        var curr = [Int](repeating: 0, count: t.count + 1)
        for i in 1...s.count {
            curr[0] = i
            for j in 1...t.count {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &curr)
        }
        return prev[t.count]
    }

    // MARK: - Authorization

    /// Requests both speech-recognition and microphone permission.
    static func requestAuthorization() async -> Bool {
        let speechAuthorized = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        guard speechAuthorized else { return false }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }

    nonisolated static var isAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
            && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
}
