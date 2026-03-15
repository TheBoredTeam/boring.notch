//
//  BibleVerseManager.swift
//  boringNotch
//
//  Created on feature/bible-verse-of-the-day
//

import Foundation

struct BibleVerse: Codable {
    let reference: String
    let text: String
    let version: String?
}

private struct BibleVerseResponse: Decodable {
    let reference: String
    let text: String
    let version: String?

    enum CodingKeys: String, CodingKey {
        case reference
        case text
        case version = "translation_name"
    }
}

private struct BibleVerseCache: Codable {
    let verse: BibleVerse
    let date: Date
}

@MainActor
final class BibleVerseManager: ObservableObject {
    static let shared = BibleVerseManager()

    @Published private(set) var todaysVerse: BibleVerse?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastFetchDate: Date?

    private let session: URLSession
    private var loadTask: Task<Void, Never>?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        session = URLSession(configuration: config)

        loadCachedVerse()
    }

    func loadTodaysVerseIfNeeded() async {
        guard !hasVerseForToday else {
            return
        }

        if let loadTask {
            await loadTask.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.loadTodaysVerse()
        }

        loadTask = task
        await task.value
    }

    private var hasVerseForToday: Bool {
        guard let lastFetchDate, todaysVerse != nil else { return false }
        return Calendar.current.isDateInToday(lastFetchDate)
    }

    private func loadTodaysVerse() async {
        isLoading = true
        defer {
            isLoading = false
            loadTask = nil
        }

        guard let url = URL(string: "https://bible-api.com/?random=verse") else {
            return
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return
            }

            let payload = try JSONDecoder().decode(BibleVerseResponse.self, from: data)
            let verse = BibleVerse(
                reference: payload.reference,
                text: payload.text.trimmingCharacters(in: .whitespacesAndNewlines),
                version: payload.version
            )

            todaysVerse = verse
            lastFetchDate = Date()
            saveCachedVerse()
        } catch {
            print("Error fetching Bible verse: \(error.localizedDescription)")
        }
    }

    private func saveCachedVerse() {
        guard let verse = todaysVerse else { return }

        let cache = BibleVerseCache(verse: verse, date: lastFetchDate ?? Date())
        let encoder = JSONEncoder()

        if let data = try? encoder.encode(cache),
           let cacheURL = cacheURL {
            try? data.write(to: cacheURL)
        }
    }

    private func loadCachedVerse() {
        guard let cacheURL,
              let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(BibleVerseCache.self, from: data) else {
            return
        }

        if Calendar.current.isDateInToday(cache.date) {
            todaysVerse = cache.verse
            lastFetchDate = cache.date
        }
    }

    private var cacheURL: URL? {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        return cacheDir?.appendingPathComponent("bible_verse_cache.json")
    }
}

