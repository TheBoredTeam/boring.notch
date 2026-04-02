
import Foundation

enum ClipboardItemKind: Codable, Equatable {
    case text(String)
    
    var displayType: String {
        return "Text"
    }
}
