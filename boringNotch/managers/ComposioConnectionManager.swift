//
//  ComposioConnectionManager.swift
//  boringNotch
//
//  Tracks Composio connected-account health out of band, replacing the old in-notch
//  "Connect" CTA. The actual Composio v3 SDK work lives in the pi-sidecar (it owns the
//  Composio login); this manager is the Swift-side mirror of that state and the place
//  the UI reads from / drives reconnection through.
//
//  Wire path: PiAgentManager owns the sidecar process and decodes its events. It
//  forwards `connections` / `connection_expired` / `connection_link` here, and this
//  manager issues `list_connections` / `reconnect` / `connect` / `set_default` back
//  through PiAgentManager's stdin. The default-account map is owned by the sidecar
//  (it writes the extension config file); this manager only mirrors it for the UI.
//

import AppKit
import Foundation

@MainActor
final class ComposioConnectionManager: ObservableObject {
    static let shared = ComposioConnectionManager()

    /// Traffic-light bucket for a connection's status: 🟢 healthy, 🟡 in progress,
    /// 🔴 needs the user's attention (expired/failed/etc.).
    enum StatusTier: Equatable {
        case active    // 🟢 ACTIVE
        case pending   // 🟡 INITIALIZING / INITIATED
        case attention // 🔴 EXPIRED / FAILED / INACTIVE / REVOKED / unknown
    }

    /// One connected account for a toolkit.
    struct Connection: Identifiable, Equatable {
        let alias: String?
        let wordId: String?  // Composio human word id (selector fallback after alias)
        let connectedAccountId: String
        let authConfigId: String?
        let status: String   // ACTIVE | INITIALIZING | INACTIVE | FAILED | EXPIRED | REVOKED
        let logo: String?    // toolkit brand logo URL (Composio metadata)

        var id: String { connectedAccountId }
        /// Display/selector identity, in the order the user prefers: alias → wordId → id.
        var displayName: String { alias ?? wordId ?? connectedAccountId }
        /// What we write as the default selector (the agent resolver matches all three).
        var selector: String { alias ?? wordId ?? connectedAccountId }
        /// Composio statuses that mean the account can't be used until re-authorized.
        var needsReauth: Bool {
            ["EXPIRED", "INACTIVE", "REVOKED", "FAILED"].contains(status.uppercased())
        }
        /// 3-way mapping driving the status dot color (see `StatusTier`).
        var statusTier: StatusTier {
            switch status.uppercased() {
            case "ACTIVE": return .active
            case "INITIALIZING", "INITIATED": return .pending
            default: return .attention
            }
        }
    }

    /// A toolkit/account that needs the user to re-authorize. Drives the reconnect UI.
    struct ConnectionNeed: Identifiable, Equatable {
        let toolkit: String
        let alias: String?
        let connectedAccountId: String
        let status: String

        var id: String { connectedAccountId }
    }

    /// Live inventory, grouped by toolkit slug (e.g. "gmail" → [work, personal]).
    @Published private(set) var connections: [String: [Connection]] = [:]
    /// Toolkit slug → brand logo URL, resolved from Composio metadata by the sidecar.
    @Published private(set) var toolkitLogos: [String: String] = [:]
    /// Accounts currently needing re-auth (expired/revoked/…). Surfaced in PiSettings.
    @Published private(set) var reauthNeeded: [ConnectionNeed] = []

    /// Per-toolkit default account selector (lowercased slug → alias/wordId/ca_ id). The
    /// agent uses this to pick the right account automatically. The source of truth is the
    /// extension config file the sidecar owns; this mirror is populated from the sidecar's
    /// `connections` event `defaults` field (never UserDefaults), so UI and agent agree.
    @Published private(set) var defaultAliases: [String: String] = [:]

    private init() {}

    /// Sorted toolkit slugs that have at least one connected account.
    var toolkits: [String] { connections.keys.sorted() }

    // MARK: - Inbound (called by PiAgentManager from sidecar events)

    /// Replace the inventory from a `connections` event and recompute re-auth needs.
    /// `defaults` (when present) is the file-sourced default-account map — adopt it so the
    /// UI ★ always reflects the agent's actual source of truth.
    func applyConnections(_ items: [PiConnectionItem], defaults: [String: String]? = nil) {
        if let defaults {
            defaultAliases = Dictionary(uniqueKeysWithValues: defaults.map { ($0.key.lowercased(), $0.value) })
        }
        var grouped: [String: [Connection]] = [:]
        var logos: [String: String] = [:]
        for item in items {
            let slug = item.toolkit.lowercased()
            guard !slug.isEmpty else { continue }
            grouped[slug, default: []].append(
                Connection(
                    alias: item.alias,
                    wordId: item.wordId,
                    connectedAccountId: item.connectedAccountId,
                    authConfigId: item.authConfigId,
                    status: item.status,
                    logo: item.logo
                )
            )
            if let logo = item.logo, !logo.isEmpty, logos[slug] == nil {
                logos[slug] = logo
            }
        }
        connections = grouped
        toolkitLogos = logos

        // Rebuild reauthNeeded straight from the inventory so a now-healthy account
        // clears itself (a stale "live" event can't keep a resolved need pinned).
        reauthNeeded = grouped.flatMap { slug, accounts in
            accounts.filter(\.needsReauth).map {
                ConnectionNeed(toolkit: slug, alias: $0.alias, connectedAccountId: $0.connectedAccountId, status: $0.status)
            }
        }
        .sorted { $0.toolkit < $1.toolkit }
    }

    /// Flag a single account from a live `connection_expired` event (between full lists).
    func markReauthNeeded(toolkit: String, alias: String?, connectedAccountId: String, status: String) {
        let slug = toolkit.lowercased()
        guard !reauthNeeded.contains(where: { $0.connectedAccountId == connectedAccountId }) else { return }
        reauthNeeded.append(
            ConnectionNeed(toolkit: slug, alias: alias, connectedAccountId: connectedAccountId, status: status)
        )
        reauthNeeded.sort { $0.toolkit < $1.toolkit }
    }

    /// Open the hosted auth URL returned by a `reconnect`, then refresh once the user
    /// has had a moment to complete it.
    func openConnectionLink(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    // MARK: - Outbound (UI → sidecar)

    /// Pull a fresh inventory (e.g. when PiSettings opens, or after a reconnect).
    func refresh() {
        PiAgentManager.shared.requestConnections()
    }

    /// Start hosted re-auth for a need; the sidecar replies with a `connection_link`.
    func reconnect(_ need: ConnectionNeed) {
        PiAgentManager.shared.reconnect(connectedAccountId: need.connectedAccountId, toolkit: need.toolkit)
    }

    /// Set (or clear, with nil) the default account selector for a toolkit. Writes
    /// through the sidecar to the extension config file (the agent's source of truth);
    /// the resulting `connections` event reconciles `defaultAliases` back. The local
    /// value is updated optimistically so the UI ★ flips immediately, before the round-trip.
    func setDefaultAlias(_ alias: String?, for toolkit: String) {
        let slug = toolkit.lowercased()
        let selector = alias ?? ""
        if selector.isEmpty {
            defaultAliases.removeValue(forKey: slug)
        } else {
            defaultAliases[slug] = selector
        }
        PiAgentManager.shared.setDefaultAccount(toolkit: slug, selector: selector)
    }

    /// Set (or, with an empty/whitespace alias, clear) the human-readable alias for an
    /// account. Composio accounts connected via the CLI or the agent arrive without one,
    /// so this is how the user labels them "work"/"personal" and gets them to show. The
    /// sidecar persists it and re-emits `connections`, which relabels the row.
    func renameConnection(_ connection: Connection, toolkit: String, alias: String) {
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        PiAgentManager.shared.renameConnection(connectedAccountId: connection.connectedAccountId, alias: trimmed)
    }

    /// Permanently disconnect an account. Optimistically drop it from the local inventory
    /// so the row disappears immediately; the sidecar's re-list reconciles the truth.
    func deleteConnection(_ connection: Connection, toolkit: String) {
        let slug = toolkit.lowercased()
        if var accounts = connections[slug] {
            accounts.removeAll { $0.connectedAccountId == connection.connectedAccountId }
            if accounts.isEmpty { connections.removeValue(forKey: slug) }
            else { connections[slug] = accounts }
        }
        reauthNeeded.removeAll { $0.connectedAccountId == connection.connectedAccountId }
        PiAgentManager.shared.deleteConnection(connectedAccountId: connection.connectedAccountId)
    }

    /// Authorize a NEW account for a toolkit out of band; the sidecar replies with a
    /// `connection_link` opened in the browser. No agent involvement, no transcript URL.
    func connect(toolkit: String, alias: String? = nil) {
        PiAgentManager.shared.connect(toolkit: toolkit, alias: alias)
    }

    /// Called by PiAgentManager once the sidecar process is up: request the initial
    /// inventory. The sidecar owns default-account persistence, so nothing is pushed.
    func sidecarDidLaunch() {
        PiAgentManager.shared.requestConnections()
    }
}
