import Foundation

struct Note: Identifiable, Codable, Equatable {
    let id: UUID
    var content: String
    let createdAt: Date
    var updatedAt: Date
    var isPinned: Bool
    var isMonospaced: Bool

    var headingTitle: String {
        content
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty ?? "Untitled Note"
    }

    var previewText: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let lines = trimmed.components(separatedBy: .newlines)
        guard lines.count > 1 else { return "" }
        let remainder = lines.dropFirst().joined(separator: " ")
        let condensed = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(condensed.prefix(200))
    }

    init(
        id: UUID = UUID(),
        content: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isPinned: Bool = false,
        isMonospaced: Bool = false
    ) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.isMonospaced = isMonospaced
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
