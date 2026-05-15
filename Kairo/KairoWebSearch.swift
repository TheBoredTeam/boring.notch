//
//  KairoWebSearch.swift
//  Kairo — Web search with spoken results
//
//  DuckDuckGo Instant Answer API + Claude summarization.
//  Searches, reads results, speaks them naturally.
//

import AppKit
import Foundation

// ═══════════════════════════════════════════
// MARK: - Search Result Model
// ═══════════════════════════════════════════

struct KairoSearchResult {
    let title: String
    let snippet: String
    let url: String
}

// ═══════════════════════════════════════════
// MARK: - Web Search
// ═══════════════════════════════════════════

struct KairoWebSearch {

    // MARK: - Main Search Flow

    static func handleWebSearch(_ query: String) async {

        // FEEDBACK 1 — tell user what we're doing
        KairoFeedback.say(
            "Searching for \(query)...",
            pillText: "🔍 Searching the web..."
        )

        // Wait a beat so they hear it
        try? await Task.sleep(nanoseconds: 800_000_000)

        // Run the search
        let results = await searchWeb(query)

        if results.isEmpty {
            KairoFeedback.say(
                "I couldn't find results for \(query). Try rephrasing your question."
            )
            return
        }

        // FEEDBACK 2 — summarize with Claude
        let summary = await summarizeResults(query: query, results: results)

        // FEEDBACK 3 — speak the summary
        KairoFeedback.say(
            summary,
            pillText: "💬 \(String(summary.prefix(60)))..."
        )

        // Also open browser with results
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let url = URL(string: "https://www.google.com/search?q=\(encoded)") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - DuckDuckGo Instant Answer API (Free)

    static func searchWeb(_ query: String) async -> [KairoSearchResult] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query

        guard let url = URL(string: "https://api.duckduckgo.com/?q=\(encoded)&format=json&no_redirect=1&no_html=1") else {
            return []
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                var results: [KairoSearchResult] = []

                // Abstract — main answer
                if let abstract = json["Abstract"] as? String, !abstract.isEmpty {
                    results.append(KairoSearchResult(
                        title: json["Heading"] as? String ?? query,
                        snippet: abstract,
                        url: json["AbstractURL"] as? String ?? ""
                    ))
                }

                // Related topics
                if let topics = json["RelatedTopics"] as? [[String: Any]] {
                    for topic in topics.prefix(4) {
                        if let text = topic["Text"] as? String,
                           let topicURL = topic["FirstURL"] as? String
                        {
                            results.append(KairoSearchResult(
                                title: text.components(separatedBy: " - ").first ?? text,
                                snippet: text,
                                url: topicURL
                            ))
                        }
                    }
                }

                return results
            }
        } catch {}

        return []
    }

    // MARK: - Summarize with Claude

    static func summarizeResults(query: String, results: [KairoSearchResult]) async -> String {
        let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""

        guard !apiKey.isEmpty else {
            return results.first?.snippet ?? "I found some results for \(query)"
        }

        let context = results.prefix(4)
            .map { "• \($0.title): \($0.snippet)" }
            .joined(separator: "\n")

        let prompt = """
            User asked: "\(query)"

            Search results:
            \(context)

            Give a natural spoken response in 2-3 sentences.
            Be specific with actual information found.
            Sound like you personally found this.
            Start with what you found, not "I found".
            Speak as Kairo — direct, intelligent, warm.
            If asking about restaurants/places — name actual specific ones with brief detail.
            Keep under 60 words.
            """

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            return results.first?.snippet ?? ""
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 120,
            "system":
                "You are Kairo, an AI assistant. Give spoken responses — short, natural, intelligent. Never robotic. Like Jarvis. Always answer in first person naturally.",
            "messages": [["role": "user", "content": prompt]],
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let content = json["content"] as? [[String: Any]],
               let text = content.first?["text"] as? String
            {
                return text
            }
        } catch {}

        return results.first?.snippet ?? "Here's what I found for \(query)"
    }

    // MARK: - Ask Claude Directly (General Questions)

    static func askClaude(_ text: String) async -> String {
        let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""

        guard !apiKey.isEmpty,
              let url = URL(string: "https://api.anthropic.com/v1/messages")
        else { return "I'm not sure about that." }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 150,
            "system": """
                You are Kairo, a personal AI assistant.
                You live in a Mac as a smart assistant.
                Answer in 1-3 natural spoken sentences.
                Be direct and helpful like Jarvis.
                Sound intelligent but warm.
                Never say "I cannot" — always try to help.
                If you don't know something say so briefly and suggest what to do.
                """,
            "messages": [["role": "user", "content": text]],
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let content = json["content"] as? [[String: Any]],
               let responseText = content.first?["text"] as? String
            {
                return responseText
            }
        } catch {}

        return "I had trouble with that one."
    }
}
