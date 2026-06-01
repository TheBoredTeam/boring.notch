//  AppPreferences.swift
//  IslandNotch
//
//  Purpose: Observable, UserDefaults-backed settings. SwiftUI views read these
//           directly; mutations persist via didSet.
//  Layer: Service

import Foundation
import Observation

@Observable
final class AppPreferences {
    @ObservationIgnored private let defaults: UserDefaults

    // MARK: Stored, persisted settings

    /// Where screenshots are saved.
    var captureLocation: CaptureLocation {
        didSet { defaults.set(captureLocation.rawValue, forKey: Keys.captureLocation) }
    }

    /// Delete shots older than this many days. 0 = never sweep.
    var retentionDays: Int {
        didSet { defaults.set(retentionDays, forKey: Keys.retentionDays) }
    }

    /// Whether the double-⌘ CGEventTap gesture is active (requires Accessibility).
    var doubleCommandEnabled: Bool {
        didSet { defaults.set(doubleCommandEnabled, forKey: Keys.doubleCommandEnabled) }
    }

    /// Capture sources whose screenshots are auto-copied to the clipboard.
    /// Default: double-⌘ and the keyboard chord; drag/drop and menu are manual.
    var autoCopySources: Set<CaptureSource> {
        didSet {
            defaults.set(autoCopySources.map(\.rawValue), forKey: Keys.autoCopySources)
        }
    }

    /// The agent that left-click / auto-copy formats payloads for.
    var activeAgent: AgentTarget {
        didSet { defaults.set(activeAgent.rawValue, forKey: Keys.activeAgent) }
    }

    /// Optional display name for the "custom" agent.
    var customAgentName: String {
        didSet { defaults.set(customAgentName, forKey: Keys.customAgentName) }
    }

    // MARK: Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        self.captureLocation = (defaults.string(forKey: Keys.captureLocation))
            .flatMap(CaptureLocation.init(rawValue:)) ?? .desktopIslandShots
        self.retentionDays = defaults.integer(forKey: Keys.retentionDays) // 0 if unset
        if defaults.object(forKey: Keys.doubleCommandEnabled) == nil {
            self.doubleCommandEnabled = true
        } else {
            self.doubleCommandEnabled = defaults.bool(forKey: Keys.doubleCommandEnabled)
        }

        if let raw = defaults.array(forKey: Keys.autoCopySources) as? [String] {
            self.autoCopySources = Set(raw.compactMap(CaptureSource.init(rawValue:)))
        } else {
            self.autoCopySources = [.doubleCommand, .chord] // first-run default
        }

        self.activeAgent = (defaults.string(forKey: Keys.activeAgent))
            .flatMap(AgentTarget.init(rawValue:)) ?? .claudeCode
        self.customAgentName = defaults.string(forKey: Keys.customAgentName) ?? "Custom"
    }

    // MARK: Per-agent payload mode

    /// The clipboard payload mode for a given agent, falling back to its default.
    func payloadMode(for agent: AgentTarget) -> PayloadMode {
        guard let raw = defaults.string(forKey: Keys.payloadMode(agent)),
              let mode = PayloadMode(rawValue: raw) else {
            return agent.defaultPayloadMode
        }
        return mode
    }

    func setPayloadMode(_ mode: PayloadMode, for agent: AgentTarget) {
        defaults.set(mode.rawValue, forKey: Keys.payloadMode(agent))
        // Touch an observed property so dependent views refresh.
        activeAgent = activeAgent
    }

    /// Whether a screenshot from `source` should be auto-copied on capture.
    func shouldAutoCopy(_ source: CaptureSource) -> Bool {
        autoCopySources.contains(source)
    }

    // MARK: Keys

    private enum Keys {
        static let captureLocation = "pref.captureLocation"
        static let retentionDays = "pref.retentionDays"
        static let doubleCommandEnabled = "pref.doubleCommandEnabled"
        static let autoCopySources = "pref.autoCopySources"
        static let activeAgent = "pref.activeAgent"
        static let customAgentName = "pref.customAgentName"
        static func payloadMode(_ agent: AgentTarget) -> String { "pref.payloadMode.\(agent.rawValue)" }
    }
}
