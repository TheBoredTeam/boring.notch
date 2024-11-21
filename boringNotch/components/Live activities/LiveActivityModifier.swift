//
//  LiveActivityModifier.swift
//  boringNotch
//
//  Created by Richard Kunkli on 12/08/2024.
//

import SwiftUI

enum ActivityType {
    case mediaPlayback
    case charging
    case download
}

struct LiveActivityModifier<Left: View, Right: View>: ViewModifier {
    let `for`: ActivityType
    let leftContent: () -> Left
    let rightContent: () -> Right
    
    func body(content: Content) -> some View {
        content
            .overlay(
                HStack {
                    leftContent()
                    Spacer()
                        //.frame(minWidth: vm.closedNotchSize.width)
                    rightContent()
                }
                .padding()
            )
    }
}

extension View {
    func liveActivity<Left: View, Right: View>(
        for activityId: ActivityType,
        @ViewBuilder left: @escaping () -> Left,
        @ViewBuilder right: @escaping () -> Right
    ) -> some View {
        self.modifier(LiveActivityModifier(for: activityId, leftContent: left, rightContent: right))
    }
}
