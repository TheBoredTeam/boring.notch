import SwiftUI
import Defaults

class QuickLaunchManager: ObservableObject {
    @Published var quickLaunchApps: [QuickLaunchApp] = []
    
    struct QuickLaunchApp: Identifiable, Codable {
        let id: String
        let name: String
        let bundleIdentifier: String
        let icon: Data?
        
        var nsImage: NSImage? {
            guard let icon = icon else { return nil }
            return NSImage(data: icon)
        }
    }
    
    init() {
        loadQuickLaunchApps()
    }
    
    func addApp(_ app: NSRunningApplication) {
        guard let bundleIdentifier = app.bundleIdentifier,
              let localizedName = app.localizedName else { return }
        
        let icon = app.icon?.tiffRepresentation
        
        let quickLaunchApp = QuickLaunchApp(
            id: bundleIdentifier,
            name: localizedName,
            bundleIdentifier: bundleIdentifier,
            icon: icon
        )
        
        if !quickLaunchApps.contains(where: { $0.id == bundleIdentifier }) {
            quickLaunchApps.append(quickLaunchApp)
            saveQuickLaunchApps()
        }
    }
    
    func removeApp(_ app: QuickLaunchApp) {
        quickLaunchApps.removeAll { $0.id == app.id }
        saveQuickLaunchApps()
    }
    
    func launchApp(_ app: QuickLaunchApp) {
        NSWorkspace.shared.launchApplication(
            withBundleIdentifier: app.bundleIdentifier,
            options: [],
            additionalEventParamDescriptor: nil,
            launchIdentifier: nil
        )
    }
    
    private func loadQuickLaunchApps() {
        if let data = UserDefaults.standard.data(forKey: "quickLaunchApps"),
           let apps = try? JSONDecoder().decode([QuickLaunchApp].self, from: data) {
            quickLaunchApps = apps
        }
    }
    
    private func saveQuickLaunchApps() {
        if let data = try? JSONEncoder().encode(quickLaunchApps) {
            UserDefaults.standard.set(data, forKey: "quickLaunchApps")
        }
    }
} 