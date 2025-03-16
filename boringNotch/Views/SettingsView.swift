Section {
    NavigationLink(destination: LanguageSelectionView()) {
        HStack {
            Text("Language")
            Spacer()
            Text(LocalizedStringKey(LanguageManager.shared.availableLanguages[LanguageManager.shared.selectedLanguage] ?? ""))
                .foregroundColor(.secondary)
        }
    }
    // ... other settings ...
} 