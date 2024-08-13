//
//  SystemEventIndicatorModifier.swift
//  boringNotch
//
//  Created by Richard Kunkli on 12/08/2024.
//

import SwiftUI

struct SystemEventIndicatorModifier: ViewModifier {
    @State var eventType: SystemEventType
    @State var value: Int
    
    func body(content: Content) -> some View {
        content
    }
}

enum SystemEventType {
    case volume
    case brightness
    case backlight
}

extension View {
    func systemEventIndicator(for eventType: SystemEventType, value: Int) -> some View {
        self.modifier(SystemEventIndicatorModifier(eventType: eventType, value: value))
    }
}
