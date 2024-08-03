import SwiftUI
import AVFoundation
import Combine

struct ContentView: View {
    let onHover: () -> Void
    var body: some View {
        BoringNotch(onHover: onHover)
            .frame(maxWidth: .infinity, maxHeight: 250)
            .background(Color.clear)
            .edgesIgnoringSafeArea(.top)
    }
}
