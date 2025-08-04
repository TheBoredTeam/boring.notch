//
//  LocalizationManager.swift
//  boringNotch
//
//  Created by Juan Carlos Acosta Perabá on 4/8/25.
//

import Foundation
import Defaults

class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()
    
    @Published var currentLanguage: AppLanguage = Defaults[.appLanguage] {
        didSet {
            Defaults[.appLanguage] = currentLanguage
            applyLanguage()
        }
    }
    
    private init() {
        applyLanguage()
        
        // Observe changes from Defaults
        Defaults.observe(.appLanguage) { [weak self] change in
            DispatchQueue.main.async {
                self?.currentLanguage = change.newValue
            }
        }
    }
    
    private func applyLanguage() {
        let languageCode: String
        
        switch currentLanguage {
        case .english:
            languageCode = "en"
        case .spanish:
            languageCode = "es"
        }
        
        // Set the language for the current bundle
        UserDefaults.standard.set([languageCode], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
        
        // Post notification to update UI
        NotificationCenter.default.post(name: .languageChanged, object: languageCode)
    }
    
    func localizedString(for key: String, comment: String = "") -> String {
        let languageCode: String
        
        switch currentLanguage {
        case .english:
            languageCode = "en"
        case .spanish:
            languageCode = "es"
        }
        
        guard let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return NSLocalizedString(key, comment: comment)
        }
        
        return NSLocalizedString(key, bundle: bundle, comment: comment)
    }
}

// Notification for language changes
extension Notification.Name {
    static let languageChanged = Notification.Name("languageChanged")
}