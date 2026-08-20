//
//  ReelsLiveActivity.swift
//  boringNotch
//
//  Closed-notch nudge shown while you're on a reels/shorts feed: an icon on the
//  left wing, today's watch time on the right. Turns red and switches to a
//  "stop" glyph once you've passed the daily limit.
//

import Defaults
import SwiftUI

struct ReelsLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var reels = ReelsManager.shared
    @Default(.reelsNotchMetric) private var metric

    private var tint: Color {
        reels.isOverLimit
            ? Color(red: 1.0, green: 0.32, blue: 0.32)   // red — over limit
            : Color(red: 1.0, green: 0.62, blue: 0.25)   // amber — watching
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left wing: the reel COUNT (replaces the old icon), pulsing gently.
            HStack(spacing: 4) {
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let pulse = (sin(t * 3) + 1) / 2
                    HStack(spacing: 3) {
                        Text("\(reels.todayCount)")
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                        Image(systemName: reels.isOverLimit ? "hand.raised.fill" : "play.rectangle.fill")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(tint)
                    .opacity(0.75 + pulse * 0.25)
                }
                Spacer(minLength: 0)
            }
            .frame(
                width: max(0, vm.effectiveClosedNotchHeight - 12 + 34),
                height: max(0, vm.effectiveClosedNotchHeight - 12)
            )
            .padding(.leading, 8)

            // Middle: the physical notch gap.
            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width)

            // Right wing: secondary metric (time, or "reels" label if count-only).
            HStack {
                Spacer(minLength: 0)
                Text(rightText)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint.opacity(0.85))
                    .lineLimit(1)
            }
            .frame(
                width: max(0, vm.effectiveClosedNotchHeight - 12 + 34),
                height: max(0, vm.effectiveClosedNotchHeight - 12)
            )
            .padding(.trailing, 8)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }

    private var rightText: String {
        switch metric {
        case "time": return timeString
        case "count": return "reels"
        default:      return timeString   // "both"
        }
    }

    private var timeString: String {
        let total = Int(reels.todaySeconds)
        let m = total / 60
        let s = total % 60
        return m > 0 ? "\(m)m" : "\(s)s"
    }
}
