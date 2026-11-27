//
//  NotchClockView.swift
//  boringNotch
//

import Defaults
import SwiftUI

/// Time, and optionally the date, for the closed notch on displays without a
/// physical notch (showClockWithoutNotch). Uses the system's 12/24-hour and
/// date format settings.
struct NotchClockView: View {
    @Default(.clockShowsDate) private var showsDate

    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 8) {
                if showsDate {
                    Text(context.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                        .foregroundStyle(.gray)
                }
                Text(context.date, format: .dateTime.hour().minute())
                    .foregroundStyle(.white)
            }
            .font(.system(size: 13, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1)
        }
    }
}
