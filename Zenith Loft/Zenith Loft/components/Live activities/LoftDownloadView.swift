//
//  LoftDownloadView.swift
//  Zenith Loft (LoftOS)
//  Created by You on 11/05/25
//
//  Clean-room download HUD surface:
//  - LoftBrowser enum (safari/chrome/other)
//  - LoftDownloadFile model
//  - LoftDownloadWatcher (ObservableObject) you can update from a monitor
//  - LoftDownloadArea view (compact row showing the top/most-recent download)
//
//  Notes:
//  - No external assets required (uses app icons via bundle IDs when possible).
//  - Safe unwraps (handles empty lists).
//

import SwiftUI
import AppKit

// MARK: - Models

enum LoftBrowser: Equatable {
    case safari
    case chrome
    case other(bundleIdentifier: String?)

    /// Known bundle identifier (when applicable)
    var bundleIdentifier: String? {
        switch self {
        case .safari: return "com.apple.Safari"
        case .chrome: return "com.google.Chrome"
        case .other(let id): return id
        }
    }

    var displayNameFallback: String {
        switch self {
        case .safari: return "Safari"
        case .chrome: return "Google Chrome"
        case .other: return "Browser"
        }
    }
}

struct LoftDownloadFile: Identifiable, Equatable {
    let id = UUID()
    var name: String
    /// Size in bytes
    var sizeBytes: Int
    /// Formatted size (e.g., "24.1 MB")
    var formattedSize: String
    var browser: LoftBrowser
}

// MARK: - Source of truth

final class LoftDownloadWatcher: ObservableObject {
    @Published var downloads: [LoftDownloadFile] = []

    /// Convenience: most recent (or first) download to display
    var current: LoftDownloadFile? { downloads.first }
}

// MARK: - App Icon helper

struct LoftAppIcon: View {
    var bundleIdentifier: String?
    var fallbackSystemName: String = "arrow.down.circle"

    var body: some View {
        if let id = bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 26, height: 26)
                .cornerRadius(5)
        } else {
            Image(systemName: fallbackSystemName)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundColor(.white)
        }
    }
}

// MARK: - Compact HUD row

struct LoftDownloadArea: View {
    @EnvironmentObject var watcher: LoftDownloadWatcher

    var body: some View {
        if let file = watcher.current {
            HStack(alignment: .center, spacing: 12) {
                // App icon (Safari/Chrome/other)
                LoftAppIcon(bundleIdentifier: file.browser.bundleIdentifier)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Download")
                        .font(.callout).fontWeight(.semibold)
                        .foregroundColor(.white)
                    Text("In progress")
                        .font(.footnote)
                        .foregroundStyle(.gray)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(file.formattedSize)
                        .font(.callout).foregroundColor(.white)
                    Text(file.name)
                        .font(.caption2)
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 34)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        } else {
            // Optional placeholder when there are no downloads
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle")
                    .frame(width: 18, height: 18)
                Text("No active downloads")
                    .font(.footnote)
                    .foregroundStyle(.gray)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Preview

#Preview {
    let watcher = LoftDownloadWatcher()
    watcher.downloads = [
        LoftDownloadFile(
            name: "Sample_File_2025-11-05.dmg",
            sizeBytes: 24_500_000,
            formattedSize: "24.5 MB",
            browser: .safari
        )
    ]
    return VStack(spacing: 12) {
        LoftDownloadArea().environmentObject(watcher)
        // Empty state
        LoftDownloadArea().environmentObject(LoftDownloadWatcher())
    }
    .padding()
    .frame(width: 360)
    .background(Color.black)
}
