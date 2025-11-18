import Foundation
import Combine
import SwiftUI
import UserNotifications
import Defaults

// Manager Pomodoro con soporte de descanso largo y notificaciones locales.
class PomodoroManager: ObservableObject {
    static let shared = PomodoroManager()

    // Duraciones (segundos) cargadas desde Defaults
    @Published var workDuration: TimeInterval = Defaults[.pomodoroWorkDuration]
    @Published var breakDuration: TimeInterval = Defaults[.pomodoroBreakDuration]
    @Published var longBreakDuration: TimeInterval = Defaults[.pomodoroLongBreakDuration]
    @Published var useLongBreak: Bool = Defaults[.pomodoroUseLongBreak]
    @Published var longBreakAfter: Int = Defaults[.pomodoroLongBreakAfter]

    // Estado dinámico
    @Published var remaining: TimeInterval = Defaults[.pomodoroWorkDuration]
    @Published var isRunning: Bool = false
    @Published var isWorkPhase: Bool = true
    @Published var completedWorkSessions: Int = 0

    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    init() {
        observeDefaults()
        requestNotificationPermission()
    }

    // Observa cambios en Defaults y aplica nuevas duraciones sin romper el estado actual.
    private func observeDefaults() {
        Defaults.publisher(.pomodoroWorkDuration).map(\.
            newValue).sink { [weak self] new in self?.workDuration = new }.store(in: &cancellables)
        Defaults.publisher(.pomodoroBreakDuration).map(\.
            newValue).sink { [weak self] new in self?.breakDuration = new }.store(in: &cancellables)
        Defaults.publisher(.pomodoroLongBreakDuration).map(\.
            newValue).sink { [weak self] new in self?.longBreakDuration = new }.store(in: &cancellables)
        Defaults.publisher(.pomodoroUseLongBreak).map(\.
            newValue).sink { [weak self] new in self?.useLongBreak = new }.store(in: &cancellables)
        Defaults.publisher(.pomodoroLongBreakAfter).map(\.
            newValue).sink { [weak self] new in self?.longBreakAfter = new }.store(in: &cancellables)
    }

    // Solicita permiso para notificaciones locales una vez.
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // Inicia o continúa
    func start() {
        guard !isRunning else { return }
        isRunning = true
        scheduleTimer()
    }

    // Pausa sin perder el tiempo restante
    func pause() {
        isRunning = false
        timer?.invalidate()
    }

    // Reinicia el ciclo actual (mantiene fase)
    func reset() {
        timer?.invalidate()
        isRunning = false
        remaining = isWorkPhase ? workDuration : currentBreakDuration()
    }

    // Determina duración del descanso según si toca descanso largo.
    private func currentBreakDuration() -> TimeInterval {
        if useLongBreak && completedWorkSessions > 0 && completedWorkSessions % longBreakAfter == 0 {
            return longBreakDuration
        }
        return breakDuration
    }

    // Avanza de fase y dispara notificación.
    private func advancePhase() {
        if isWorkPhase {
            completedWorkSessions += 1
            sendNotification(title: "Bloque completado", body: "Tiempo de descanso")
        } else {
            sendNotification(title: "Descanso terminado", body: "Vuelve al enfoque")
        }
        isWorkPhase.toggle()
        remaining = isWorkPhase ? workDuration : currentBreakDuration()
        start() // auto start siguiente fase
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            guard self.isRunning else { return }
            if self.remaining > 0 {
                self.remaining -= 1
            } else {
                self.isRunning = false
                self.timer?.invalidate()
                self.advancePhase()
            }
        }
        if let t = timer { RunLoop.current.add(t, forMode: .common) }
    }

    // Actualiza duraciones manualmente y persiste en Defaults.
    func updateDurations(work: Int, shortBreak: Int, longBreak: Int, useLong: Bool, longAfter: Int) {
        Defaults[.pomodoroWorkDuration] = Double(work * 60)
        Defaults[.pomodoroBreakDuration] = Double(shortBreak * 60)
        Defaults[.pomodoroLongBreakDuration] = Double(longBreak * 60)
        Defaults[.pomodoroUseLongBreak] = useLong
        Defaults[.pomodoroLongBreakAfter] = longAfter
        // Si no está corriendo, refleja inmediatamente en remaining.
        if !isRunning { remaining = isWorkPhase ? workDuration : currentBreakDuration() }
    }

    // Formatea mm:ss para la vista
    func formattedRemaining() -> String {
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
