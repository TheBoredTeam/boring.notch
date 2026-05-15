//
//  KairoVoiceButton.swift
//  Kairo — Premium floating voice button
//
//  Long press → activates voice mode with ripple animation.
//  Connects to Kairo backend for Whisper STT + Claude response.
//

import AVFoundation
import AppKit
import Combine
import SwiftUI

// ═══════════════════════════════════════════
// MARK: - Notification Names
// ═══════════════════════════════════════════

extension Notification.Name {
    static let kairoVoiceActivated = Notification.Name("kairoVoiceActivated")
    static let kairoVoiceDismissed = Notification.Name("kairoVoiceDismissed")
    static let kairoCommandActivated = Notification.Name("kairoCommandActivated")
}

// ═══════════════════════════════════════════
// MARK: - Voice Engine
// ═══════════════════════════════════════════

class KairoVoiceEngine: ObservableObject {
    static let shared = KairoVoiceEngine()

    @Published var isListening = false
    @Published var isSpeaking = false
    @Published var userTranscript = ""
    @Published var kairoResponse = ""
    @Published var showTranscript = false
    @Published var currentMicLevel: Float = 0

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var audioPlayer: AVAudioPlayer?

    // Silence detection
    private var silenceStart: Date?
    private let silenceDuration: TimeInterval = 1.8
    private let silenceThreshold: Float = -40.0

    func startListening() {
        guard !isListening else { return }
        isListening = true
        isSpeaking = false
        showTranscript = true
        userTranscript = ""
        kairoResponse = ""
        silenceStart = nil
        setupAudio()
    }

    private func setupAudio() {
        // Prepare temp WAV file
        recordingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("kairo_voice_\(UUID().uuidString).wav")

        audioEngine = AVAudioEngine()
        guard let engine = audioEngine, let url = recordingURL else { return }

        let inputNode = engine.inputNode
        inputNode.removeTap(onBus: 0)
        let hardwareFormat = inputNode.outputFormat(forBus: 0)

        // Record mono at the hardware sample rate — Whisper accepts any rate
        let recordFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: hardwareFormat.sampleRate,
            channels: 1,
            interleaved: false
        )!

        let wavSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: hardwareFormat.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
        ]

        guard let file = try? AVAudioFile(forWriting: url, settings: wavSettings) else {
            print("[KairoVoice] Failed to create WAV file")
            isListening = false
            return
        }
        audioFile = file
        print("[KairoVoice] Recording at \(hardwareFormat.sampleRate)Hz mono")

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordFormat) { [weak self] buffer, _ in
            guard let self else { return }

            // Write audio to WAV file
            try? self.audioFile?.write(from: buffer)

            // Calculate RMS level for waveform visualization
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frames = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frames { sum += channelData[i] * channelData[i] }
            let rms = sqrt(sum / Float(max(frames, 1)))
            let db = 20 * log10(max(rms, 0.000001))

            DispatchQueue.main.async {
                self.currentMicLevel = max(0, min(1, (db + 50) / 50))
            }

            // Auto-stop on silence
            if db < self.silenceThreshold {
                if self.silenceStart == nil {
                    self.silenceStart = Date()
                } else if Date().timeIntervalSince(self.silenceStart!) > self.silenceDuration {
                    DispatchQueue.main.async { self.stopListening() }
                }
            } else {
                self.silenceStart = nil
            }
        }

        do {
            try engine.start()
            print("[KairoVoice] Recording started")
        } catch {
            print("[KairoVoice] Engine start failed: \(error)")
            isListening = false
        }
    }

    func stopListening() {
        guard isListening else { return }
        isListening = false
        currentMicLevel = 0

        // Stop engine
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil

        // Send audio to server
        processVoice()
    }

    private func processVoice() {
        guard let url = recordingURL, let audioData = try? Data(contentsOf: url) else {
            kairoResponse = "Recording failed."
            isSpeaking = false
            return
        }

        // Need at least ~0.5s of audio (16kHz * 2 bytes * 0.5s ≈ 16000 bytes)
        guard audioData.count > 16000 else {
            kairoResponse = "Didn't catch that. Try again."
            // Clean up
            try? FileManager.default.removeItem(at: url)
            return
        }

        isSpeaking = true
        print("[KairoVoice] Sending \(audioData.count) bytes to /voice")

        KairoSocket.shared.sendAudioToServer(audioData) { [weak self] transcript, responseText, ttsAudio in
            guard let self else { return }

            self.userTranscript = transcript.isEmpty ? "(could not transcribe)" : transcript
            self.kairoResponse = responseText.isEmpty ? "No response." : responseText

            if let audio = ttsAudio, !audio.isEmpty, audio.count > 1000 {
                self.playResponse(audio)
            } else if !responseText.isEmpty && !responseText.lowercased().contains("server error") {
                KairoFeedbackEngine.shared.speakSystem(responseText)
                self.isSpeaking = false
            } else {
                KairoFeedbackEngine.shared.say("Couldn't process that.", pillText: "Try again")
                self.isSpeaking = false
            }
        }

        // Clean up temp file
        try? FileManager.default.removeItem(at: url)
    }

    private func playResponse(_ data: Data) {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("kairo_response_\(UUID().uuidString).mp3")
        do {
            try data.write(to: tempURL)
            audioPlayer = try AVAudioPlayer(contentsOf: tempURL)
            audioPlayer?.volume = 1.0
            audioPlayer?.play()

            // Reset state after playback finishes
            let duration = audioPlayer?.duration ?? 5.0
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.3) { [weak self] in
                self?.isSpeaking = false
                try? FileManager.default.removeItem(at: tempURL)
            }
        } catch {
            print("[KairoVoice] Playback error: \(error)")
            isSpeaking = false
        }
    }

    func cancel() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil
        audioPlayer?.stop()
        isListening = false
        isSpeaking = false
        currentMicLevel = 0
        if let url = recordingURL { try? FileManager.default.removeItem(at: url) }
    }

    func dismiss() {
        withAnimation(.kairoSlow) { showTranscript = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.kairoResponse = ""
            self.userTranscript = ""
        }
    }
}

// ═══════════════════════════════════════════
// MARK: - Floating Button Window
// ═══════════════════════════════════════════

class KairoVoiceButtonWindow: NSPanel {
    override init(contentRect: NSRect, styleMask: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
    }

    convenience init() {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 70, height: 70),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        level = .init(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false

        if let screen = NSScreen.main {
            setFrameOrigin(NSPoint(x: screen.frame.width - 90, y: 60))
        }
        contentView = NSHostingView(rootView: KairoVoiceButtonView())
    }
}

// ═══════════════════════════════════════════
// MARK: - Button View
// ═══════════════════════════════════════════

struct KairoVoiceButtonView: View {
    @ObservedObject var voice = KairoVoiceEngine.shared
    @State private var isPressed = false
    @State private var isActive = false
    @State private var pressProgress: CGFloat = 0
    @State private var breathe = false
    @State private var orbScale: CGFloat = 1.0
    @State private var hovered = false
    @State private var rippleScale: CGFloat = 1.0
    @State private var rippleOpacity: Double = 0

    let holdDuration: Double = 0.6

    var body: some View {
        ZStack {
            // Ripple ring
            Circle()
                .stroke(K.cyan.opacity(rippleOpacity), lineWidth: 1.5)
                .frame(width: 48, height: 48)
                .scaleEffect(rippleScale)

            // Breathing glow
            Circle()
                .fill(RadialGradient(colors: [K.cyan.opacity(breathe ? 0.25 : 0.08), .clear], center: .center, startRadius: 0, endRadius: 40))
                .frame(width: 80, height: 80).blur(radius: 8)
                .scaleEffect(breathe ? 1.1 : 0.9)

            // Progress ring
            Circle()
                .trim(from: 0, to: pressProgress)
                .stroke(K.cyan, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 54, height: 54)
                .rotationEffect(.degrees(-90))
                .opacity(isPressed ? 1 : 0)

            // Main orb
            ZStack {
                Circle().glassEffect(.regular.interactive()).frame(width: 48, height: 48)
                Circle()
                    .fill(LinearGradient(
                        colors: isActive ? [K.green, K.cyan] : [K.cyan.opacity(isPressed ? 0.4 : 0.15), K.blue.opacity(isPressed ? 0.3 : 0.1)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 48, height: 48)
                Circle().stroke(LinearGradient(colors: [.white.opacity(hovered ? 0.3 : 0.15), K.cyan.opacity(isPressed ? 0.6 : 0.2)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                    .frame(width: 48, height: 48)

                Image(systemName: isActive ? "waveform" : "mic.fill")
                    .font(.system(size: isActive ? 16 : 18, weight: .medium))
                    .foregroundStyle(isActive ? K.green : .white.opacity(isPressed ? 1 : 0.85))
                    .shadow(color: isActive ? K.green.opacity(0.6) : K.cyan.opacity(isPressed ? 0.6 : 0.2), radius: isPressed ? 10 : 4)
            }
            .frame(width: 48, height: 48)
            .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
            .shadow(color: K.cyan.opacity(isPressed ? 0.4 : 0.1), radius: isPressed ? 16 : 6)
            .scaleEffect(orbScale)

            // Tooltip
            if hovered && !isPressed {
                Text("Hold to speak")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().glassEffect(.regular))
                    .offset(y: -40)
                    .transition(.scale(scale: 0.8, anchor: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: 70, height: 70)
        .onAppear { withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) { breathe = true } }
        .onHover { h in withAnimation(.kairoFast) { hovered = h; orbScale = h && !isPressed ? 1.06 : (isPressed ? 0.93 : 1.0) } }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isPressed { beginPress() } }
                .onEnded { _ in endPress() }
        )
        .animation(.kairoFast, value: isActive)
        .animation(.kairoFast, value: isPressed)
    }

    private func beginPress() {
        isPressed = true
        withAnimation(.kairoMicro) { orbScale = 0.93 }
        pressProgress = 0
        withAnimation(.linear(duration: holdDuration)) { pressProgress = 1.0 }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)

        DispatchQueue.main.asyncAfter(deadline: .now() + holdDuration) { [self] in
            guard isPressed else { return }
            activate()
        }
    }

    private func endPress() {
        if isActive {
            deactivate()
        } else {
            withAnimation(.kairoSpring) { isPressed = false; pressProgress = 0; orbScale = hovered ? 1.06 : 1.0 }
        }
    }

    private func activate() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        withAnimation(.kairoSpring) { isActive = true; orbScale = 1.12 }
        fireRipple()
        voice.startListening()
        NotificationCenter.default.post(name: .kairoVoiceActivated, object: nil)
    }

    private func deactivate() {
        withAnimation(.kairoSpring) { isActive = false; isPressed = false; pressProgress = 0; orbScale = 1.0 }
        voice.stopListening()
        NotificationCenter.default.post(name: .kairoVoiceDismissed, object: nil)
    }

    private func fireRipple() {
        rippleScale = 1.0; rippleOpacity = 0.7
        withAnimation(.easeOut(duration: 1.0)) { rippleScale = 2.5; rippleOpacity = 0 }
    }
}
