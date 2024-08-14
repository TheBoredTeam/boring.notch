    //
    //  MusicVisualizer.swift
    //  boringNotch
    //
    //  Created by Harsh Vardhan  Goswami  on 02/08/24.
    //

import SwiftUI

struct MusicVisualizer: View {
    @State private var amplitudes: [CGFloat] = Array(repeating: 0, count: 5)
    @EnvironmentObject var vm: BoringViewModel
    let avgColor: NSColor?
    let isPlaying: Bool
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<4) { index in
                Capsule()
                    .fill(vm.coloredSpectrogram ? Color(nsColor: avgColor ?? .white) : .white)
                    .frame(width: 2, height: isPlaying ? amplitudes[index] : 2)
            }
        }
        .transition(.scale.animation(.spring(.bouncy(duration: 0.6))))
        .onReceive(timer) { _ in
            withAnimation(.spring(.bouncy(duration: 0.6))) {
                for i in 0..<4 {
                    amplitudes[i] = CGFloat.random(in: 4...12)
                }
            }
        }.onDisappear(perform: {
            amplitudes = Array(repeating: 0, count: 4)
            self.timer.upstream.connect().cancel()
        })
    }
}
