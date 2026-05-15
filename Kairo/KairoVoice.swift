//
//  KairoVoice.swift
//  Kairo
//
//  Microphone recording and voice command processing.
//  Records audio via AVFoundation, sends WAV to Kairo backend,
//  receives and plays TTS response.
//

import AppKit
import AVFoundation
import Combine
import Foundation

class KairoVoice: NSObject, ObservableObject {
    static let shared = KairoVoice()

    enum VoiceState {
        case idle
        case listening
        case processing
        case speaking
    }

    @Published var state: VoiceState = .idle
    @Published var transcript: String = ""
    @Published var response: String = ""
    @Published var audioLevel: Float = 0.0

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var audioPlayer: AVAudioPlayer?
    private var levelTimer: Timer?

    // Silence detection
    private var silenceStart: Date?
    private let silenceDuration: TimeInterval = 1.5
    private let silenceThreshold: Float = -40.0  // dB

    override init() {
        super.init()
    }

    // MARK: - Recording

    func startListening() {
        guard state == .idle else { return }

        // Prepare temp file
        let tempDir = FileManager.default.temporaryDirectory
        recordingURL = tempDir.appendingPathComponent("kairo_command.wav")

        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else { return }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        // Create audio file
        guard let url = recordingURL,
              let file = try? AVAudioFile(
                forWriting: url,
                settings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 16000.0,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                ]
              ) else {
            print("[KairoVoice] Failed to create audio file")
            return
        }
        audioFile = file

        // Install tap on mic
        let recordingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: format.sampleRate,
            channels: 1,
            interleaved: false
        )!

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            // Write to file (will be converted on read)
            try? self.audioFile?.write(from: buffer)

            // Calculate audio level for UI
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frames = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frames {
                sum += channelData[i] * channelData[i]
            }
            let rms = sqrt(sum / Float(frames))
            let db = 20 * log10(max(rms, 0.000001))

            DispatchQueue.main.async {
                self.audioLevel = max(0, min(1, (db + 50) / 50))  // Normalize to 0-1
            }

            // Silence detection
            if db < self.silenceThreshold {
                if self.silenceStart == nil {
                    self.silenceStart = Date()
                } else if Date().timeIntervalSince(self.silenceStart!) > self.silenceDuration {
                    DispatchQueue.main.async {
                        self.stopAndProcess()
                    }
                }
            } else {
                self.silenceStart = nil
            }
        }

        do {
            try engine.start()
            DispatchQueue.main.async {
                self.state = .listening
                self.transcript = ""
                self.response = ""
                self.silenceStart = nil
            }
            print("[KairoVoice] Listening...")
        } catch {
            print("[KairoVoice] Engine start error: \(error)")
        }
    }

    func stopAndProcess() {
        guard state == .listening else { return }

        // Stop recording
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil

        state = .processing
        audioLevel = 0

        print("[KairoVoice] Processing...")

        // Read the WAV file and send to server
        guard let url = recordingURL, let audioData = try? Data(contentsOf: url) else {
            state = .idle
            return
        }

        // Send to Kairo backend
        KairoSocket.shared.sendAudioToServer(audioData) { [weak self] transcript, responseText, audioData in
            guard let self = self else { return }

            self.transcript = transcript
            self.response = responseText

            if let audio = audioData, !audio.isEmpty {
                self.state = .speaking
                self.playResponseAudio(audio)
            } else {
                self.state = .idle
            }
        }

        // Clean up temp file
        try? FileManager.default.removeItem(at: url)
    }

    func cancel() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil
        audioPlayer?.stop()
        state = .idle
        audioLevel = 0
    }

    // MARK: - Playback

    private func playResponseAudio(_ data: Data) {
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.play()
        } catch {
            print("[KairoVoice] Playback error: \(error)")
            state = .idle
        }
    }
}

// MARK: - On-Demand TTS (used by FeedbackEngine)

extension KairoVoice {

    /// Speak text via ElevenLabs, fallback to system TTS
    func speak(_ text: String) {
        audioPlayer?.stop()
        state = .speaking

        Task {
            await speakWithElevenLabs(text)
        }
    }

    private func speakWithElevenLabs(_ text: String) async {
        let apiKey = ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"] ?? ""
        let voiceID = ProcessInfo.processInfo.environment["ELEVENLABS_VOICE_ID"]
            ?? "QR57ghQmWinyEbqmRLVI"

        guard !apiKey.isEmpty,
              let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)/stream")
        else {
            speakWithSystem(text)
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
            let (data, resp) = try await URLSession.shared.data(for: request)
            let httpResp = resp as? HTTPURLResponse
            guard httpResp?.statusCode == 200, !data.isEmpty else {
                speakWithSystem(text)
                return
            }

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("kairo_tts_\(UUID().uuidString).mp3")
            try data.write(to: tempURL)

            await MainActor.run {
                self.audioPlayer = try? AVAudioPlayer(contentsOf: tempURL)
                self.audioPlayer?.delegate = self
                self.audioPlayer?.volume = 1.0
                self.audioPlayer?.play()
            }
        } catch {
            print("[KairoVoice] ElevenLabs error: \(error)")
            speakWithSystem(text)
        }
    }

    private func speakWithSystem(_ text: String) {
        DispatchQueue.main.async {
            let synth = NSSpeechSynthesizer()
            synth.setVoice(NSSpeechSynthesizer.VoiceName(rawValue: "com.apple.speech.synthesis.voice.daniel"))
            synth.startSpeaking(text)

            let duration = Double(text.components(separatedBy: " ").count) * 0.4 + 1.0
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                self.state = .idle
            }
        }
    }
}

// MARK: - AVAudioPlayerDelegate

extension KairoVoice: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.state = .idle
        }
    }
}
