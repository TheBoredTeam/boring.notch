import Foundation

struct Note: Identifiable, Codable, Equatable {
    let id: UUID
    var content: String
    let createdAt: Date
    var updatedAt: Date
    var isPinned: Bool
    var isMonospaced: Bool

    var title: String {
        content
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty ?? "Untitled"
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
