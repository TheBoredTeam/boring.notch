import SwiftUI

struct AudioSpectrumView: View {
    @Binding var isPlaying: Bool
    @State private var phases: [Double] = Array(repeating: 0, count: 8)

    private let barCount = 8

    var body: some View {
        GeometryReader { geo in
            let barWidth = max(1, geo.size.width / CGFloat(barCount * 2))
            HStack(alignment: .bottom, spacing: barWidth) {
                ForEach(0..<barCount, id: \.self) { idx in
                    Capsule()
                        .fill(.white)
                        .frame(width: barWidth, height: barHeight(for: idx, in: geo.size))
                        .animation(.easeInOut(duration: 0.25), value: phases[idx])
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .onAppear { start() }
            .onChange(of: isPlaying) { _, newValue in
                if newValue { start() } else { stop() }
            }
        }
        .accessibilityHidden(true)
    }

    private func barHeight(for index: Int, in size: CGSize) -> CGFloat {
        let base = size.height * 0.2
        let variable = size.height * 0.8 * CGFloat(abs(sin(phases[index])))
        return max(1, min(size.height, base + variable))
    }

    private func start() {
        guard isPlaying else { return }
        // Kick off a simple timer-driven animation by randomizing phases periodically
        withAnimation(.easeInOut(duration: 0.25)) {
            for i in phases.indices { phases[i] = Double.random(in: 0...(.pi * 2)) }
        }
        scheduleTick()
    }

    private func stop() {
        withAnimation(.easeOut(duration: 0.3)) {
            for i in phases.indices { phases[i] = 0 }
        }
    }

    private func scheduleTick() {
        guard isPlaying else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard isPlaying else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                for i in phases.indices { phases[i] += Double.random(in: 0.5...1.5) }
            }
            scheduleTick()
        }
    }
}

#Preview {
    StatefulPreviewWrapper(true) { isPlaying in
        AudioSpectrumView(isPlaying: isPlaying)
            .frame(width: 100, height: 30)
            .background(Color.black)
            .preferredColorScheme(.dark)
    }
}

// Helper for binding previews
struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State var value: Value
    var content: (Binding<Value>) -> Content
    init(_ value: Value, content: @escaping (Binding<Value>) -> Content) {
        _value = State(initialValue: value)
        self.content = content
    }
    var body: some View { content($value) }
}
