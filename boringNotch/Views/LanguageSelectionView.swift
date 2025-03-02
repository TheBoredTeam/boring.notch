import SwiftUI

struct LanguageSelectionView: View {
    @StateObject private var languageManager = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Form {
            Section {
                ForEach(Array(languageManager.availableLanguages.keys.sorted()), id: \.self) { code in
                    HStack {
                        Text(LocalizedStringKey(languageManager.availableLanguages[code] ?? code))
                        Spacer()
                        if languageManager.selectedLanguage == code {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        languageManager.setLanguage(code)
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(Text("Language"))
    }
} 