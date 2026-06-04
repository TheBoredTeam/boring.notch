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
//  manager issues `list_connections` / `reconnect` / `set_default_aliases` back through
//  PiAgentManager's stdin.
//

import AppKit
import Foundation

@MainActor
final class ComposioConnectionManager: ObservableObject {
    static let shared = ComposioConnectionManager()

    /// One connected account for a toolkit.
    struct Connection: Identifiable, Equatable {
        let alias: String?
        let connectedAccountId: String
        let authConfigId: String?
        let status: String   // ACTIVE | INITIALIZING | INACTIVE | FAILED | EXPIRED | REVOKED

        var id: String { connectedAccountId }
        /// Composio statuses that mean the account can't be used until re-authorized.
        var needsReauth: Bool {
            ["EXPIRED", "INACTIVE", "REVOKED", "FAILED"].contains(status.uppercased())
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
    /// Accounts currently needing re-auth (expired/revoked/…). Surfaced in PiSettings.
    @Published private(set) var reauthNeeded: [ConnectionNeed] = []

    /// Per-toolkit default account alias. The agent uses this to pick the right account
    /// automatically (pushed to the sidecar, folded into its system prompt).
    @Published var defaultAliases: [String: String] {
        didSet {
            guard defaultAliases != oldValue else { return }
            UserDefaults.standard.set(defaultAliases, forKey: Self.defaultAliasesKey)
            PiAgentManager.shared.setDefaultAliases(defaultAliases)
        }
    }

    private static let defaultAliasesKey = "pi.composio.defaultAliases"

    private init() {
        defaultAliases = (UserDefaults.standard.dictionary(forKey: Self.defaultAliasesKey) as? [String: String]) ?? [:]
    }

    /// Sorted toolkit slugs that have at least one connected account.
    var toolkits: [String] { connections.keys.sorted() }

    // MARK: - Inbound (called by PiAgentManager from sidecar events)

    /// Replace the inventory from a `connections` event and recompute re-auth needs.
    func applyConnections(_ items: [PiConnectionItem]) {
        var grouped: [String: [Connection]] = [:]
        for item in items {
            let slug = item.toolkit.lowercased()
            guard !slug.isEmpty else { continue }
            grouped[slug, default: []].append(
                Connection(
                    alias: item.alias,
                    connectedAccountId: item.connectedAccountId,
                    authConfigId: item.authConfigId,
                    status: item.status
                )
            )
        }
        connections = grouped

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

    /// Set (or clear, with nil) the default account alias for a toolkit.
    func setDefaultAlias(_ alias: String?, for toolkit: String) {
        let slug = toolkit.lowercased()
        if let alias, !alias.isEmpty {
            defaultAliases[slug] = alias
        } else {
            defaultAliases.removeValue(forKey: slug)
        }
    }

    /// Called by PiAgentManager once the sidecar process is up: push current defaults
    /// and request the initial inventory.
    func sidecarDidLaunch() {
        if !defaultAliases.isEmpty {
            PiAgentManager.shared.setDefaultAliases(defaultAliases)
        }
        PiAgentManager.shared.requestConnections()
    }
}
