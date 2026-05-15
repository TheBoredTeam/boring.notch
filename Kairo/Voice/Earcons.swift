import AVFoundation

@MainActor
final class Earcons {
    static let shared = Earcons()

    private var player: AVAudioPlayer?

    enum Tone {
        case listenStart
        case listenEnd
        case thinking
        case respond
        case error

        var frequencies: [Double] {
            switch self {
            case .listenStart: return [523.25, 783.99]
            case .listenEnd:   return [880.00]
            case .thinking:    return [349.23]
            case .respond:     return [659.25, 987.77]
            case .error:       return [523.25, 392.00]
            }
        }

        var duration: Double {
            switch self {
            case .listenStart: return 0.18
            case .listenEnd:   return 0.08
            case .thinking:    return 0.25
            case .respond:     return 0.22
            case .error:       return 0.30
            }
        }
    }

    func play(_ tone: Tone) {
        let data = generateTone(frequencies: tone.frequencies, duration: tone.duration)
        do {
            player = try AVAudioPlayer(data: data)
            player?.volume = 0.25
            player?.prepareToPlay()
            player?.play()
        } catch {
            print("[Kairo] earcon failed: \(error)")
        }
    }

    private func generateTone(frequencies: [Double], duration: Double) -> Data {
        let sampleRate = 44100.0
        let noteDuration = duration / Double(frequencies.count)
        let fadeSamples = Int(sampleRate * 0.015)

        var samples: [Int16] = []
        for freq in frequencies {
            let noteSamples = Int(sampleRate * noteDuration)
            for i in 0..<noteSamples {
                let t = Double(i) / sampleRate
                var amplitude = sin(2.0 * .pi * freq * t)

                if i < fadeSamples {
                    amplitude *= Double(i) / Double(fadeSamples)
                } else if i > noteSamples - fadeSamples {
                    amplitude *= Double(noteSamples - i) / Double(fadeSamples)
                }

                let sample = Int16(amplitude * 0.4 * Double(Int16.max))
                samples.append(sample)
            }
        }

        return wavData(samples: samples, sampleRate: Int(sampleRate))
    }

    private func wavData(samples: [Int16], sampleRate: Int) -> Data {
        var data = Data()
        let dataSize = samples.count * 2
        let fileSize = dataSize + 36

        data.append(contentsOf: "RIFF".utf8)
        data.append(UInt32(fileSize).littleEndianData)
        data.append(contentsOf: "WAVE".utf8)

        data.append(contentsOf: "fmt ".utf8)
        data.append(UInt32(16).littleEndianData)
        data.append(UInt16(1).littleEndianData)
        data.append(UInt16(1).littleEndianData)
        data.append(UInt32(sampleRate).littleEndianData)
        data.append(UInt32(sampleRate * 2).littleEndianData)
        data.append(UInt16(2).littleEndianData)
        data.append(UInt16(16).littleEndianData)

        data.append(contentsOf: "data".utf8)
        data.append(UInt32(dataSize).littleEndianData)
        samples.forEach { data.append($0.littleEndianData) }

        return data
    }
}

private extension FixedWidthInteger {
    var littleEndianData: Data {
        withUnsafeBytes(of: self.littleEndian) { Data($0) }
    }
}
