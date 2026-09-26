//
//  AmbientSoundManager.swift
//  boringNotch
//
//  Focus soundscapes for the Pomodoro tab. Noise colors, rain, ocean and
//  binaural beats are synthesized in real time with AVAudioEngine, so they
//  need no bundled audio and work fully offline. "Lofi" streams a free public
//  radio channel (SomaFM) over the network and degrades gracefully if offline.
//

import Foundation
import AVFoundation
import Combine
import Defaults

// Lives on the audio render thread. Plain value math only — no locks, no
// allocation. Parameters written from the main thread are simple scalars; the
// occasional benign race only nudges a float and is inaudible.
final class NoiseGenerator {
    enum Mode: Int {
        case white, pink, brown, rain, ocean, binaural
    }

    var mode: Mode = .brown
    var gain: Float = 0.6
    var carrier: Double = 200   // binaural base frequency (Hz)
    var beat: Double = 10       // binaural L/R offset (Hz)

    // Filter / integrator state
    private var brown: Float = 0
    private var pink0: Float = 0, pink1: Float = 0, pink2: Float = 0
    private var pink3: Float = 0, pink4: Float = 0, pink5: Float = 0, pink6: Float = 0
    private var oceanPhase: Double = 0
    private var leftPhase: Double = 0
    private var rightPhase: Double = 0

    @inline(__always) private func white() -> Float { Float.random(in: -1...1) }

    /// Produces one stereo frame as (left, right).
    func next(sampleRate: Double) -> (Float, Float) {
        switch mode {
        case .binaural:
            let twoPi = 2.0 * Double.pi
            leftPhase += twoPi * carrier / sampleRate
            rightPhase += twoPi * (carrier + beat) / sampleRate
            if leftPhase > twoPi { leftPhase -= twoPi }
            if rightPhase > twoPi { rightPhase -= twoPi }
            // A touch of brown noise underneath keeps pure tones from feeling clinical.
            let w = white()
            brown = (brown + 0.02 * w) / 1.02
            let bed = brown * 1.2 * 0.15
            let l = (Float(sin(leftPhase)) * 0.5 + bed) * gain
            let r = (Float(sin(rightPhase)) * 0.5 + bed) * gain
            return (l, r)

        case .white:
            let s = white() * 0.4 * gain
            return (s, s)

        case .pink:
            let w = white()
            pink0 = 0.99886 * pink0 + w * 0.0555179
            pink1 = 0.99332 * pink1 + w * 0.0750759
            pink2 = 0.96900 * pink2 + w * 0.1538520
            pink3 = 0.86650 * pink3 + w * 0.3104856
            pink4 = 0.55000 * pink4 + w * 0.5329522
            pink5 = -0.7616 * pink5 - w * 0.0168980
            let pink = pink0 + pink1 + pink2 + pink3 + pink4 + pink5 + pink6 + w * 0.5362
            pink6 = w * 0.115926
            let s = pink * 0.11 * gain
            return (s, s)

        case .brown:
            let w = white()
            brown = (brown + 0.02 * w) / 1.02
            let s = brown * 3.2 * gain
            return (s, s)

        case .rain:
            // Brown bed for the "wash", plus sparse bright droplets on top.
            let w = white()
            brown = (brown + 0.02 * w) / 1.02
            let bed = brown * 2.2
            let drop = abs(w) > 0.992 ? w * 1.6 : 0
            let s = (bed + drop) * 0.5 * gain
            return (s, s)

        case .ocean:
            // Brown noise swelling with a slow (~0.08 Hz) wave envelope.
            let w = white()
            brown = (brown + 0.02 * w) / 1.02
            oceanPhase += 2.0 * Double.pi * 0.08 / sampleRate
            if oceanPhase > 2.0 * Double.pi { oceanPhase -= 2.0 * Double.pi }
            let env = Float((sin(oceanPhase) + 1.0) / 2.0) // 0...1
            let s = brown * 3.4 * (0.18 + 0.82 * env) * gain
            return (s, s)
        }
    }
}

@MainActor
final class AmbientSoundManager: ObservableObject {
    static let shared = AmbientSoundManager()

    enum Sound: String, CaseIterable, Identifiable {
        case brown, pink, white, rain, ocean, focus, calm, deep, lofi
        var id: String { rawValue }

        var label: String {
            switch self {
            case .brown: return "Brown"
            case .pink:  return "Pink"
            case .white: return "White"
            case .rain:  return "Rain"
            case .ocean: return "Ocean"
            case .focus: return "Focus"
            case .calm:  return "Calm"
            case .deep:  return "Deep"
            case .lofi:  return "Lofi"
            }
        }

        var icon: String {
            switch self {
            case .brown: return "waveform.path"
            case .pink:  return "waveform"
            case .white: return "aqi.medium"
            case .rain:  return "cloud.rain.fill"
            case .ocean: return "water.waves"
            case .focus: return "brain.head.profile"
            case .calm:  return "leaf.fill"
            case .deep:  return "moon.zzz.fill"
            case .lofi:  return "music.note"
            }
        }

        var isStream: Bool { self == .lofi }

        // Mapping for synthesized sounds.
        fileprivate var noiseMode: NoiseGenerator.Mode? {
            switch self {
            case .white: return .white
            case .pink:  return .pink
            case .brown: return .brown
            case .rain:  return .rain
            case .ocean: return .ocean
            case .focus, .calm, .deep: return .binaural
            case .lofi:  return nil
            }
        }

        // Binaural carrier/beat presets (Hz). Beat freq targets a brainwave band.
        fileprivate var binaural: (carrier: Double, beat: Double)? {
            switch self {
            case .focus: return (210, 14)  // beta-ish — alert focus
            case .calm:  return (180, 10)  // alpha — relaxed
            case .deep:  return (140, 4)   // theta — deep work
            default: return nil
            }
        }
    }

    @Published private(set) var current: Sound? = nil
    @Published var volume: Double {
        didSet {
            Defaults[.pomodoroAmbientVolume] = volume
            applyVolume()
        }
    }

    private let engine = AVAudioEngine()
    private let generator = NoiseGenerator()
    private var sourceNode: AVAudioSourceNode?
    private var engineConfigured = false

    // Streamed sounds (lofi).
    private var streamPlayer: AVPlayer?
    private static let lofiStreamURL = URL(string: "https://ice1.somafm.com/groovesalad-128-mp3")!

    private init() {
        self.volume = Defaults[.pomodoroAmbientVolume]
    }

    // MARK: - Public controls

    /// Tap a sound to start it; tap the active one again to stop.
    func toggle(_ sound: Sound) {
        if current == sound {
            stop()
        } else {
            play(sound)
        }
    }

    func play(_ sound: Sound) {
        stopStream()
        if sound.isStream {
            stopSynth()
            startStream()
        } else {
            startSynth(sound)
        }
        current = sound
    }

    func stop() {
        stopSynth()
        stopStream()
        current = nil
    }

    // MARK: - Synthesis

    private func configureEngineIfNeeded() {
        guard !engineConfigured else { return }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2) else { return }
        let sampleRate = format.sampleRate

        let node = AVAudioSourceNode(format: format) { [generator] _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let channels = abl.count
            // Non-interleaved float buffers: [0] = L, [1] = R.
            let left = abl[0].mData?.assumingMemoryBound(to: Float.self)
            let right = channels > 1 ? abl[1].mData?.assumingMemoryBound(to: Float.self) : left
            for frame in 0..<Int(frameCount) {
                let (l, r) = generator.next(sampleRate: sampleRate)
                left?[frame] = l
                right?[frame] = r
            }
            return noErr
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
        sourceNode = node
        engineConfigured = true
    }

    private func startSynth(_ sound: Sound) {
        configureEngineIfNeeded()
        if let mode = sound.noiseMode { generator.mode = mode }
        if let b = sound.binaural {
            generator.carrier = b.carrier
            generator.beat = b.beat
        }
        generator.gain = Float(volume)
        engine.mainMixerNode.outputVolume = Float(volume)
        if !engine.isRunning {
            do { try engine.start() } catch { print("Ambient engine start failed: \(error)") }
        }
    }

    private func stopSynth() {
        if engine.isRunning { engine.pause() }
    }

    // MARK: - Streaming

    private func startStream() {
        let player = AVPlayer(url: Self.lofiStreamURL)
        player.volume = Float(volume)
        player.automaticallyWaitsToMinimizeStalling = true
        player.play()
        streamPlayer = player
    }

    private func stopStream() {
        streamPlayer?.pause()
        streamPlayer = nil
    }

    // MARK: - Volume

    private func applyVolume() {
        generator.gain = Float(volume)
        engine.mainMixerNode.outputVolume = Float(volume)
        streamPlayer?.volume = Float(volume)
    }
}
