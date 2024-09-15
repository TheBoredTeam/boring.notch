//
//  InlineHUDs.swift
//  boringNotch
//
//  Created by Richard Kunkli on 14/09/2024.
//

import SwiftUI

struct InlineHUD: View {
    @EnvironmentObject var vm: BoringViewModel
    @Binding var type: SneakContentType
    @Binding var value: CGFloat
    @Binding var hoverAnimation: Bool
    @Binding var gestureProgress: CGFloat
    var body: some View {
        HStack {
            HStack(spacing: 5) {
                switch (type) {
                    case .volume:
                        Image(systemName: SpeakerSymbol(value))
                            .contentTransition(.opacity)
                            .frame(width: 20, height: 15, alignment: .leading)
                            .foregroundStyle(.white)
                    case .brightness:
                        Image(systemName: "sun.max.fill")
                            .contentTransition(.symbolEffect)
                            .frame(width: 20, height: 15)
                            .foregroundStyle(.white)
                    case .backlight:
                        Image(systemName: "keyboard")
                            .contentTransition(.symbolEffect)
                            .frame(width: 20, height: 15)
                            .foregroundStyle(.white)
                    case .mic:
                        Image(systemName: "mic")
                            .symbolRenderingMode(.hierarchical)
                            .symbolVariant(value > 0 ? .none : .slash)
                            .contentTransition(.interpolate)
                            .frame(width: 20, height: 15)
                            .foregroundStyle(.white)
                    default:
                        EmptyView()
                }
                Text(Type2Name(type))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .allowsTightening(true)
                    .contentTransition(.numericText())
            }
            .symbolVariant(.fill)
            .frame(width: 100 - (hoverAnimation ? 0 : 12) + gestureProgress / 2, height: vm.sizes.size.closed.height! - (hoverAnimation ? 0 : 12), alignment: .leading)
            
            Rectangle()
                .fill(.black)
                .frame(width: vm.sizes.size.closed.width! - 20)
            
            HStack {
                if (type != .mic) {
                    DraggableProgressBar(value: $value)
                } else {
                    Text(value > 0 ? "unmuted" : "muted")
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                        .allowsTightening(true)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(.trailing, 4)
            .frame(width: 100 - (hoverAnimation ? 0 : 12) + gestureProgress / 2, height: vm.sizes.size.closed.height! - (hoverAnimation ? 0 : 12), alignment: .center)
        }
        .frame(height: Sizes().size.closed.height! + (hoverAnimation ? 8 : 0), alignment: .center)
    }
    
    func SpeakerSymbol(_ value: CGFloat) -> String {
        switch(value) {
            case 0:
                return "speaker.slash"
            case 0...0.3:
                return "speaker.wave.1"
            case 0.3...0.8:
                return "speaker.wave.2"
            case 0.8...1:
                return "speaker.wave.3"
            default:
                return "speaker.wave.2"
        }
    }
    
    func Type2Name(_ type: SneakContentType) -> String {
        switch(type) {
            case .volume:
                return "Volume"
            case .brightness:
                return "Brightness"
            case .backlight:
                return "Backlight"
            case .mic:
                return "Mic"
            default:
                return ""
        }
    }
}

#Preview {
    InlineHUD(type: .constant(.brightness), value: .constant(0.4), hoverAnimation: .constant(false), gestureProgress: .constant(0))
        .padding(.horizontal, 8)
        .background(Color.black)
        .padding()
        .environmentObject(BoringViewModel())
}
