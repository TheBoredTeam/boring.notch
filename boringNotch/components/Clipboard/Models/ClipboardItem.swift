import Foundation
import AppKit

struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    var kind: ClipboardItemKind
    var sourceApp: String
    var sourceAppName: String
    var timestamp: Date
    var isPinned: Bool
    
    var displayText: String {
        switch kind {
        case .text(let content):
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    
    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        return lhs.id == rhs.id
    }
}
