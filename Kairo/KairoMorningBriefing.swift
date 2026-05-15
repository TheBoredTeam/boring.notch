//
//  KairoMorningBriefing.swift
//  Kairo — Morning briefing on wake/login
//
//  Triggers when Mac wakes from sleep or user logs in.
//  Gathers: weather, home status, calendar, emails.
//  Builds briefing with Claude, speaks via ElevenLabs.
//

import AVFoundation
import Combine
import EventKit
import SwiftUI

class KairoMorningBriefing: ObservableObject {
    static let shared = KairoMorningBriefing()

    @Published var isBriefingActive = false
    @Published var briefingText = ""
    @Published var briefingWords: [String] = []

    var hasGreetedToday = false
    private var greetedDate: Date?
    private var audioPlayer: AVAudioPlayer?

    // MARK: - Start Listening

    func startListening() {
        // Wake from sleep
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)

        // Screen unlock is handled by KairoApp.triggerJarvisWelcome() — no observer here to avoid duplicate voices

        // Fresh boot check
        var tv = timeval()
        var tvSize = MemoryLayout<timeval>.size
        sysctlbyname("kern.boottime", &tv, &tvSize, nil, 0)
        let bootDate = Date(timeIntervalSince1970: Double(tv.tv_sec))
        if Date().timeIntervalSince(bootDate) < 120 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { self.triggerBriefing() }
        }

        print("[KairoBriefing] Listening for wake/login")
    }

    @objc private func systemDidWake(_ n: Notification) {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 5 && hour < 12 && !hasGreetedToday {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.triggerBriefing() }
        } else if hour >= 12 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.triggerQuickUpdate() }
        }
    }

    // MARK: - Trigger Briefing

    func triggerBriefing() {
        hasGreetedToday = true
        greetedDate = Date()
        isBriefingActive = true

        // Open the notch
        NotificationCenter.default.post(name: .kairoVoiceActivated, object: nil)

        Task {
            let cal = await fetchCalendar()
            let emails = await fetchUnreadEmails()
            let briefing = await buildBriefing(calendar: cal, emails: emails)

            await MainActor.run {
                self.briefingText = briefing
                self.animateWords(briefing)
                self.speakWithElevenLabs(briefing)
            }
        }
    }

    func triggerQuickUpdate() {
        let hour = Calendar.current.component(.hour, from: Date())
        let greeting = hour < 17 ? "afternoon" : "evening"
        let message = "Welcome back. Good \(greeting)."

        isBriefingActive = true
        NotificationCenter.default.post(name: .kairoVoiceActivated, object: nil)

        briefingText = message
        animateWords(message)
        speakWithSystem(message)

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.dismiss() }
    }

    // MARK: - Fetch Calendar (EventKit)

    private func fetchCalendar() async -> (count: Int, next: String?) {
        let store = EKEventStore()
        return await withCheckedContinuation { cont in
            store.requestFullAccessToEvents { granted, _ in
                guard granted else { cont.resume(returning: (0, nil)); return }
                let start = Calendar.current.startOfDay(for: Date())
                let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
                let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
                    .sorted { $0.startDate < $1.startDate }
                let upcoming = events.filter { $0.startDate > Date() }
                let f = DateFormatter(); f.timeStyle = .short
                cont.resume(returning: (events.count, upcoming.first.map { "\($0.title ?? "Event") at \(f.string(from: $0.startDate))" }))
            }
        }
    }

    // MARK: - Fetch Unread Emails (AppleScript)

    private func fetchUnreadEmails() async -> Int {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                var error: NSDictionary?
                let script = NSAppleScript(source: """
                    tell application "Mail"
                        set c to 0
                        repeat with a in accounts
                            set c to c + (unread count of inbox of a)
                        end repeat
                        return c
                    end tell
                """)
                let result = script?.executeAndReturnError(&error)
                cont.resume(returning: Int(result?.int32Value ?? 0))
            }
        }
    }

    // MARK: - Build Briefing with Claude (via Kairo backend)

    private func buildBriefing(calendar: (count: Int, next: String?), emails: Int) async -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let greeting = hour < 12 ? "morning" : hour < 17 ? "afternoon" : "evening"
        let music = await MainActor.run { MusicManager.shared }

        let calInfo = calendar.count == 0 ? "No meetings today." : "\(calendar.count) events today. \(calendar.next ?? "")"
        let emailInfo = emails == 0 ? "No unread emails." : "\(emails) unread emails."

        let prompt = "Good \(greeting). \(calInfo) \(emailInfo) Generate a 2-sentence Jarvis-style briefing."

        // Use Kairo backend
        return await withCheckedContinuation { cont in
            KairoSocket.shared.sendTextCommand(prompt) { response in
                cont.resume(returning: response.isEmpty ? "Good \(greeting). Kairo is online. All systems ready." : response)
            }
        }
    }

    // MARK: - Speak

    private func speakWithElevenLabs(_ text: String) {
        let apiKey = ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"] ?? ""
        let voiceID = ProcessInfo.processInfo.environment["ELEVENLABS_VOICE_ID"] ?? "QR57ghQmWinyEbqmRLVI"

        guard !apiKey.isEmpty, let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)") else {
            speakWithSystem(text); return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "text": text, "model_id": "eleven_turbo_v2_5",
            "voice_settings": ["stability": 0.5, "similarity_boost": 0.8, "style": 0.2, "use_speaker_boost": true]
        ])

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let data, !data.isEmpty else { self?.speakWithSystem(text); return }
            DispatchQueue.main.async {
                self?.audioPlayer = try? AVAudioPlayer(data: data)
                self?.audioPlayer?.play()
                let dur = self?.audioPlayer?.duration ?? 8
                DispatchQueue.main.asyncAfter(deadline: .now() + dur + 1) { self?.dismiss() }
            }
        }.resume()
    }

    private func speakWithSystem(_ text: String) {
        let synth = NSSpeechSynthesizer()
        synth.startSpeaking(text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { self.dismiss() }
    }

    // MARK: - Animate Words

    private func animateWords(_ text: String) {
        let words = text.components(separatedBy: " ").filter { !$0.isEmpty }
        briefingWords = []
        for (i, word) in words.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.07) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { self.briefingWords.append(word) }
            }
        }
    }

    // MARK: - Dismiss

    func dismiss() {
        withAnimation(.spring(response: 0.65, dampingFraction: 0.78)) { isBriefingActive = false; briefingWords = [] }
        NotificationCenter.default.post(name: .kairoVoiceDismissed, object: nil)
    }
}
