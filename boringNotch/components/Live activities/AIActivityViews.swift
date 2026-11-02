import AppKit
import SwiftUI

enum AIActivityLayout {
    static func wingWidth(height: CGFloat) -> CGFloat { max(42, min(50, height + 14)) }
    static func additionalWidth(height: CGFloat) -> CGFloat {
        2 * wingWidth(height: height) + 2 * cornerRadiusInsets.closed.bottom
    }
}

struct TrafficLightView: View {
    let status: AIActivityStatus
    var diameter: CGFloat = 8
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let colors = [Color(red: 1, green: 0.373, blue: 0.341),
                          Color(red: 1, green: 0.741, blue: 0.18),
                          Color(red: 0.157, green: 0.784, blue: 0.251)]

    var body: some View {
        HStack(spacing: diameter * 0.625) {
            ForEach(0..<3) { index in
                let illuminated = status.illuminatedLamp == index
                Circle()
                    .fill(colors[index].opacity(illuminated ? 1 : 0.19))
                    .overlay(alignment: .top) {
                        Ellipse().fill(.white.opacity(illuminated ? 0.4 : 0.07))
                            .frame(width: diameter * 0.5, height: diameter * 0.22)
                            .padding(.top, diameter * 0.12)
                    }
                    .overlay { Circle().strokeBorder(.black.opacity(0.2), lineWidth: 0.5) }
                    .shadow(color: illuminated ? colors[index].opacity(0.38) : .clear, radius: 3)
                    .frame(width: diameter, height: diameter)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: status)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(status.label))
    }
}

/// Offline pixel companions. The Claude and Codex body geometry is adapted from
/// CodeIsland's ClawdView/DexView (MIT, copyright 2026 wxtsky).
/// See THIRD_PARTY_LICENSES. ChatGPT's dialogue face is a Boring Notch companion,
/// rather than a claim that the provider has an official mascot.
struct AIMascotView: View {
    let provider: AIProvider
    let status: AIActivityStatus
    var action: AIActivityAction? = nil
    var size: CGFloat = 24
    var animates = true
    /// Desk props (keyboard, book, terminal…) are too fine to read at icon sizes.
    var showsProps = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var manager = AIActivityManager.shared
    @State private var frame = 0

    private var motionKey: String { "\(provider.rawValue):\(status.rawValue):\(animates && manager.allowsAnimation && !reduceMotion)" }

    var body: some View {
        Canvas { context, canvasSize in
            let unit = min(canvasSize.width, canvasSize.height) / 20
            let t = Double(frame) / 12
            let moving = frame > 0
            // Static rows still show the prop for the current action; only the motion needs frames.
            let pose = status == .working && showsProps ? action ?? .editing : nil
            let working = pose != nil && moving
            let bounce = working ? sin(t * .pi * 2 / 0.8) * 0.65
                : status == .completed && t < 0.7 ? -sin(t / 0.7 * .pi) * 2 : 0
            func rectangle(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ color: Color) {
                context.fill(Path(CGRect(x: x * unit, y: (y + bounce) * unit,
                                         width: w * unit, height: h * unit)), with: .color(color))
            }
            // Props sit on the desk below the companion and do not bounce with it.
            func prop(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ color: Color) {
                context.fill(Path(CGRect(x: x * unit, y: y * unit, width: w * unit, height: h * unit)), with: .color(color))
            }
            func oval(_ x: Double, _ y: Double, _ w: Double, _ h: Double, fill: Color? = nil,
                      stroke: Color? = nil, line: Double = 0.8) {
                let path = Path(ellipseIn: CGRect(x: x * unit, y: y * unit, width: w * unit, height: h * unit))
                if let fill { context.fill(path, with: .color(fill)) }
                if let stroke { context.stroke(path, with: .color(stroke), lineWidth: line * unit) }
            }
            let claude = provider == .claude || provider == .claudeCode
            let bodyColor: Color = claude ? Color(red: 0.871, green: 0.533, blue: 0.427)
                : provider == .chatgpt ? Color(red: 0.66, green: 0.87, blue: 0.77) : Color(white: 0.93)
            if claude {
                rectangle(4, 5, 12, 9, bodyColor)
                // Both arms up to celebrate; one hand up to ask a question, waving gently.
                let wave = status == .needsAttention && moving && frame % 12 >= 6 ? 0.8 : 0
                func arm(_ shoulder: Double, outward: Double, raised: Bool, lift: Double = 0) {
                    if raised {
                        // A short shoulder plus a forearm angled out and up reads as a raised hand.
                        rectangle(shoulder, 6.5, 2, 2, bodyColor)
                        rectangle(shoulder + outward, 3.4 + lift, 1.6, 3.4, bodyColor)
                    } else {
                        rectangle(shoulder, 8, 2, 5, bodyColor)
                    }
                }
                arm(2, outward: -0.8, raised: status == .completed)
                arm(16, outward: 1.2, raised: status == .completed || status == .needsAttention, lift: wave)
                for x in [5.0, 8, 12, 15] {
                    let step = working ? (Int(t * 6) % 2 == Int(x) % 2 ? 1.0 : 0) : 0
                    rectangle(x, 14 + step, 1, 3 - step, bodyColor)
                }
            } else {
                let rows: [(Double, Double, Double)] = [(5, 5, 2), (5, 8.5, 3), (5, 13, 2),
                    (6, 4, 12), (7, 3, 14), (8, 3, 14), (9, 2, 16), (10, 2, 16),
                    (11, 2, 16), (12, 3, 14), (13, 4, 12), (14, 5, 10)]
                // Rows overlap slightly so antialiasing never shows seams between them.
                for (y, x, width) in rows { rectangle(x, y, width, 1.05, bodyColor) }
                rectangle(6, 15, 1, 2, bodyColor.opacity(0.7))
                rectangle(13, 15, 1, 2, bodyColor.opacity(0.7))
            }

            // Eyes follow the work: down at a book, sideways after a magnifying glass.
            let glassX = 10 + (moving ? sin(t * 1.6) * 4.5 : 0)
            let look: (x: Double, y: Double) = switch pose {
            case .reading: (moving ? Double(Int(t * 2) % 3 - 1) * 0.6 : 0, 1)
            case .searching: ((glassX - 10) / 4.5, 0.5)
            case .running, .testing, .browsing: (0, 1)
            default: (0, 0)
            }
            // Faces carry most of the charm: blinks, eye highlights, blush, and a mood per state.
            let blink = moving && status != .completed && frame % 46 >= 44
            let sleepy = [.unknown, .idle, .interrupted].contains(status)
            let happy = status == .completed
            let blush = Color(red: 1, green: 0.42, blue: 0.5).opacity(0.75)
            if provider == .codex {
                rectangle(3.2, 12.2, 1.5, 0.8, blush)
                rectangle(13.8, 12.2, 1.5, 0.8, blush)
                if blink || sleepy {
                    rectangle(4.8 + look.x, 10.2 + look.y, 2, 0.8, .black)
                } else {
                    rectangle(5 + look.x, 9 + look.y, 1, 1, .black)
                    rectangle(6 + look.x, 10 + look.y, 1, 1, .black)
                    rectangle(5 + look.x, 11 + look.y, 1, 1, .black)
                }
                if happy {
                    rectangle(9, 10.6, 0.9, 0.9, .black)
                    rectangle(9.9, 11.4, 2.2, 0.9, .black)
                    rectangle(12.1, 10.6, 0.9, 0.9, .black)
                } else if !working || frame % 8 < 5 {
                    rectangle(9 + look.x, 11 + look.y, 4, 1, .black)
                }
            } else {
                func eye(_ left: Double) {
                    let center = left + 0.65 + look.x, top = 8 + look.y
                    if happy {
                        rectangle(center - 1.3, top + 1.6, 0.9, 0.9, .black)
                        rectangle(center - 0.45, top + 0.8, 0.9, 0.9, .black)
                        rectangle(center + 0.4, top + 1.6, 0.9, 0.9, .black)
                    } else if blink || sleepy {
                        rectangle(center - 0.75, top + 1.8, 1.5, 0.7, .black)
                    } else {
                        // Wide eyes while waiting for you.
                        let width = status == .needsAttention ? 1.7 : 1.3, height = status == .needsAttention ? 3.0 : 2.7
                        let y = top - (height - 2.7) / 2
                        rectangle(center - width / 2, y, width, height, .black)
                        rectangle(center - width / 2 + 0.15, y + 0.3, 0.6, 0.6, .white.opacity(0.9))
                    }
                }
                eye(6)
                eye(12.7)
                rectangle(4.5, 11.3, 1.6, 0.9, blush)
                rectangle(13.9, 11.3, 1.6, 0.9, blush)
                let mouth: Color = provider == .chatgpt ? .black.opacity(0.7) : .black
                if happy {
                    rectangle(8.6, 11.4, 0.8, 0.8, mouth)
                    rectangle(9.4, 12.1, 1.2, 0.8, mouth)
                    rectangle(10.6, 11.4, 0.8, 0.8, mouth)
                } else if provider == .chatgpt {
                    rectangle(8, 12, 4, 1, mouth)
                }
            }

            let green = Color(red: 0.36, green: 0.9, blue: 0.45)
            func terminal() {
                prop(2, 15, 16, 4.6, Color(white: 0.1))
                prop(2, 15, 16, 0.8, Color(white: 0.36))
                prop(3, 16.4, 0.8, 0.8, green)
                prop(3.8, 17.2, 0.8, 0.8, green)
                prop(3, 18, 0.8, 0.8, green)
            }
            switch pose {
            case nil: break
            case .editing, .usingTool:
                // Tiny keyboard: only the companion canvas changes each frame.
                prop(2, 16, 16, 3, Color(white: 0.24))
                for key in 0..<6 {
                    prop(3 + Double(key) * 2.4, 17, 1.5, 0.8,
                         working && Int(t * 8) % 6 == key ? .white : Color(white: 0.5))
                }
            case .reading:
                prop(2.5, 15.5, 7, 3.8, Color(white: 0.93))
                prop(10.5, 15.5, 7, 3.8, Color(white: 0.84))
                prop(9.5, 15, 1, 4.6, Color(red: 0.55, green: 0.33, blue: 0.2))
                let line = moving ? Int(t * 3) % 4 : -1
                for index in 0..<4 {
                    let x = index < 2 ? 3.5 : 11.5
                    prop(x, 16.4 + Double(index % 2) * 1.4, 5, 0.6,
                         index == line ? Color(red: 0.86, green: 0.47, blue: 0.36) : Color(white: 0.6))
                }
            case .searching:
                oval(glassX - 2.2, 13.6, 4.4, 4.4, fill: Color(red: 0.6, green: 0.8, blue: 1).opacity(0.35),
                     stroke: Color(white: 0.92), line: 0.9)
                prop(glassX + 1.4, 17.6, 2.2, 1.1, Color(red: 0.55, green: 0.33, blue: 0.2))
            case .running:
                terminal()
                if !moving || frame % 12 < 6 { prop(5.2, 18, 1.6, 0.8, green) }
            case .testing:
                terminal()
                let passed = moving ? Int(t * 4) % 7 : 3
                for index in 0..<passed { prop(5.6 + Double(index) * 1.7, 17.3, 1.1, 1.1, green) }
            case .browsing:
                oval(7.2, 14.2, 5.6, 5.6, fill: Color(red: 0.3, green: 0.56, blue: 0.95))
                let meridian = 5.6 * abs(cos(moving ? t * 2.5 : 0.6))
                oval(10 - meridian / 2, 14.2, meridian, 5.6, stroke: .white.opacity(0.65), line: 0.45)
                prop(7.4, 16.8, 5.2, 0.45, .white.opacity(0.65))
            case .delegating:
                // A small helper hops beside the companion.
                let hop = moving ? -abs(sin(t * 4)) * 1.4 : 0
                prop(14, 15.4 + hop, 4.4, 3, bodyColor.opacity(0.9))
                prop(14.8, 16.1 + hop, 0.7, 1, .black)
                prop(16.8, 16.1 + hop, 0.7, 1, .black)
                prop(14.6, 18.4 + hop, 0.7, 1, bodyColor.opacity(0.9))
                prop(16.8, 18.4 + hop, 0.7, 1, bodyColor.opacity(0.9))
            case .thinking:
                let lit = moving ? Int(t * 3) % 4 : 3
                for index in 0..<3 {
                    prop(12.6 + Double(index) * 2.2, 1, 1.4, 1.4, .white.opacity(index < lit ? 0.95 : 0.25))
                }
            }

            if status == .needsAttention && (!moving || frame % 12 < 8) {
                let yellow = Color(red: 1, green: 0.78, blue: 0.2)
                let x = claude ? 1.2 : 16.8  // Claude's raised hand is on the right.
                prop(x, 0.4, 1.6, 2.8, yellow)
                prop(x, 3.7, 1.6, 1.1, yellow)
            }
            if status == .completed && moving && frame < 9 {
                let confetti: [(Double, Double, Color)] = [
                    (3, 1, Color(red: 1, green: 0.37, blue: 0.34)), (8, 0, Color(red: 1, green: 0.74, blue: 0.18)),
                    (14, 1.5, green), (17.5, 3, Color(red: 0.3, green: 0.56, blue: 0.95)),
                    (1, 4, Color(red: 1, green: 0.74, blue: 0.18))]
                for (x, y, color) in confetti { prop(x, y + Double(frame) * 0.5, 1, 1, color) }
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .accessibilityHidden(true)
        .task(id: motionKey) {
            frame = 0
            guard animates, manager.allowsAnimation, !reduceMotion,
                  [.working, .needsAttention, .completed].contains(status) else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(83)) } catch { return }
                frame += 1
                if status == .completed && frame >= 9 { return }
            }
        }
    }
}

struct AIActivityLiveActivity: View {
    /// One companion per provider, most urgent first; the lamps describe the first.
    let groups: [AIActivityGroup]
    var banner: AIActivitySession? = nil
    let notchWidth: CGFloat
    let height: CGFloat

    private var lead: AIActivitySession { groups[0].lead }
    private var mascotSize: CGFloat { max(12, min(26, height - 6)) }

    private var totalWidth: CGFloat { notchWidth + 2 * AIActivityLayout.wingWidth(height: height) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                companions
                    .frame(width: AIActivityLayout.wingWidth(height: height))
                Color.clear.frame(width: notchWidth)
                TrafficLightView(status: lead.status, diameter: min(8, max(5, height / 4)))
                    .frame(width: AIActivityLayout.wingWidth(height: height))
            }
            .frame(height: height)
            if let banner {
                // The notch grows downward like a sneak peek, so a question cannot go unnoticed.
                AIAttentionBanner(session: banner)
                    .frame(width: totalWidth - 2 * cornerRadiusInsets.closed.bottom)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.smooth, value: groups.map(\.id))
        .help(groups.map(describe).joined(separator: "\n"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(groups.map(describe).joined(separator: "; ")))
    }

    // Overlapping avatars fit two companions in the existing wing, so the notch never widens.
    // Only the front companion animates; the one behind still shows its pose.
    private var companions: some View {
        HStack(alignment: .bottom, spacing: -mascotSize * 0.2) {
            ForEach(Array(groups.prefix(2).enumerated()), id: \.element.id) { index, group in
                AIMascotView(provider: group.provider, status: group.lead.status, action: group.lead.action,
                             size: index == 0 ? mascotSize : mascotSize * 0.8, animates: index == 0)
                    .opacity(index == 0 ? 1 : 0.75)
                    // Badges sit on the outer edges so they never cover the other companion.
                    .overlay(alignment: index == 0 ? .bottomLeading : .bottomTrailing) {
                        if group.count > 1 { badge("\(group.count)", x: index == 0 ? 0 : 2) }
                    }
                    .overlay(alignment: .topTrailing) { if index == 1 && groups.count > 2 { badge("+\(groups.count - 2)", x: 2) } }
                    .zIndex(Double(2 - index))
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
    }

    private func badge(_ text: String, x: CGFloat) -> some View {
        Text(text)
            .font(.system(size: max(5, mascotSize * 0.24), weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 2)
            .background(Capsule().fill(Color(white: 0.3)))
            .offset(x: x, y: 1)
    }

    private func describe(_ group: AIActivityGroup) -> String {
        let session = group.lead
        let count = group.count > 1 ? " ×\(group.count)" : ""
        return "\(session.provider.name)\(count) · \(session.caption ?? session.status.label)\(session.source == .preview ? " · Preview" : "")"
    }
}

/// The AI tab's icon is the front companion itself: in color while something is live, gray otherwise.
struct AITabIcon: View {
    let selected: Bool
    @ObservedObject private var manager = AIActivityManager.shared

    var body: some View {
        let lead = manager.selectedSession
        let live = (lead?.status.priority ?? 0) >= 2
        AIMascotView(provider: lead?.provider ?? .claudeCode, status: lead?.status ?? .idle,
                     size: 18, animates: false, showsProps: false)
            // Desaturated, the body's brightness already matches the gray symbols beside it.
            .saturation(selected || live ? 1 : 0)
    }
}

struct AIAttentionBanner: View {
    let session: AIActivitySession
    private let yellow = Color(red: 1, green: 0.741, blue: 0.18)

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.bubble.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(yellow)
                .symbolEffect(.pulse, options: .repeating)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(session.provider.name) needs you")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                // Keep the project when it fits; the reason matters more.
                ViewThatFits(in: .horizontal) {
                    if !session.project.isEmpty { Text("\(session.reason) · \(session.project)") }
                    Text(session.reason)
                }
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.65))
            }
            .lineLimit(1)
            .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(yellow.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(yellow.opacity(0.3), lineWidth: 0.5))
    }
}

struct AIActivityDetailView: View {
    @ObservedObject private var manager = AIActivityManager.shared

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(manager.connectionWarnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.yellow)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
                if manager.sessions.isEmpty {
                    HStack(spacing: 16) {
                        AIMascotView(provider: .claudeCode, status: .idle, size: 40, animates: false)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Your AI companions are quiet").font(.headline)
                            Text("Connect Claude Code or Codex in Settings → AI Activities.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 24)
                } else {
                    ForEach(manager.sessions) { AIActivityRow(session: $0) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
    }
}

/// Live sessions are what you opened the notch for: large animated cards. Finished and idle
/// rows stay compact and static.
struct AIActivityRow: View {
    let session: AIActivitySession
    @ObservedObject private var manager = AIActivityManager.shared

    var body: some View {
        let live = session.status.priority >= 2
        HStack(spacing: live ? 14 : 10) {
            AIMascotView(provider: session.provider, status: session.status, action: session.action,
                         size: live ? 46 : 28, animates: live)
            Button { if session.source != .preview { manager.open(session) } } label: {
                VStack(alignment: .leading, spacing: live ? 4 : 3) {
                    HStack(spacing: 6) {
                        Text(session.provider.name).font(.system(size: live ? 15 : 13, weight: live ? .semibold : .medium))
                        if !session.project.isEmpty {
                            Text("· \(session.project)").font(.system(size: live ? 15 : 13)).foregroundStyle(.secondary)
                        }
                    }.lineLimit(1)
                    Group {
                        if let caption = session.caption, let action = session.action {
                            Label(caption, systemImage: action.symbol).lineLimit(1).truncationMode(.middle)
                        } else {
                            Text(session.reason).lineLimit(2)
                        }
                    }
                    .font(.system(size: live ? 13 : 11))
                    .foregroundStyle(session.status == .needsAttention ? Color(red: 1, green: 0.741, blue: 0.18) : .secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(session.source == .preview ? "Preview only" : "Open \(session.provider.name)")
            VStack(alignment: .trailing, spacing: 5) {
                TrafficLightView(status: session.status, diameter: live ? 11 : 8)
                Text(session.status.label).font(.system(size: live ? 11 : 10)).foregroundStyle(.secondary)
            }
            if session.status.priority < 2 || session.source == .preview {
                Button { manager.dismiss(session) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Dismiss finished activity").accessibilityLabel("Dismiss finished activity")
            }
        }
        .padding(.horizontal, live ? 12 : 8).padding(.vertical, live ? 9 : 5)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(live ? 0.07 : 0)))
    }
}

#Preview("AI traffic lights") {
    VStack(spacing: 20) {
        ForEach([AIActivityStatus.working, .needsAttention, .completed, .unknown], id: \.self) { status in
            AIActivityLiveActivity(groups: [AIActivityGroup(lead: AIActivitySession(provider: .claudeCode, sessionID: "preview", status: status))],
                                   notchWidth: 185, height: 32)
        }
        AIActivityLiveActivity(groups: [AIActivityGroup(lead: AIActivitySession(provider: .claudeCode, sessionID: "a", status: .needsAttention)),
                                        AIActivityGroup(lead: AIActivitySession(provider: .codex, sessionID: "b", status: .working), count: 2)],
                               notchWidth: 185, height: 32)
    }.padding(24).background(.black)
}
