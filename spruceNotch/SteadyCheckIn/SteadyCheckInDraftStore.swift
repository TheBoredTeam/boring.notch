//
//  SteadyCheckInDraftStore.swift
//  spruceNotch
//

import Foundation

final class SteadyCheckInDraftStore {
    static let shared = SteadyCheckInDraftStore()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let fileURL: URL

    private init() {
        let fm = FileManager.default
        let support = try? fm.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = (support ?? fm.temporaryDirectory)
            .appendingPathComponent("spruceNotch", isDirectory: true)
            .appendingPathComponent("SteadyCheckIn", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("draft.json")
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> SteadyCheckInDraft? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(SteadyCheckInDraft.self, from: data)
    }

    func save(_ draft: SteadyCheckInDraft) {
        var copy = draft
        copy.updatedAt = Date()
        guard let data = try? encoder.encode(copy) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
