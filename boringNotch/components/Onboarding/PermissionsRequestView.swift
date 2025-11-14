//
//  PermissionsRequestView.swift
//  boringNotch
//
//  Created by Alexander on 2025-06-23.
//

import SwiftUI

struct PermissionRequestView: View {
    let icon: Image
    let title: String
    let description: String
    let privacyNote: String?
    let onAllow: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            icon
                .resizable()
                .scaledToFit()
                .frame(width: 70, height: 56)
                .foregroundColor(.effectiveAccent)
                .padding(.top, 32)

            Text(title)
                .font(.title)
                .fontWeight(.semibold)

            Text(description)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let privacyNote = privacyNote {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                        .foregroundColor(.secondary)
                    Text(privacyNote)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .padding(.bottom, 8)
                .padding(.horizontal)
            }

            HStack {
                Button("Not Now") { onSkip() }
                    .buttonStyle(.bordered)
                Button("Allow Access") { onAllow() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
    }
}
