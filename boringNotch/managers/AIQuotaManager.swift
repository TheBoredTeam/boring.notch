//
//  AIQuotaManager.swift
//  boringNotch
//

import Combine
import Defaults
import Foundation
import Security

@MainActor
final class AIQuotaManager: ObservableObject {
    static let shared = AIQuotaManager()

    @Published var claudeQuota: AIQuotaResult?
    @Published var codexQuota: AIQuotaResult?
    @Published var isLoading = false

    private var refreshTask: Task<Void, Never>?
    private var defaultsCancellable: AnyCancellable?
    private var refreshPolicy = AIQuotaRefreshPolicy()

    private init() {
        defaultsCancellable = Defaults.publisher(.showAIQuota)
            .sink { [weak self] change in
                Task { @MainActor in
                    if change.newValue {
                        self?.startAutoRefresh()
                    } else {
                        self?.stopAutoRefresh()
                        if BoringViewCoordinator.shared.currentView == .quota {
                            BoringViewCoordinator.shared.currentView = .home
                        }
                    }
                }
            }

        if Defaults[.showAIQuota] {
            startAutoRefresh()
        }
    }

    func startAutoRefresh() {
        guard Defaults[.showAIQuota] else { return }

        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.fetchAll()

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(120))
                } catch {
                    return
                }

                guard !Task.isCancelled else { return }
                await self.fetchAll()
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func fetchAll() async {
        guard Defaults[.showAIQuota] else { return }

        isLoading = true
        async let claude = fetchClaudeQuota()
        async let codex = fetchCodexQuota()

        let newClaude = await claude
        let newCodex = await codex

        if newClaude.success || claudeQuota == nil {
            claudeQuota = newClaude
        }
        if newCodex.success || codexQuota == nil {
            codexQuota = newCodex
        }
        isLoading = false
    }

    func fetchClaudeQuota() async -> AIQuotaResult {
        if !refreshPolicy.canRequest(.claude),
           let message = refreshPolicy.blockMessage(for: .claude) {
            print("[AIQuota] Claude: skipping usage fetch, \(message)")
            return .unavailable(
                provider: .claude,
                status: .valid,
                message: message
            )
        }

        // Try XPC helper first (file-based, no password prompt)
        let credentials = await XPCHelperClient.shared.readClaudeCredentials()
        let credentialStatus = CredentialStatus(rawStatus: credentials.status)
        print("[AIQuota] Claude credentials via XPC: status=\(credentials.status), hasToken=\(credentials.accessToken != nil), message=\(credentials.message ?? "nil")")

        if let token = credentials.accessToken, !token.isEmpty {
            return await fetchClaudeUsage(token: token, credentialStatus: credentialStatus)
        }

        // Fall back to Keychain (may trigger macOS password prompt on unsigned builds)
        let keychainToken = Self.readKeychainPasswordFromMainApp(service: "Claude Code-credentials")
        if let keychainToken, !keychainToken.isEmpty {
            print("[AIQuota] Claude: got token from main-app Keychain read")
            if let data = keychainToken.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let oauth = object["claudeAiOauth"] as? [String: Any] ?? object["claude.ai_oauth"] as? [String: Any],
               let accessToken = oauth["accessToken"] as? String, !accessToken.isEmpty {
                return await fetchClaudeUsage(token: accessToken, credentialStatus: .valid)
            }
        }

        return .unavailable(
            provider: .claude,
            status: credentialStatus,
            message: credentials.message
        )
    }

    private func fetchClaudeUsage(token: String, credentialStatus: CredentialStatus) async -> AIQuotaResult {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.timeoutInterval = 10
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let data = try await data(for: request, provider: .claude)
            let result = try AIQuotaParser.decodeClaudeQuota(from: data)
            refreshPolicy.recordSuccess(.claude)
            return result
        } catch let error as AIQuotaRequestError {
            switch error {
            case .rateLimited(let retryAfter):
                refreshPolicy.recordRateLimit(.claude, retryAfter: retryAfter)
                return .unavailable(
                    provider: .claude,
                    status: credentialStatus,
                    message: refreshPolicy.blockMessage(for: .claude) ?? "Rate limited. Will retry shortly."
                )
            case .expired:
                refreshPolicy.recordAuthFailure(.claude)
                return .unavailable(
                    provider: .claude,
                    status: .expired,
                    message: refreshPolicy.blockMessage(for: .claude) ?? "Token expired. Re-login with CLI."
                )
            case .api:
                return error.result(provider: .claude, fallbackStatus: credentialStatus)
            }
        } catch {
            return .unavailable(
                provider: .claude,
                status: credentialStatus,
                message: "Failed to parse Claude usage: \(error.localizedDescription)"
            )
        }
    }

    func fetchCodexQuota() async -> AIQuotaResult {
        let credentials = await XPCHelperClient.shared.readCodexCredentials()
        let credentialStatus = CredentialStatus(rawStatus: credentials.status)

        guard let token = credentials.accessToken, !token.isEmpty else {
            return .unavailable(
                provider: .codex,
                status: credentialStatus,
                message: credentials.message
            )
        }

        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.timeoutInterval = 10
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("codex-cli", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountId = credentials.accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        do {
            let data = try await data(for: request, provider: .codex)
            return try AIQuotaParser.decodeCodexQuota(from: data)
        } catch let error as AIQuotaRequestError {
            return error.result(provider: .codex, fallbackStatus: credentialStatus)
        } catch {
            return .unavailable(
                provider: .codex,
                status: credentialStatus,
                message: "Failed to parse Codex usage: \(error.localizedDescription)"
            )
        }
    }

    private func data(for request: URLRequest, provider: AIProvider) async throws -> Data {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIQuotaRequestError.api("Invalid response")
            }
            print("[AIQuota] \(provider.displayName): usage HTTP \(httpResponse.statusCode)")

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw AIQuotaRequestError.expired("Authentication failed. Re-login with \(provider.displayName) CLI.")
            }

            if httpResponse.statusCode == 429 {
                let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                    .flatMap(Int.init)
                throw AIQuotaRequestError.rateLimited(retryAfter: retryAfter)
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw AIQuotaRequestError.api("HTTP \(httpResponse.statusCode): \(body.truncatedForDisplay)")
            }

            return data
        } catch let error as AIQuotaRequestError {
            throw error
        } catch {
            throw AIQuotaRequestError.api("Network error: \(error.localizedDescription)")
        }
    }

    /// Read a Keychain password directly from the main app process.
    /// GUI apps can trigger the macOS Keychain authorization prompt.
    private static func readKeychainPasswordFromMainApp(service: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        print("[AIQuota] Main-app Keychain read for '\(service)': OSStatus \(status)")

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum AIQuotaRequestError: Error {
    case expired(String)
    case api(String)
    case rateLimited(retryAfter: Int?)

    func result(provider: AIProvider, fallbackStatus: CredentialStatus) -> AIQuotaResult {
        switch self {
        case .expired(let message):
            return .unavailable(provider: provider, status: .expired, message: message)
        case .api(let message):
            return .unavailable(provider: provider, status: fallbackStatus, message: message)
        case .rateLimited:
            return .unavailable(provider: provider, status: fallbackStatus, message: "Rate limited. Will retry shortly.")
        }
    }
}

private extension String {
    var truncatedForDisplay: String {
        guard count > 180 else { return self }
        return String(prefix(180)) + "..."
    }
}
