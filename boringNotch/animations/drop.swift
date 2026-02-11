//
//  drop.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on  04/08/24.
//

import Foundation
import SwiftUI

// MARK: - Standardized Animations
/// Centralized animation definitions for consistent UI behavior across the app.
enum StandardAnimations {
    /// Interactive spring for responsive UI (used for notch interactions)
    static let interactive = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)
    
    /// Spring animation for opening the notch
    static let open = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
    
    /// Spring animation for closing the notch
    static let close = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)
    
    /// Bouncy spring for playful animations
    @available(macOS 14.0, *)
    static var bouncy: Animation {
        Animation.spring(.bouncy(duration: 0.4))
    }
    
    /// Smooth animation for general transitions
    static let smooth = Animation.smooth
    
    /// Entry animation for the closed-notch mute badge
    static let muteBadgeIn = Animation.spring(response: 0.28, dampingFraction: 0.78, blendDuration: 0)
    
    /// Exit animation for the closed-notch mute badge
    static let muteBadgeOut = Animation.easeOut(duration: 0.16)
    
    /// One-shot pulse used when mute turns on
    static let muteBadgeBurst = Animation.spring(response: 0.38, dampingFraction: 0.72, blendDuration: 0)
    
    /// Timing curve fallback for older macOS versions
    static let timingCurve = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.7)
}

public class BoringAnimations {
    @Published var notchStyle: Style = .notch
    
    init() {
        self.notchStyle = .notch
    }
    
    var animation: Animation {
        if #available(macOS 14.0, *), notchStyle == .notch {
            StandardAnimations.bouncy
        } else {
            StandardAnimations.timingCurve
        }
    }
}
