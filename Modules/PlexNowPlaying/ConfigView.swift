//
//  ConfigView.swift
//  boringNotch (Plex Module)
//

import SwiftUI
import Defaults

public struct ConfigView: View {

    // MARK: - Defaults (ver Defaults+Discogs.swift)
    @Default(.pmsURL)        private var pmsURL
    @Default(.plexToken)     private var plexToken
    @Default(.enableDiscogs) private var enableDiscogs
    @Default(.discogsToken)  private var discogsToken
    @Default(.enricherURL)   private var enricherURL

    @ObservedObject private var vm = PlexNowPlayingViewModel.shared

    public init() {}

    public var body: some View {
        Form {
            plexSection
            discogsSection
            statusSection
        }
        // Ya no arranca el poller aquí.
        // Solo reconsulta Facts cuando cambian los campos relevantes.
        .onChangeTrigger(of: enableDiscogs) { Task { await vm.forceRefresh() } }
        .onChangeTrigger(of: discogsToken)  { Task { await vm.forceRefresh() } }
        .onChangeTrigger(of: enricherURL)   { Task { await vm.forceRefresh() } }
        .frame(minWidth: 520)
    }

    // MARK: - Secciones

    private var plexSection: some View {
        Section(header: Text("Plex Media Server")) {
            TextField("PMS URL (ej. http://127.0.0.1:32400)", text: $pmsURL)
                .textTweaksForCurrentPlatform()

            SecureField("Plex Token", text: $plexToken)
                .textTweaksForCurrentPlatform()

            Button("Probar conexión / Reiniciar poller") {
                startOrRestartPlex()
            }
        }
    }

    private var discogsSection: some View {
        Section(header: Text("Discogs (enriquecimiento)")) {
            Toggle("Habilitar Discogs", isOn: $enableDiscogs)

            SecureField("Discogs Token", text: $discogsToken)
                .textTweaksForCurrentPlatform()

            TextField("Enricher URL (opcional)", text: $enricherURL)
                .textTweaksForCurrentPlatform()

            Button("Refrescar datos del álbum") {
                Task { await vm.forceRefresh() }
            }
        }
    }

    private var statusSection: some View {
        Section(header: Text("Estado")) {
            HStack {
                Text("Now Playing")
                Spacer()
                if let np = vm.snapshotNowPlaying {
                    Text("\(np.artist) — \(np.album)")
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    Text("—").foregroundColor(.secondary)
                }
            }

            HStack {
                Text("Facts")
                Spacer()
                Text(vm.state.label)
                    .foregroundColor(vm.state.color)
            }
        }
    }

    // MARK: - Helpers

    private func startOrRestartPlex() {
        let trimmedURL = pmsURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTok = plexToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL), !trimmedTok.isEmpty else { return }
        PlexNowPlayingViewModel.shared.startPlexPolling(baseURL: url, token: trimmedTok)
    }
}

// MARK: - UI helpers para FactsState (enum global)

private extension FactsState {
    var label: String {
        switch self {
        case .idle:    return "Idle"
        case .loading: return "Cargando"
        case .ready:   return "Listo"
        case .error:   return "Error"
        }
    }
    var color: Color {
        switch self {
        case .idle:    return .secondary
        case .loading: return .orange
        case .ready:   return .green
        case .error:   return .red
        }
    }
}

// MARK: - Modificadores compatibles

private extension View {
    /// Aplica tweaks de texto solamente donde existen (iOS); en macOS no hace nada.
    @ViewBuilder
    func textTweaksForCurrentPlatform() -> some View {
        #if os(iOS)
        self
            .autocapitalization(.none)
            .disableAutocorrection(true)
        #else
        self
        #endif
    }

    /// Wrapper para `onChange` compatible con macOS 11+ / iOS 14+ sin warnings deprecados.
    @ViewBuilder
    func onChangeTrigger<T: Equatable>(of value: T, perform action: @escaping () -> Void) -> some View {
        if #available(macOS 14.0, iOS 17.0, *) {
            self.onChange(of: value) { _, _ in action() }
        } else {
            self.onChange(of: value, perform: { _ in action() })
        }
    }
}
