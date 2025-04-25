import SwiftUI
import Defaults

struct QuickLaunchView: View {
    @StateObject private var quickLaunchManager = QuickLaunchManager()
    @State private var isAddingApp = false
    @State private var selectedApp: NSRunningApplication?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Quick Launch")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: { isAddingApp = true }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            if quickLaunchManager.quickLaunchApps.isEmpty {
                Text("Add your favorite apps for quick access")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(quickLaunchManager.quickLaunchApps) { app in
                            QuickLaunchAppButton(app: app, quickLaunchManager: quickLaunchManager)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.3))
        )
        .sheet(isPresented: $isAddingApp) {
            AddQuickLaunchAppView(quickLaunchManager: quickLaunchManager)
        }
    }
}

struct QuickLaunchAppButton: View {
    let app: QuickLaunchManager.QuickLaunchApp
    @ObservedObject var quickLaunchManager: QuickLaunchManager
    
    var body: some View {
        Button(action: { quickLaunchManager.launchApp(app) }) {
            VStack(spacing: 4) {
                if let image = app.nsImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Text(app.name)
                    .font(.caption)
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .frame(width: 60)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button("Remove") {
                quickLaunchManager.removeApp(app)
            }
        }
    }
}

struct AddQuickLaunchAppView: View {
    @ObservedObject var quickLaunchManager: QuickLaunchManager
    @State private var apps: [NSRunningApplication] = []
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack {
            List(apps, id: \.bundleIdentifier) { app in
                if let name = app.localizedName {
                    HStack {
                        if let icon = app.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 24, height: 24)
                        }
                        
                        Text(name)
                        
                        Spacer()
                        
                        Button("Add") {
                            quickLaunchManager.addApp(app)
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .frame(width: 400, height: 300)
        .onAppear {
            apps = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        }
    }
} 