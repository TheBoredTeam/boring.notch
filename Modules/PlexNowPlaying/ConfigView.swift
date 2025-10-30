//
//  ConfigView.swift
//  BoringNotch (Plex Module)
//
//  Configuración de PMS y Enricher con control de polling.
//  El token se guarda en Keychain (no se expone).
//

import SwiftUI
import Security

public struct ConfigView: View {
    @AppStorage("PMS_URL") private var pmsURL: String = "http://127.0.0.1:32400"
    @AppStorage("ENRICHER_URL") private var enricherURL: String = "http://127.0.0.1:5173"

    @State private var token: String = ""
    @State private var isPolling: Bool = false
    @State private var statusMsg: String = ""

    // 🔴 Usa SIEMPRE el singleton para que la UI vea los cambios del polling
    @StateObject private var vm = PlexNowPlayingViewModel.shared

    public init() {}

    public var body: some View {
        Form {
            Section(header: Text("Plex Media Server")) {
                TextField("PMS URL", text: $pmsURL)
                    .textFieldStyle(.roundedBorder)

                // Token seguro (solo en memoria y Keychain)
                SecureField("X-Plex-Token", text: $token)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Guardar Token") {
                        KeychainStore.shared.saveToken(token)
                        statusMsg = "🔒 Token guardado en Keychain"
                    }

                    Button(isPolling ? "Detener Polling" : "Iniciar Polling") {
                        Task { await togglePolling() }
                    }
                }

                Button("Probar conexión con Plex") {
                    Task { await probeOnce() }
                }

                if !statusMsg.isEmpty {
                    Text(statusMsg)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }

            Section(header: Text("Enricher API")) {
                TextField("Base URL", text: $enricherURL)
                    .textFieldStyle(.roundedBorder)
                Text("El Enricher se usa desde el ViewModel. Asegúrate de que está activo en \(enricherURL).")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 420)
        .onAppear {
            token = KeychainStore.shared.loadToken() ?? ""
        }
    }

    // MARK: - Acciones

    private func togglePolling() async {
        if isPolling {
            await MainActor.run {
                vm.stopPlexPolling()
                isPolling = false
                statusMsg = "⏹️ Polling detenido"
            }
        } else {
            guard let url = URL(string: pmsURL), !token.isEmpty else {
                statusMsg = "⚠️ Configura URL y Token antes de iniciar"
                return
            }
            await MainActor.run {
                vm.startPlexPolling(baseURL: url, token: token)
                isPolling = true
                statusMsg = "▶️ Polling iniciado contra \(url.absoluteString)"
            }
        }
    }

    private func probeOnce() async {
        guard let url = URL(string: pmsURL), !token.isEmpty else {
            statusMsg = "⚠️ URL o token inválidos"
            return
        }
        statusMsg = "🔄 Probando conexión…"
        let client = PlexClient(baseURL: url, token: token, debugLogging: true)
        await client.pollOnce()
        statusMsg = "✅ Solicitud enviada (revisa la consola para logs)"
    }
}

// MARK: - Keychain

public final class KeychainStore {
    public static let shared = KeychainStore()
    private init() {}

    public func saveToken(_ token: String) {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "plex_token",
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    public func loadToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "plex_token",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
}
