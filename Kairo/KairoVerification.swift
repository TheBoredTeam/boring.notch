//
//  KairoVerification.swift
//  Kairo — System verification + command history + live data
//
//  Runs all checks on launch. Prints results to console.
//  Also provides command history persistence.
//

import AVFoundation
import EventKit
import SwiftUI
import UserNotifications

// ═══════════════════════════════════════════
// MARK: - Verification
// ═══════════════════════════════════════════

class KairoVerification {
    private static var log: [String] = []
    private static func L(_ msg: String) { log.append(msg); NSLog("KAIRO: %@", msg) }

    static func runAll() async {
        log = []
        L("╔═══════════════════════════════╗")
        L("║   KAIRO SYSTEM VERIFICATION   ║")
        L("╚═══════════════════════════════╝")

        checkEnvFile()
        await checkKairoBackend()
        checkAccessibility()
        checkMicrophone()
        await checkCalendar()

        L("═══ VERIFICATION COMPLETE ═══")

        // Write to file for easy reading
        let output = log.joined(separator: "\n")
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".kairo_verification.txt")
        try? output.write(to: path, atomically: true, encoding: .utf8)
    }

    static func checkEnvFile() {
        L("── ENVIRONMENT ──")
        let keys = ["ANTHROPIC_API_KEY", "OPENAI_API_KEY", "ELEVENLABS_API_KEY", "ELEVENLABS_VOICE_ID",
                     "HA_URL", "HA_TOKEN", "OPENROUTER_API_KEY", "SPOTIFY_CLIENT_ID", "YOUTUBE_API_KEY"]
        for key in keys {
            let val = ProcessInfo.processInfo.environment[key] ?? ""
            if val.isEmpty {
                L("  [  ] \(key): not set")
            } else {
                L("  [OK] \(key): \(String(val.prefix(8)))...")
            }
        }
    }

    static func checkKairoBackend() async {
        L("\n── KAIRO BACKEND ──")
        let serverURL = UserDefaults.standard.string(forKey: "kairoServerURL")?.replacingOccurrences(of: "/ws", with: "").replacingOccurrences(of: "ws://", with: "http://") ?? "http://localhost:8420"

        guard let url = URL(string: "\(serverURL)/health") else { print("  [!!] Invalid server URL"); return }
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let name = json["name"] as? String {
                    L("  [OK] Backend: \(name) v\(json["version"] ?? "?")")
                }
            } else { print("  [!!] Backend: status \((resp as? HTTPURLResponse)?.statusCode ?? 0)") }
        } catch { print("  [!!] Backend: \(error.localizedDescription)") }

        // Check WebSocket
        L("  [\(KairoSocket.shared.isConnected ? "OK" : "  ")] WebSocket: \(KairoSocket.shared.isConnected ? "connected" : "disconnected")")
    }

    static func checkAccessibility() {
        L("\n── PERMISSIONS ──")
        let ax = AXIsProcessTrusted()
        L("  [\(ax ? "OK" : "!!")] Accessibility: \(ax ? "granted" : "DENIED — open System Settings")")
    }

    static func checkMicrophone() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: print("  [OK] Microphone: authorized")
        case .denied:     print("  [!!] Microphone: DENIED")
        case .notDetermined: print("  [  ] Microphone: not requested")
        default: print("  [  ] Microphone: unknown")
        }
    }

    static func checkCalendar() async {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess, .authorized:
            let store = EKEventStore()
            let start = Calendar.current.startOfDay(for: Date())
            let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
            let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
            L("  [OK] Calendar: \(events.count) events today")
        case .denied: print("  [!!] Calendar: DENIED")
        default: print("  [  ] Calendar: not requested")
        }
    }
}

// ═══════════════════════════════════════════
// MARK: - Command History (persisted)
// ═══════════════════════════════════════════

class KairoCommandHistory: ObservableObject {
    static let shared = KairoCommandHistory()

    struct Item: Codable, Identifiable {
        let id: UUID
        let command: String
        let timestamp: Date
        var timeAgo: String {
            let d = Date().timeIntervalSince(timestamp)
            if d < 60 { return "now" }
            if d < 3600 { return "\(Int(d/60))m" }
            return "\(Int(d/3600))h"
        }
    }

    @Published var recent: [Item] = []
    private let key = "kairo.cmd.history"

    init() { load() }

    func add(_ command: String) {
        let item = Item(id: UUID(), command: command, timestamp: Date())
        recent.insert(item, at: 0)
        if recent.count > 15 { recent = Array(recent.prefix(15)) }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(recent) { UserDefaults.standard.set(data, forKey: key) }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let items = try? JSONDecoder().decode([Item].self, from: data) { recent = items }
    }
}
