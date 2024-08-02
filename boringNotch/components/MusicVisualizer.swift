//
//  MusicVisualizer.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 02/08/24.
//

import SwiftUI

struct MusicVisualizer: View {
    @State private var amplitudes: [CGFloat] = Array(repeating: 0, count: 5)
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5) { index in
                Capsule()
                    .fill(Color.white)
                    .frame(width: 3, height: amplitudes[index])
            }
        }
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.1)) {
                for i in 0..<5 {
                    amplitudes[i] = CGFloat.random(in: 5...20)
                }
            }
        }
    }
}
