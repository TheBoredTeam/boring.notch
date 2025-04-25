import SwiftUI
import CoreHaptics

class Haptics {
    private var engine: CHHapticEngine?
    
    init() {
        do {
            engine = try CHHapticEngine()
            try engine?.start()
        } catch {
            print("Failed to create haptic engine: \(error)")
        }
    }
    
    func toggle() {
        guard let engine = engine else { return }
        
        do {
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
            let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            print("Failed to play haptic pattern: \(error)")
        }
    }
} 