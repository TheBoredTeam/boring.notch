//
//  MusicControllerSelectionView.swift
//  boringNotch
//
//  Created by Alexander on 2025-06-23.
//

import SwiftUI

@MainActor
struct MusicControllerSelectionView: View {
    let onContinue: () -> Void

    @ObservedObject private var musicManager = MusicManager.shared
    @State private var selectedMediaController = MusicManager.shared.preferredMediaController
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Choose a Music Source")
                .font(.title)
                .fontWeight(.bold)
                .padding(.top, 24)

            Text("Select the music source you want to use. You can change this later in the app settings.")
                .multilineTextAlignment(.center)
                .font(.body)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(MediaControllerType.allCases) { controller in
                        let isEnabled = controller != .nowPlaying
                            || (
                                !musicManager.isCheckingNowPlayingAvailability
                                    && musicManager.nowPlayingAvailability.isSelectable
                            )

                        Button {
                            selectedMediaController = controller
                        } label: {
                            ControllerOptionView(
                                controller: controller,
                                isSelected: selectedMediaController == controller,
                                isEnabled: isEnabled
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!isEnabled)

                        if controller == .youtubeMusic,
                           let url = URL(string: "https://github.com/pear-devs/pear-desktop") {
                            Link("View on GitHub: pear-devs/pear-desktop", destination: url)
                                .font(.subheadline)
                        }
                    }
                }
                .padding()
            }
            // Disable scroll if there are 4 or fewer to avoid unnecessary scroll behavior
            .scrollDisabled(MediaControllerType.allCases.count <= 4)

            nowPlayingAvailabilityStatus

            Button("Continue", action: {
                guard canContinue else { return }
                musicManager.selectMediaController(selectedMediaController)
                onContinue()
            })
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canContinue)
                .padding(.bottom, 24)
        }
        .task {
            musicManager.ensureNowPlayingAvailabilityChecked()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
    }

    private var canContinue: Bool {
        selectedMediaController != .nowPlaying
            || (
                !musicManager.isCheckingNowPlayingAvailability
                    && musicManager.nowPlayingAvailability.isSelectable
            )
    }

    @ViewBuilder
    private var nowPlayingAvailabilityStatus: some View {
        if musicManager.isCheckingNowPlayingAvailability {
            Text("Checking Now Playing availability...")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let message = musicManager.nowPlayingAvailability.settingsMessage {
            VStack(spacing: 8) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if musicManager.nowPlayingAvailability.showsCheckAgainButton {
                    Button("Check Again") {
                        musicManager.refreshNowPlayingAvailability()
                    }
                    .font(.caption)
                }
            }
            .padding(.horizontal, 24)
        }
    }
}

struct ControllerOptionView: View {
    let controller: MediaControllerType
    let isSelected: Bool
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundColor(isSelected ? .effectiveAccent : .secondary.opacity(0.5))
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)

            VStack(alignment: .leading, spacing: 4) {
                Text(controller.localizedString)
                    .font(.headline)
                    .fontWeight(.semibold)

                Text(controller.descriptionResource)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.effectiveAccent.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.effectiveAccent : Color.secondary.opacity(0.3), lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .opacity(isEnabled ? 1 : 0.5)
    }
}


extension MediaControllerType {
    var descriptionResource: LocalizedStringResource {
        switch self {
        case .nowPlaying:
            LocalizedStringResource(
                "Works with most media apps, including browsers, to detect what's playing. Note: This may be removed in a future macOS version.",
                comment: "Onboarding description of the universal macOS Now Playing music source."
            )
        case .spotify:
            LocalizedStringResource(
                "Connects directly to the Spotify app.",
                comment: "Onboarding description of the Spotify music source."
            )
        case .appleMusic:
            LocalizedStringResource(
                "Connects directly to the Apple Music app.",
                comment: "Onboarding description of the Apple Music source."
            )
        case .youtubeMusic:
            LocalizedStringResource(
                "Requires a third-party client with API plugin enabled.",
                comment: "Onboarding description of the YouTube Music source."
            )
        }
    }
}

#Preview {
    MusicControllerSelectionView(onContinue: {})
        .frame(width: 400, height: 600)
}
