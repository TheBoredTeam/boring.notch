//
//  BrightnessView.swift
//  boringNotch
//
//  Created by JeanLouis on 21/08/2025.
//

import Foundation
import SwiftUI

struct BrightnessView: View {
    @EnvironmentObject var vm: BoringViewModel
    @StateObject private var brightness = BrightnessManager.shared
    
    private let minIndicatorWidth: CGFloat = 4

    var body: some View {
        let b = brightness.animatedBrightness

        HStack(alignment: .center, spacing: 10) {
            Image(systemName: iconName(for: b))
                .font(.system(size: 16, weight: .bold))
                .frame(width: 28, height: 28)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    Capsule()
                        .fill(Color.white)
                        .frame(width: max(minIndicatorWidth, geo.size.width * CGFloat(b)))
                        .animation(.easeOut(duration: 0.18), value: b)
                }
            }
            .frame(height: 10)

            Text(label(for: b))
                .font(.system(.caption, design: .rounded))
                .monospacedDigit()
                .frame(width: 46, alignment: .trailing)
        }
        .padding(6)
        .frame(maxWidth: vm.notchSize.width  , maxHeight: 28)
        .background(Color.black)
        .clipShape(.rect(bottomLeadingRadius: 8, bottomTrailingRadius: 8))
        .opacity((brightness.shouldShowOverlay ) ? 1 : 0)
        .onAppear {
            brightness.refresh()
        }
    }
    
    private func label(for value: Float) -> String {
        "\(Int(value * 100))%"
    }

    private func iconName(for value: Float) -> String {
        switch value {
        case ..<0.01: return "sun.min.fill"
        case ..<0.33: return "sun.min.fill"
        case ..<0.66: return "sun.max.fill"
        default: return "sun.max.fill"
        }
    }
}

#Preview {
    BrightnessView()
        .frame(width: 160, height: 100, alignment: .center)
        .background(.black)
        .environmentObject(BoringViewModel())

}
