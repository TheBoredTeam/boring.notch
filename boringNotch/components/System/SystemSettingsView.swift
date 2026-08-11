import SwiftUI

struct SystemSettingsView: View {
    var body: some View {
        Form {
            Section {
                Text("Memory data is read from the macOS kernel — no configuration needed.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Memory")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("System")
    }
}
