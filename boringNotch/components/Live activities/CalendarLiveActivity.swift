//
//  CalendarLiveActivity.swift
//  boringNotch
//
//  Right-side ring of the closed-notch calendar live activity: a countdown
//  ring around a calendar glyph. `progress` is 1 (full) → 0 (empty).
//

import SwiftUI

struct CalendarLiveActivityRing: View {
    let progress: Double
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.25), lineWidth: 2)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.accentColor,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: progress)
            Image(systemName: "calendar")
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundStyle(.gray)
        }
        .frame(width: size, height: size)
    }
}
