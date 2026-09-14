//
//  NotchPrivacyView.swift
//  boringNotch
//

import SwiftUI

/// The Privacy section of the opened notch: what is using the microphone and camera right
/// now, and who is responsible where macOS lets us find out.
struct NotchPrivacyView: View {
    @ObservedObject private var manager = PrivacyActivityManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Privacy")
                .font(.headline)
                .foregroundStyle(.white)

            if manager.usage.isAnythingActive {
                VStack(alignment: .leading, spacing: 10) {
                    if manager.usage.microphoneActive {
                        PrivacyRow(
                            symbol: "mic.fill",
                            title: Text("Microphone"),
                            apps: manager.usage.microphoneApps
                        )
                    }
                    if manager.usage.cameraActive {
                        PrivacyRow(
                            symbol: "video.fill",
                            title: Text("Camera"),
                            // macOS exposes no per-client API for the camera, so there is
                            // never a name to show here.
                            apps: []
                        )
                    }
                }
            } else {
                Text("Microphone and camera are not in use")
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 8)
    }
}

private struct PrivacyRow: View {
    let symbol: String
    let title: Text
    let apps: [PrivacyApp]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.green)
                .imageScale(.medium)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(.subheadline)
                    .foregroundStyle(.white)

                if apps.isEmpty {
                    // Said plainly rather than guessed at.
                    Text("In use — app unknown")
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                } else {
                    // Runtime data, so verbatim: not localization keys.
                    Text(verbatim: apps.map(\.name).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 4)

            Text("Active")
                .font(.caption2)
                .foregroundStyle(.green)
        }
    }
}

#Preview {
    NotchPrivacyView()
        .frame(width: 300, height: 160)
        .background(Color.black)
}
