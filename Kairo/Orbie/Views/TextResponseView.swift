import SwiftUI

struct TextResponseData: Hashable {
    let query: String
    let response: String
    let icon: String?
}

/// Panel-sized text answer. Optional query echoed at the top with a
/// waveform glyph (representing what Kairo heard). Response reveals
/// character-by-character for a deliberate, conversational pacing.
struct TextResponseView: View {
    let data: TextResponseData
    @State private var revealedChars: Int = 0
    @State private var revealTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: Kairo.Space.lg) {
            if !data.query.isEmpty {
                queryRow
            }

            Text(String(data.response.prefix(revealedChars)))
                .font(.system(size: 22, weight: .regular, design: .rounded))
                .foregroundStyle(Kairo.Palette.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.none, value: revealedChars)

            Spacer(minLength: 0)
        }
        .padding(Kairo.Space.xxl - Kairo.Space.xs)  // 28pt feels right here
        .onAppear { startReveal() }
        .onDisappear { revealTimer?.invalidate() }
    }

    private var queryRow: some View {
        HStack(spacing: Kairo.Space.sm) {
            Image(systemName: "waveform")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Kairo.Palette.textDim)
            Text(data.query)
                .font(Kairo.Typography.bodyEmphasis)
                .foregroundStyle(Kairo.Palette.textDim)
                .lineLimit(1)
        }
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
