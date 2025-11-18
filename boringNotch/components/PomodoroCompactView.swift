import SwiftUI

struct PomodoroCompactView: View {
    @ObservedObject var manager = PomodoroManager.shared

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: manager.isWorkPhase ? "hourglass" : "cup.and.saucer")
                .font(.system(size: 10, weight: .semibold))
            Text(manager.formattedRemaining())
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(manager.isWorkPhase ? .white : .green)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.black.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .help("Pomodoro activo: clic en menú para abrir")
        .accessibilityLabel("Pomodoro restante")
        .accessibilityValue(manager.formattedRemaining())
        .animation(.smooth, value: manager.isWorkPhase)
    }
}

#Preview { PomodoroCompactView() }
