//
//  NotchPanelAnimation.swift
//  boringNotch
//
//  Created by Codex on 2026-06-30.
//

import Foundation
import SwiftUI

enum NotchPanelAnimation {
    static let spring = Animation.interactiveSpring(response: 0.52, dampingFraction: 0.9, blendDuration: 0)
    static let contentTransition = AnyTransition.asymmetric(
        insertion: .scale(scale: 0.82, anchor: .top).combined(with: .opacity),
        removal: .scale(scale: 0.92, anchor: .top).combined(with: .opacity)
    )
}
