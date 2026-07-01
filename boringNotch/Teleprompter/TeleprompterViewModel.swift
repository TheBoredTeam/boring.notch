//
//  TeleprompterViewModel.swift
//  boringNotch
//
//  Owns the teleprompter's state: the script, the current reading position,
//  playback, appearance, and the bridge to speech-following. Shared as a
//  singleton so the notch view and the Settings pane edit the same script.
//

import Foundation
import SwiftUI
import Combine
import Defaults

@MainActor
final class TeleprompterViewModel: ObservableObject {
    static let shared = TeleprompterViewModel()

    // Script
    @Published var scriptText: String = Defaults[.teleprompterText]
    @Published private(set) var words: [ScriptWord] = []
    @Published private(set) var chunks: [ScriptChunk] = []

    // Reading position (index of the word currently being read)
    @Published var currentWordIndex: Int = 0

    // Playback
    @Published private(set) var isRunning: Bool = false
    @Published var followVoice: Bool = Defaults[.teleprompterFollowVoice]
    @Published private(set) var isListening: Bool = false
    @Published private(set) var statusMessage: String?

    // Appearance (persisted)
    @Published var fontSize: Double = Defaults[.teleprompterFontSize]
    @Published var mirror: Bool = Defaults[.teleprompterMirror]

    let follower = SpeechFollower()
    private var cancellables = Set<AnyCancellable>()
    private var holdingNotchOpen = false

    var currentChunkIndex: Int {
        chunks.firstIndex { $0.contains(currentWordIndex) } ?? max(0, chunks.count - 1)
    }

    var progress: Double {
        guard !words.isEmpty else { return 0 }
        return min(1, Double(currentWordIndex) / Double(words.count))
    }

    private init() {
        TeleprompterFont.registerIfNeeded()
        rebuild(resetPosition: true)

        // Voice drives the reading position while following.
        follower.$matchIndex
            .receive(on: RunLoop.main)
            .sink { [weak self] index in
                guard let self, self.isRunning, self.followVoice else { return }
                self.currentWordIndex = min(index, self.words.count)
            }
            .store(in: &cancellables)

        // Reflect the recognizer's status; drop back to manual on failure.
        follower.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self else { return }
                self.isListening = (status == .listening)
                self.statusMessage = Self.message(for: status)
                if status != .listening, self.isRunning, self.followVoice {
                    self.isRunning = false
                    self.releaseNotch()
                }
            }
            .store(in: &cancellables)

        // Persist + rebuild the script shortly after edits settle.
        $scriptText
            .dropFirst()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] text in
                Defaults[.teleprompterText] = text
                self?.rebuild(resetPosition: false)
            }
            .store(in: &cancellables)

        $fontSize.dropFirst().sink { Defaults[.teleprompterFontSize] = $0 }.store(in: &cancellables)
        $mirror.dropFirst().sink { Defaults[.teleprompterMirror] = $0 }.store(in: &cancellables)
        $followVoice.dropFirst().sink { Defaults[.teleprompterFollowVoice] = $0 }.store(in: &cancellables)
    }

    // MARK: - Script lifecycle

    func rebuild(resetPosition: Bool) {
        let newWords = TeleprompterTokenizer.words(from: scriptText)
        words = newWords
        chunks = TeleprompterTokenizer.chunks(from: newWords)
        currentWordIndex = resetPosition ? 0 : min(currentWordIndex, newWords.count)
        follower.setScript(words: newWords.map(\.normalized), resetPosition: resetPosition)
    }

    // MARK: - Playback

    func toggleRun() {
        isRunning ? stop() : start()
    }

    func start() {
        guard !words.isEmpty else { return }
        isRunning = true
        holdNotchOpen()
        if followVoice {
            follower.seek(to: currentWordIndex)
            Task { await follower.start() }
        }
    }

    func stop() {
        isRunning = false
        follower.stop()
        releaseNotch()
    }

    func restart() {
        setPosition(0)
    }

    /// Turn voice-following on/off, starting or stopping the mic if we're live.
    func setFollowVoice(_ on: Bool) {
        followVoice = on
        guard isRunning else { return }
        if on {
            follower.seek(to: currentWordIndex)
            Task { await follower.start() }
        } else {
            follower.stop()
        }
    }

    // MARK: - Manual navigation

    func step(words delta: Int) {
        setPosition(currentWordIndex + delta)
    }

    func step(chunks delta: Int) {
        guard !chunks.isEmpty else { return }
        let target = max(0, min(currentChunkIndex + delta, chunks.count - 1))
        setPosition(chunks[target].startIndex)
    }

    func setPosition(_ index: Int) {
        currentWordIndex = max(0, min(index, words.count))
        follower.seek(to: currentWordIndex)
    }

    // MARK: - Keep the notch open while presenting

    private func holdNotchOpen() {
        guard !holdingNotchOpen else { return }
        holdingNotchOpen = true
        SharingStateManager.shared.beginInteraction()
    }

    private func releaseNotch() {
        guard holdingNotchOpen else { return }
        holdingNotchOpen = false
        SharingStateManager.shared.endInteraction()
    }

    /// Called when the teleprompter view leaves the screen.
    func viewDisappeared() {
        if isRunning { stop() }
    }

    // MARK: - Helpers

    private static func message(for status: SpeechFollower.Status) -> String? {
        switch status {
        case .idle, .listening: return nil
        case .denied: return "Microphone or speech access denied"
        case .unavailable: return "Speech recognition unavailable"
        case .error(let text): return text
        }
    }
}
