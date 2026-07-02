//
//  MusicControllerSelectionView.swift
//  boringNotch
//
//  Created by Alexander on 2025-06-23.
//

import SwiftUI
import Defaults


struct MusicControllerSelectionView: View {
    let onContinue: () -> Void

    @Default(.mediaController) var mediaController
    @Default(.fallbackToNowPlayingWhenInactive) var fallbackToNowPlaying

    private var availableMediaControllers: [MediaControllerType] {
        if MusicManager.shared.isNowPlayingDeprecated {
            return MediaControllerType.allCases.filter { $0 != .nowPlaying }
        } else {
            return MediaControllerType.allCases
        }
    }
    
    @State private var selectedMediaController: MediaControllerType = Defaults[.mediaController]
    
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
                    ForEach(availableMediaControllers) { controller in
                        ControllerOptionView(
                            controller: controller,
                            isSelected: self.selectedMediaController == controller
                        )
                        .onTapGesture {
                            self.selectedMediaController = controller
                        }
                    }
                }
                .padding()
            }
            // Always allow scrolling so the source list is never clipped. The old
            // `count <= 4` heuristic truncated content in the fixed 400x600 window once the
            // fallback toggle and the taller cards (e.g. YouTube Music) were added.
            .scrollDisabled(false)

            Toggle(
                "Use Now Playing when the selected app isn't playing",
                isOn: $fallbackToNowPlaying
            )
            .disabled(selectedMediaController == .nowPlaying || MusicManager.shared.isNowPlayingDeprecated)
            .padding(.horizontal)
            .toggleStyle(.switch)

            Button("Continue", action: {
                self.mediaController = self.selectedMediaController
                self.applySelectionToPriorityList()
                NotificationCenter.default.post(
                    name: Notification.Name.mediaControllerChanged,
                    object: nil
                )
                onContinue()
            })
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
        .onAppear {
            // Under a Now-Playing-deprecated OS the stored default may be `.nowPlaying`, which isn't
            // selectable — preselect the first available source so Continue never persists a dead pick
            // (which would also re-trigger this step every launch).
            if !availableMediaControllers.contains(selectedMediaController) {
                selectedMediaController = availableMediaControllers.first ?? selectedMediaController
            }
        }
    }

    /// Translate the onboarding single-select (+ fallback toggle) into the ordered priority list.
    /// On a fresh install this authors the list; when re-shown to an existing (already-migrated) user
    /// it MERGES the pick into their list rather than clobbering their configured sources/order.
    private func applySelectionToPriorityList() {
        let selected = selectedMediaController
        let includeNowPlaying = fallbackToNowPlaying
            && selected != .nowPlaying
            && !MusicManager.shared.isNowPlayingDeprecated

        if Defaults[.didMigrateMediaSourcePriority] {
            // Existing user re-onboarding: enable the picked source(s), preserve everything else.
            var list = Defaults[.mediaSourcePriority]
            func enable(_ type: MediaControllerType) {
                if let i = list.firstIndex(where: { $0.type == type }) { list[i].isEnabled = true }
            }
            enable(selected)
            if includeNowPlaying { enable(.nowPlaying) }
            Defaults[.mediaSourcePriority] = list
        } else {
            // Fresh install: author the list from the onboarding choice, and mark migration done.
            var enabled: Set<MediaControllerType> = [selected]
            if includeNowPlaying { enabled.insert(.nowPlaying) }
            Defaults[.mediaSourcePriority] = MediaSourceEntry.canonicalOrder.map {
                MediaSourceEntry(type: $0, isEnabled: enabled.contains($0))
            }
            Defaults[.didMigrateMediaSourcePriority] = true
        }
    }
}

struct ControllerOptionView: View {
    let controller: MediaControllerType
    let isSelected: Bool

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

                Text(controller.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if controller == .youtubeMusic, let url = URL(string: "https://github.com/pear-devs/pear-desktop") {
                    Link("View on GitHub: pear-devs/pear-desktop", destination: url)
                        .font(.subheadline)
                        .padding(.top, 2)
                }
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
    }
}


extension MediaControllerType {
    var description: String {
        switch self {
        case .nowPlaying:
            return "Works with most media apps, including browsers, to detect what's playing. Note: This may be removed in a future macOS version."
        case .spotify:
            return "Connects directly to the Spotify app."
        case .appleMusic:
            return "Connects directly to the Apple Music app."
        case .youtubeMusic:
            return "Requires a third-party client with API plugin enabled."
        }
    }
}

#Preview {
    MusicControllerSelectionView(onContinue: {})
        .frame(width: 400, height: 600)
}
