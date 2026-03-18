//
//  OpenNotchOSD.swift
//  boringNotch
//
//  Created by Alexander on 2024-11-23.
//

import SwiftUI
import Defaults

struct OpenNotchOSD: View {
    @EnvironmentObject var vm: BoringViewModel
    @Binding var type: SneakContentType
    @Binding var value: CGFloat
    @Binding var icon: String
    @Binding var accent: Color?
    @Default(.showOpenNotchOSDPercentage) var showPercentage
    
    var body: some View {
        HStack(spacing: 8) {
            // Icon
            OSDIconView(eventType: type, icon: icon, value: value, accent: accent)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 20, alignment: .center)
            
            // Slider or Status Text
            if type != .mic {
                 DraggableProgressBar(value: $value, onChange: { newVal in
                     updateSystemValue(newVal)
                 }, accentColor: accent, compact: true)
                    .frame(maxWidth: .infinity)
            } else {
                Text(value > 0 ? "Unmuted" : "Muted")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .fixedSize()
            }
            
            // Percentage Text
            if type != .mic && showPercentage {
                Text("\(Int(value * 100))%")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.gray)
                    .monospacedDigit()
                    .frame(width: 35, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.black)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    func SpeakerSymbol(_ value: CGFloat) -> String {
        switch(value) {
            case 0: return "speaker.slash"
            case 0...0.33: return "speaker.wave.1"
            case 0.33...0.66: return "speaker.wave.2"
            default: return "speaker.wave.3"
        }
    }
    
    func updateSystemValue(_ newVal: CGFloat) {
        switch type {
        case .volume:
            VolumeManager.shared.setAbsolute(Float32(newVal))
        case .brightness:
            BrightnessManager.shared.setAbsolute(value: Float32(newVal))
        default:
            break
        }
    }
}

#Preview {
    OpenNotchOSD(type: .constant(.volume), value: .constant(0.5), icon: .constant(""), accent: .constant(nil))
        .environmentObject(BoringViewModel())
        .padding()
        .background(Color.gray)
}
