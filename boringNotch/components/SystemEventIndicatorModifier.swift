//
//  SystemEventIndicatorModifier.swift
//  boringNotch
//
//  Created by Richard Kunkli on 12/08/2024.
//

import SwiftUI

struct SystemEventIndicatorModifier: ViewModifier {
    @State var eventType: SystemEventType
    @State var value: CGFloat
    let showSlider: Bool = false
    
    func body(content: Content) -> some View {
        VStack {
            content
            HStack(spacing: 20) {
                switch (eventType) {
                    case .volume:
                        Image(systemName: SpeakerSymbol(value))
                            .contentTransition(.interpolate)
                            .frame(width: 20, alignment: .leading)
                    case .brightness:
                        Image(systemName: "sun.max.fill")
                            .contentTransition(.interpolate)
                            .frame(width: 20)
                    case .backlight:
                        Image(systemName: "keyboard")
                            .contentTransition(.interpolate)
                            .frame(width: 20)
                }
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.quaternary)
                        Capsule()
                            .fill(LinearGradient(colors: [.white, .white.opacity(0.2)], startPoint: .trailing, endPoint: .leading))
                            .frame(width: geo.size.width * value)
                            .shadow(color: .white, radius: 8, x: 3)
                    }
                }
                .frame(height: 6)
            }
            .symbolVariant(.fill)
            .imageScale(.large)
            .padding(.vertical)
            if showSlider {
                Slider(value: $value.animation(.smooth), in: 0...1)
            }
        }
    }
    
    func SpeakerSymbol(_ value: CGFloat) -> String {
        switch(value) {
            case 0:
                return "speaker.slash.fill"
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
}

enum SystemEventType {
    case volume
    case brightness
    case backlight
}

extension View {
    func systemEventIndicator(for eventType: SystemEventType, value: CGFloat) -> some View {
        self.modifier(SystemEventIndicatorModifier(eventType: eventType, value: value))
    }
}

#Preview {
    EmptyView()
        .systemEventIndicator(for: .volume, value: 0.4)
        .systemEventIndicator(for: .brightness, value: 0.7)
        .systemEventIndicator(for: .backlight, value: 0.2)
        .frame(width: 200)
        .padding()
        .background(.black)
}
