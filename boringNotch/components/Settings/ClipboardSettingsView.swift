import SwiftUI
import Defaults

struct ClipboardSettingsView: View {
    @Default(.clipboardMaxItems) private var clipboardMaxItems: Int
    @Default(.clipboardSortNewestFirst) private var clipboardSortNewestFirst: Bool
    @Default(.clipboardGroupByApp) private var clipboardGroupByApp: Bool
    @Default(.clipboardPersistOnQuit) private var clipboardPersistOnQuit: Bool
    
    @ObservedObject private var viewModel = ClipboardStateViewModel.shared
    
    var body: some View {
        Form {
            Section {
                Slider(value: Binding(
                    get: { Double(clipboardMaxItems) },
                    set: { clipboardMaxItems = Int($0) }
                ), in: 10...50, step: 5) {
                    HStack {
                        Text("Numero massimo elementi")
                        Spacer()
                        Text("\(clipboardMaxItems)")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Generale")
            }
            
            Section {
                Picker("Ordine", selection: $clipboardSortNewestFirst) {
                    Text("Più recenti prima").tag(true)
                    Text("Più recenti per ultimo").tag(false)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Ordinamento")
            }
            
            Section {
                Defaults.Toggle(key: .clipboardGroupByApp) {
                    Text("Raggruppa per applicazione")
                }
            } header: {
                Text("Visualizzazione")
            }
            
            Section {
                Defaults.Toggle(key: .clipboardPersistOnQuit) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mantieni elementi alla chiusura")
                        Text("Gli elementi verranno salvati e ripristinati al riavvio")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Persistenza")
            }
            
            Section {
                HStack {
                    Text("Elementi salvati")
                    Spacer()
                    Text("\(viewModel.items.count)")
                        .foregroundStyle(.secondary)
                }
                
                Button(role: .destructive) {
                    viewModel.clearAll()
                } label: {
                    Text("Cancella tutti gli elementi")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } header: {
                Text("Gestione dati")
            } footer: {
                if clipboardPersistOnQuit {
                    Text("Gli elementi della clipboard vengono salvati su disco e ripristinati al riavvio dell'app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Gli elementi della clipboard non vengono salvati su disco e verranno cancellati alla chiusura dell'app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Clipboard")
    }
}
