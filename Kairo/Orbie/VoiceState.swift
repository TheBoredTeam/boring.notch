import Foundation

enum VoiceState: Equatable {
    case idle
    case listening(amplitude: Float)
    case thinking
    case speaking(amplitude: Float)
}
