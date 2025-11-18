import Foundation
import Defaults

// Claves de configuración para el temporizador Pomodoro
extension Defaults.Keys {
    static let pomodoroWorkDuration = Key<Double>("pomodoroWorkDuration", default: 25 * 60)
    static let pomodoroBreakDuration = Key<Double>("pomodoroBreakDuration", default: 5 * 60)
    static let pomodoroLongBreakDuration = Key<Double>("pomodoroLongBreakDuration", default: 15 * 60)
    static let pomodoroUseLongBreak = Key<Bool>("pomodoroUseLongBreak", default: true)
    static let pomodoroLongBreakAfter = Key<Int>("pomodoroLongBreakAfter", default: 4)
}
