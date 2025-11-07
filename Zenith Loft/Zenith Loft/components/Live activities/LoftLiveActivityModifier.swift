//
//  LoftLiveActivityModifier.swift
//  Zenith Loft (LoftOS)
//  Created by You on 11/05/25
//
//  Clean-room replacement for dynamic notch overlays
//  Displays live “activity” content (e.g., charging, media, downloads)
//  between left + right subviews.
//

import SwiftUI

// MARK: - Supported activity types
enum LoftActivityType {
    case mediaPlayback
    case charging
    case download
    case custom(String)
}

// MARK: - Modifier
struct LoftLiveActivityModifier<Left: View, Right: View>: ViewModifier {
    let type: LoftActivityType
    let leftContent: () -> Left
    let rightContent: () -> Right

    func body(content: Content) -> some View {
        content
            .overlay(
                HStack {
                    leftContent()
                    Spacer(minLength: 8)
                    rightContent()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .center)
                .background(Color.clear)
            )
    }
}

// MARK: - Extension for convenience
extension View {
    func loftLiveActivity<Left: View, Right: View>(
        type: LoftActivityType,
        @ViewBuilder left: @escaping () -> Left,
        @ViewBuilder right: @escaping () -> Right
    ) -> some View {
        self.modifier(
            LoftLiveActivityModifier(
                type: type,
                leftContent: left,
                rightContent: right
            )
        )
    }
}

// MARK: - Example preview
#Preview {
    RoundedRectangle(cornerRadius: 12)
        .fill(.black)
        .frame(width: 300, height: 60)
        .loftLiveActivity(type: .download) {
            Label("Download", systemImage: "arrow.down.circle")
                .foregroundStyle(.white)
        } right: {
            Text("42%")
                .font(.headline)
                .foregroundStyle(.green)
        }
        .padding()
        .background(Color.gray.opacity(0.3))
}
