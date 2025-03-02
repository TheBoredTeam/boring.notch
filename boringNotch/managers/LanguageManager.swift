import Foundation
import SwiftUI

class LanguageManager: ObservableObject {
    @AppStorage("selectedLanguage") var selectedLanguage: String = "system"
    
    static let shared = LanguageManager()
    
    let availableLanguages = [
        "system": "System Default",
        "en": "English",
        "zh-Hans": "Chinese (Simplified)",
        "ru": "Russian"
    ]
    
    private init() {}
    
    func setLanguage(_ languageCode: String) {
        selectedLanguage = languageCode
        UserDefaults.standard.set([languageCode], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
        
        // 发送通知以更新UI
        NotificationCenter.default.post(name: NSNotification.Name("LanguageChanged"), object: nil)
    }
    
    func getCurrentLanguage() -> String {
        if selectedLanguage == "system" {
            return Bundle.main.preferredLocalizations.first ?? "en"
        }
        return selectedLanguage
    }
    
    func getLanguageDisplayName(_ code: String) -> String {
        return availableLanguages[code] ?? code
    }
} 