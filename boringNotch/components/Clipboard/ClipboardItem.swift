import Foundation
import AppKit

struct ClipboardItem: Identifiable, Equatable {
    let id: UUID
    let dateAdded: Date
    let content: ContentType
    
    enum ContentType: Equatable {
        case text(String)
        case image(NSImage)
    }
    
    init(id: UUID = UUID(), dateAdded: Date = Date(), content: ContentType) {
        self.id = id
        self.dateAdded = dateAdded
        self.content = content
    }
    
    // Equality check for SwiftUI updates
    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        switch (lhs.content, rhs.content) {
        case (.text(let lText), .text(let rText)):
            return lText == rText && lhs.id == rhs.id
        case (.image(let lImg), .image(let rImg)):
            // Compare TIFF data for equality
            return lImg.tiffRepresentation == rImg.tiffRepresentation && lhs.id == rhs.id
        default:
            return false
        }
    }
}
