import SwiftUI

struct TextResponseData: Hashable {
    let query: String
    let response: String
    let icon: String?
}

struct TextResponseView: View {
    let data: TextResponseData
    @State private var revealedChars: Int = 0
    @State private var revealTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !data.query.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "waveform")
                        .foregroundColor(Kairo.Palette.textDim)
                    Text(data.query)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Kairo.Palette.textDim)
                        .lineLimit(1)
                }
            }

            Text(String(data.response.prefix(revealedChars)))
                .font(.system(size: 20, weight: .regular, design: .rounded))
                .foregroundColor(Kairo.Palette.text)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.none, value: revealedChars)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
        .padding(28)
        .onAppear { startReveal() }
        .onDisappear { revealTimer?.invalidate() }
    }

    private func startReveal() {
        revealedChars = 0
        let interval: TimeInterval = 0.025
        revealTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { timer in
            if revealedChars < data.response.count {
                revealedChars += 1
            } else {
                timer.invalidate()
            }
        }
    }
}
