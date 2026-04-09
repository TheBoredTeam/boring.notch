import Foundation
import Combine
import SwiftUI

class QuickNotesManager: ObservableObject {
    static let shared = QuickNotesManager()
    
    @AppStorage("QuickNotesText") var text: String = "" {
        didSet {
            objectWillChange.send()
        }
    }
    
    private init() {}
}
