//
//  KairoActivityWidget.swift
//  KairoiOS Widget Extension — Live Activity + Dynamic Island
//
//  Three layouts:
//    • Lock-screen / banner — used when the Live Activity is displayed
//      outside the Dynamic Island (older devices, lock screen, banner)
//    • Dynamic Island — compact, expanded, and minimal presentations
//
//  Visual identity:
//    • Compact: just an orb + state pill
//    • Expanded: orb + primary text + secondary text + state pill
//    • Minimal: a single colored dot reflecting state
//

import ActivityKit
import SwiftUI
import WidgetKit

@main
struct KairoWidgetBundle: WidgetBundle {
    var body: some Widget {
        KairoLiveActivity()
    }
}

// MARK: - Live Activity

struct KairoLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: KairoActivityAttributes.self) { context in
            // Lock-screen / banner layout
            LockScreenView(state: context.state, attrs: context.attributes)
                .activityBackgroundTint(Kairo.Palette.background)
                .activitySystemActionForegroundColor(Kairo.Palette.text)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading)  { ExpandedLeading(state: context.state) }
                DynamicIslandExpandedRegion(.trailing) { ExpandedTrailing(state: context.state) }
                DynamicIslandExpandedRegion(.center)   { ExpandedCenter(state: context.state) }
                DynamicIslandExpandedRegion(.bottom)   { ExpandedBottom(state: context.state, attrs: context.attributes) }
            } compactLeading: {
                CompactLeading(state: context.state)
            } compactTrailing: {
                CompactTrailing(state: context.state)
            } minimal: {
                MinimalGlyph(state: context.state)
            }
            .widgetURL(URL(string: "kairo://open"))
            .keylineTint(stateTint(context.state.mode))
        }
    }

    private func stateTint(_ mode: KairoActivityAttributes.State.Mode) -> Color {
        switch mode {
        case .idle:       return Kairo.Palette.orbCore
        case .listening:  return Kairo.Palette.accent
        case .thinking:   return Kairo.Palette.orbCore
        case .speaking:   return Kairo.Palette.accent
        case .nowPlaying: return Kairo.Palette.success
        }
    }
}

// MARK: - Lock-screen layout

private struct LockScreenView: View {
    let state: KairoActivityAttributes.State
    let attrs: KairoActivityAttributes

    var body: some View {
        HStack(spacing: Kairo.Space.md) {
            OrbBadge(mode: state.mode, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.primaryText)
                    .font(Kairo.Typography.bodyEmphasis)
                    .foregroundStyle(Kairo.Palette.text)
                    .lineLimit(1)
                if let secondary = state.secondaryText {
                    Text(secondary)
                        .font(Kairo.Typography.bodySmall)
                        .foregroundStyle(Kairo.Palette.textDim)
                        .lineLimit(1)
                }
            }
            Spacer()
            StatePill(mode: state.mode)
        }
        .padding(Kairo.Space.md)
    }
}

// MARK: - Dynamic Island regions

private struct CompactLeading: View {
    let state: KairoActivityAttributes.State
    var body: some View {
        OrbBadge(mode: state.mode, size: 18)
            .padding(.leading, 4)
    }
}

private struct CompactTrailing: View {
    let state: KairoActivityAttributes.State
    var body: some View {
        Text(compactLabel(state.mode))
            .font(Kairo.Typography.captionStrong)
            .foregroundStyle(tint(state.mode))
            .padding(.trailing, 6)
    }

    private func compactLabel(_ mode: KairoActivityAttributes.State.Mode) -> String {
        switch mode {
        case .idle:       return "Idle"
        case .listening:  return "•"   // a colored dot ≈ recording indicator
        case .thinking:   return "…"
        case .speaking:   return "K"
        case .nowPlaying: return "♪"
        }
    }

    private func tint(_ mode: KairoActivityAttributes.State.Mode) -> Color {
        switch mode {
        case .listening, .speaking: return Kairo.Palette.accent
        case .nowPlaying:           return Kairo.Palette.success
        default:                    return Kairo.Palette.textDim
        }
    }
}

private struct MinimalGlyph: View {
    let state: KairoActivityAttributes.State
    var body: some View {
        Circle()
            .fill(minimalColor(state.mode))
            .frame(width: 16, height: 16)
            .overlay(
                Image(systemName: "k.circle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .opacity(0.85)
            )
    }

    private func minimalColor(_ mode: KairoActivityAttributes.State.Mode) -> Color {
        switch mode {
        case .listening, .speaking: return Kairo.Palette.accent
        case .nowPlaying:           return Kairo.Palette.success
        default:                    return Kairo.Palette.orbCore
        }
    }
}

private struct ExpandedLeading: View {
    let state: KairoActivityAttributes.State
    var body: some View {
        OrbBadge(mode: state.mode, size: 28)
            .padding(.leading, 4)
    }
}

private struct ExpandedTrailing: View {
    let state: KairoActivityAttributes.State
    var body: some View {
        StatePill(mode: state.mode)
            .padding(.trailing, 4)
    }
}

private struct ExpandedCenter: View {
    let state: KairoActivityAttributes.State
    var body: some View {
        VStack(spacing: Kairo.Space.xxs) {
            Text(state.primaryText)
                .font(Kairo.Typography.bodyEmphasis)
                .foregroundStyle(Kairo.Palette.text)
                .lineLimit(1)
            if let secondary = state.secondaryText {
                Text(secondary)
                    .font(Kairo.Typography.bodySmall)
                    .foregroundStyle(Kairo.Palette.textDim)
                    .lineLimit(1)
            }
        }
    }
}

private struct ExpandedBottom: View {
    let state: KairoActivityAttributes.State
    let attrs: KairoActivityAttributes
    var body: some View {
        HStack {
            Image(systemName: "laptopcomputer")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Kairo.Palette.textDim)
            Text(attrs.macDeviceName)
                .font(Kairo.Typography.caption)
                .foregroundStyle(Kairo.Palette.textDim)
            Spacer()
            Text(state.timestamp, style: .relative)
                .font(Kairo.Typography.mono)
                .foregroundStyle(Kairo.Palette.textDim)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Reusable bits

private struct OrbBadge: View {
    let mode: KairoActivityAttributes.State.Mode
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [Kairo.Palette.orbCore, Kairo.Palette.orbDeep, .black],
                    center: UnitPoint(x: 0.3, y: 0.3),
                    startRadius: 1,
                    endRadius: size
                ))
            Circle()
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
            if mode == .listening || mode == .speaking {
                Circle()
                    .strokeBorder(Kairo.Palette.accent.opacity(0.5), lineWidth: 1.5)
                    .scaleEffect(1.1)
            }
        }
        .frame(width: size, height: size)
    }
}

private struct StatePill: View {
    let mode: KairoActivityAttributes.State.Mode

    private var label: String {
        switch mode {
        case .idle:       return "Idle"
        case .listening:  return "Listening"
        case .thinking:   return "Thinking"
        case .speaking:   return "Speaking"
        case .nowPlaying: return "Now playing"
        }
    }

    private var color: Color {
        switch mode {
        case .listening, .speaking: return Kairo.Palette.accent
        case .nowPlaying:           return Kairo.Palette.success
        case .thinking:             return Kairo.Palette.orbCore
        case .idle:                 return Kairo.Palette.textDim
        }
    }

    var body: some View {
        HStack(spacing: Kairo.Space.xs) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(Kairo.Typography.captionStrong)
                .foregroundStyle(color)
        }
        .padding(.horizontal, Kairo.Space.sm)
        .padding(.vertical, Kairo.Space.xxs + 1)
        .background(
            Capsule().fill(color.opacity(0.15))
        )
        .overlay(
            Capsule().strokeBorder(color.opacity(0.30), lineWidth: 0.5)
        )
    }
}
