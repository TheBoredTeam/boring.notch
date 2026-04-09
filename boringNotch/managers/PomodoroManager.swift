import Foundation
import Combine
import SwiftUI

class PomodoroManager: ObservableObject {
    static let shared = PomodoroManager()
    
    enum TimerState {
        case idle
        case running
        case paused
    }
    
    enum SessionType: String {
        case work = "Focus"
        case shortBreak = "Short Break"
        case longBreak = "Long Break"
    }
    
    @Published var state: TimerState = .idle
    @Published var currentSession: SessionType = .work
    @Published var timeRemaining: TimeInterval = 25 * 60 // Default 25 minutes
    
    // Configurable Durations
    @AppStorage("pomodoroWorkDuration") var workDuration: Double = 25 * 60
    @AppStorage("pomodoroShortBreakDuration") var shortBreakDuration: Double = 5 * 60
    @AppStorage("pomodoroLongBreakDuration") var longBreakDuration: Double = 15 * 60
    
    private var timer: Timer?
    
    private init() {
        resetTimer()
    }
    
    func start() {
        guard state != .running else { return }
        state = .running
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }
    
    func pause() {
        state = .paused
        timer?.invalidate()
        timer = nil
    }
    
    func resetTimer() {
        pause()
        state = .idle
        switch currentSession {
        case .work: timeRemaining = workDuration
        case .shortBreak: timeRemaining = shortBreakDuration
        case .longBreak: timeRemaining = longBreakDuration
        }
    }
    
    func setCustomTime(minutes: Int, seconds: Int) {
        let totalSeconds = Double(minutes * 60 + seconds)
        timeRemaining = totalSeconds
        
        switch currentSession {
        case .work: workDuration = totalSeconds
        case .shortBreak: shortBreakDuration = totalSeconds
        case .longBreak: longBreakDuration = totalSeconds
        }
    }
    func setSession(_ session: SessionType) {
        currentSession = session
        resetTimer()
    }
    
    private func tick() {
        if timeRemaining > 0 {
            timeRemaining -= 1
        } else {
            // Timer Finished! Play a sound and switch states
            NSSound(named: "Glass")?.play()
            handleSessionEnd()
        }
    }
    
    private func handleSessionEnd() {
        // Auto-switch to next logical state
        switch currentSession {
        case .work:
            setSession(.shortBreak)
        case .shortBreak:
            setSession(.work)
        case .longBreak:
            setSession(.work)
        }
    }
    
    var formattedTime: String {
        let minutes = Int(timeRemaining) / 60
        let seconds = Int(timeRemaining) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
