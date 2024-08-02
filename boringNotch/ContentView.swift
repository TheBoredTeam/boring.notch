import SwiftUI
import AVFoundation
import Combine

// MARK: - Data Models

struct Song: Identifiable {
    let id = UUID()
    let title: String
    let artist: String
    let albumArt: String
}

struct ContentView: View {
    let onHover: () -> Void
    var body: some View {
        BoringNotch(onHover: onHover)
            .frame(maxWidth: .infinity, maxHeight: 200)
            .background(Color.clear)
            .edgesIgnoringSafeArea(.top)
    }
}
