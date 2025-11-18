import SwiftUI

struct PomodoroView: View {
    @ObservedObject var manager = PomodoroManager.shared
    // Estados locales en minutos para edición
    @State private var workMinutes: Int = 25
    @State private var breakMinutes: Int = 5
    @State private var longBreakMinutes: Int = 15
    @State private var useLongBreak: Bool = true
    @State private var longBreakAfter: Int = 4
    @State private var showSettings: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            // Temporizador principal
            VStack(spacing: 8) {
                Text(manager.isWorkPhase ? "Trabajo" : "Descanso")
                    .font(.title3).bold()
                Text(manager.formattedRemaining())
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                ProgressView(value: progressValue)
                    .progressViewStyle(.linear)
            }

            HStack(spacing: 12) {
                Button(manager.isRunning ? "Pausar" : "Iniciar") {
                    manager.isRunning ? manager.pause() : manager.start()
                }
                Button("Reset") { manager.reset() }
                Button(showSettings ? "Ocultar" : "Config") {
                    toggleSettings()
                }
            }
            .buttonStyle(.borderedProminent)

            Text("Sesiones completadas: \(manager.completedWorkSessions)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if showSettings { settingsSection }
        }
        .onAppear(perform: syncFromManager)
        .padding(20)
        .frame(width: 320)
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Configuración")
                .font(.headline)
            durationRow(title: "Trabajo", minutes: $workMinutes, range: 5...120)
            durationRow(title: "Descanso corto", minutes: $breakMinutes, range: 1...30)
            Toggle("Usar descanso largo", isOn: $useLongBreak)
            if useLongBreak {
                durationRow(title: "Descanso largo", minutes: $longBreakMinutes, range: 5...60)
                Stepper(value: $longBreakAfter, in: 2...10) {
                    Text("Cada \(longBreakAfter) sesiones")
                }
            }
            Button("Guardar cambios") { persistSettings() }
                .buttonStyle(.bordered)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func durationRow(title: String, minutes: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack {
            Text(title).frame(width: 110, alignment: .leading)
            Stepper(value: minutes, in: range) {
                Text("\(minutes.wrappedValue) min")
            }
        }
    }

    private func syncFromManager() {
        workMinutes = Int(manager.workDuration / 60)
        breakMinutes = Int(manager.breakDuration / 60)
        longBreakMinutes = Int(manager.longBreakDuration / 60)
        useLongBreak = manager.useLongBreak
        longBreakAfter = manager.longBreakAfter
    }

    private func persistSettings() {
        manager.updateDurations(work: workMinutes, shortBreak: breakMinutes, longBreak: longBreakMinutes, useLong: useLongBreak, longAfter: longBreakAfter)
    }

    private func toggleSettings() { withAnimation { showSettings.toggle() } }

    var progressValue: Double {
        let total = manager.isWorkPhase ? manager.workDuration : (manager.useLongBreak && manager.completedWorkSessions % manager.longBreakAfter == 0 && !manager.isWorkPhase ? manager.longBreakDuration : manager.breakDuration)
        guard total > 0 else { return 0 }
        return 1 - (manager.remaining / total)
    }
}

#Preview { PomodoroView() }
