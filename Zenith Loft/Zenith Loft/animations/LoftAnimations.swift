//
//  LoftAnimations.swift
//  Zenith Loft
//
//  Created by Carson Livezey on 11/05/25.
//  Part of LoftOS — A Dynamic Notch Experience
//

import SwiftUI

/// Controls all system animations for the Zenith Loft HUD and its tiles.
public final class LoftAnimations: ObservableObject {
    /// Current presentation style for the HUD — defaults to dynamic notch mode.
    @Published var hudStyle: LoftStyle = .notch

    init() {
        self.hudStyle = .notch
    }

    /// Global animation used for HUD transitions.
    var animation: Animation {
        if #available(macOS 14.0, *), hudStyle == .notch {
            // Bouncy, modern spring on newer macOS
            return .spring(duration: 0.4, bounce: 0.5)
        } else {
            // Legacy smooth curve for older systems
            return .timingCurve(0.16, 1, 0.3, 1, duration: 0.7)
        }
    }
}

/// Supported display styles for LoftOS HUD.
enum LoftStyle {
    case notch
    case floating
}
