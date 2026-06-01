//
//  ScreenshotPreferences.swift
//  boringNotch
//
//  Purpose: Stateless facade over the screenshot `Defaults` keys. Mirrors the role
//           IslandNotch's AppPreferences played, but reads/writes through the one
//           settings system (the Defaults library) so there's a single source of truth.
//  Layer: Service
//

import Foundation
import Defaults

enum ScreenshotPreferences {
    // MARK: Reads

    static var captureLocation: CaptureLocation { Defaults[.screenshotCaptureLocation] }
    static var retentionDays: Int { Defaults[.screenshotRetentionDays] }
    static var doubleCommandEnabled: Bool { Defaults[.screenshotDoubleCommandEnabled] }
    static var autoCopySources: Set<CaptureSource> { Defaults[.screenshotAutoCopySources] }
    static var activeAgent: AgentTarget { Defaults[.screenshotActiveAgent] }
    static var customAgentName: String { Defaults[.screenshotCustomAgentName] }

    /// The clipboard payload mode for a given agent.
    static func payloadMode(for agent: AgentTarget) -> PayloadMode {
        switch agent {
        case .claudeCode: return Defaults[.screenshotPayloadModeClaudeCode]
        case .codex: return Defaults[.screenshotPayloadModeCodex]
        case .custom: return Defaults[.screenshotPayloadModeCustom]
        }
    }

    static func setPayloadMode(_ mode: PayloadMode, for agent: AgentTarget) {
        switch agent {
        case .claudeCode: Defaults[.screenshotPayloadModeClaudeCode] = mode
        case .codex: Defaults[.screenshotPayloadModeCodex] = mode
        case .custom: Defaults[.screenshotPayloadModeCustom] = mode
        }
    }

    /// Whether a screenshot from `source` should be auto-copied on capture.
    static func shouldAutoCopy(_ source: CaptureSource) -> Bool {
        autoCopySources.contains(source)
    }

    // MARK: Folder resolution

    /// Resolves (and lazily creates) the active capture folder. Returns nil if the
    /// folder couldn't be created.
    static func resolvedCaptureFolder() -> URL? {
        let folder = captureLocation.resolvedFolderURL()
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        } catch {
            Log.capture.error("failed to create capture folder \(folder.path): \(error.localizedDescription)")
            return nil
        }
    }

    /// A timestamped PNG filename, e.g. "Screenshot 2026-05-31 at 14.22.07-1A2B.png".
    /// The short random suffix guards against two captures within the same second.
    static func makeTimestampFilename() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let suffix = UUID().uuidString.prefix(4)
        return "Screenshot \(formatter.string(from: Date()))-\(suffix).png"
    }
}
