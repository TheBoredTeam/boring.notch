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
            //Disable scroll if there are 4 or fewer to avoid unnecessary scroll behavior
            .scrollDisabled(availableMediaControllers.count <= 4)

//            Spacer()

            Button("Continue", action: {
                self.mediaController = self.selectedMediaController
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
                Text(controller.rawValue)
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
