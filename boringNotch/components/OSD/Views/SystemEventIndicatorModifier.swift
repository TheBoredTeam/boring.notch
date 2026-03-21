    //
    //  SystemEventIndicatorModifier.swift
    //  boringNotch
    //
    //  Created by Richard Kunkli on 12/08/2024.
    //

import SwiftUI
import Defaults

struct SystemEventIndicatorModifier: View {
    @EnvironmentObject var vm: BoringViewModel
    @Binding var eventType: SneakContentType
    @Binding var value: CGFloat
    @Binding var icon: String
    @Binding var accent: Color?
    let showSlider: Bool = false
    var sendEventBack: (CGFloat) -> Void

    var body: some View {
        HStack(spacing: 14) {
            OSDIconView(eventType: eventType, icon: icon, value: value, accent: accent)
            if (eventType != .mic) {
                DraggableProgressBar(value: $value, accentColor: accent)
                if Defaults[.showClosedNotchOSDPercentage] {
                    Text("\(Int(value * 100))%")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .frame(width: 35, alignment: .trailing)
                }
            } else {
                Text("Mic \(value > 0 ? "unmuted" : "muted")")
                    .foregroundStyle(.gray)
                    .lineLimit(1)
                    .allowsTightening(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .imageScale(.large)
    }
}

