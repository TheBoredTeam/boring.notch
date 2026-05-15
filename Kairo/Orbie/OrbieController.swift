import SwiftUI
import Combine

@MainActor
final class OrbieController: ObservableObject {
    enum Mode: Equatable {
        case idle
        case listening
        case expanded(OrbieViewID, payload: AnyHashable?)

        static func == (lhs: Mode, rhs: Mode) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.listening, .listening): return true
            case (.expanded(let a, _), .expanded(let b, _)): return a == b
            default: return false
            }
        }
    }

    @Published private(set) var mode: Mode = .idle
    @Published private(set) var voiceState: VoiceState = .idle
    private var dismissTask: Task<Void, Never>?

    var currentSize: OrbieSize {
        switch mode {
        case .idle, .listening: return .orb
        case .expanded(let id, _):
            return ViewRegistry.config(for: id)?.size ?? .orb
        }
    }

    func show(_ id: OrbieViewID, payload: AnyHashable? = nil) {
        dismissTask?.cancel()
        mode = .expanded(id, payload: payload)

        if let after = ViewRegistry.config(for: id)?.dismissAfter {
            dismissTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(after))
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.hide() }
            }
        }
    }

    func hide() {
        dismissTask?.cancel()
        mode = .idle
    }

    func startListening() { mode = .listening }
    func stopListening()  { if case .listening = mode { mode = .idle } }

    func setVoiceState(_ state: VoiceState) {
        voiceState = state
    }

    func updateAmplitude(_ amp: Float) {
        switch voiceState {
        case .listening:
            voiceState = .listening(amplitude: amp)
        case .speaking:
            voiceState = .speaking(amplitude: amp)
        default:
            break
        }
    }
}
