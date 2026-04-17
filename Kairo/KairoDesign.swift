//
//  KairoDesign.swift
//  Kairo — Premium design system + animation components
//  Every element breathes, glows, and springs to life.
//

import AppKit
import SwiftUI

// ═══════════════════════════════════════════
// MARK: - COLOR PALETTE
// ═══════════════════════════════════════════

enum K {
    // Primary palette
    static let cyan    = Color(hex: 0x00D4FF)
    static let blue    = Color(hex: 0x0055FF)
    static let violet  = Color(hex: 0x6600FF)
    static let green   = Color(hex: 0x00FF88)
    static let red     = Color(hex: 0xFF2244)
    static let gold    = Color(hex: 0xC9A84C)
    static let orange  = Color(hex: 0xFF9F0A)
    static let pink    = Color(hex: 0xFF375F)

    // Brand colors
    static let spotify = Color(hex: 0x1DB954)
    static let apple   = Color(hex: 0xFC3C44)
    static let youtube = Color(hex: 0xFF0000)

    // Backgrounds
    static let pill    = Color(hex: 0x080A12)
    static let bg      = Color(hex: 0x04050E)
    static let panelBg = Color(hex: 0x05070F)

    // Text hierarchy
    static let text    = Color(hex: 0xDDE8F0)
    static let muted   = Color(hex: 0x304050)

    // Gradients
    static let gradient = LinearGradient(colors: [cyan, blue, violet], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let cyanBlue = LinearGradient(colors: [cyan, blue], startPoint: .leading, endPoint: .trailing)
    static let warmGlow = LinearGradient(colors: [gold, orange], startPoint: .topLeading, endPoint: .bottomTrailing)
}

// Text color convenience extensions (used across views)
extension Color {
    static let kTextPrimary   = Color.white
    static let kTextSecondary = Color.white.opacity(0.6)
    static let kTextTertiary  = Color.white.opacity(0.35)
    static let kTextMuted     = Color.white.opacity(0.2)
}

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255.0, green: Double((hex >> 8) & 0xFF) / 255.0, blue: Double(hex & 0xFF) / 255.0, opacity: alpha)
    }
}

// ═══════════════════════════════════════════
// MARK: - SPRING ANIMATIONS
// ═══════════════════════════════════════════

extension Animation {
    static let kairoSpring: Animation = .spring(response: 0.45, dampingFraction: 0.72)
    static let kairoFast: Animation   = .spring(response: 0.28, dampingFraction: 0.75)
    static let kairoSlow: Animation   = .spring(response: 0.65, dampingFraction: 0.78)
    static let kairoMicro: Animation  = .spring(response: 0.2, dampingFraction: 0.8)
    static let kairoMorph: Animation  = .spring(response: 0.55, dampingFraction: 0.72)
}

// ═══════════════════════════════════════════
// MARK: - BOUNCE BUTTON
// ═══════════════════════════════════════════

struct KairoBounce: ButtonStyle {
    var scale: CGFloat = 0.93
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.kairoMicro, value: configuration.isPressed)
    }
}

// ═══════════════════════════════════════════
// MARK: - NATIVE GLASS (macOS 26)
// ═══════════════════════════════════════════

extension View {
    func liquidGlass(cornerRadius: CGFloat = 20) -> some View {
        self
            .background(RoundedRectangle(cornerRadius: cornerRadius).glassEffect(.regular.interactive()))
            .shadow(color: .black.opacity(0.6), radius: 16, y: 6)
    }

    func kairoGlass() -> some View {
        self.glassEffect(.regular.interactive())
    }
}

// ═══════════════════════════════════════════
// MARK: - ANIMATED TEXT (fades + slides on appear/change)
// ═══════════════════════════════════════════

struct KairoText: View {
    let text: String
    let font: Font
    let color: Color
    var delay: Double = 0

    @State private var appeared = false
    @State private var trackedText = ""

    var body: some View {
        Text(text)
            .font(font).foregroundColor(color)
            .opacity(appeared ? 1 : 0)
            .blur(radius: appeared ? 0 : 4)
            .offset(y: appeared ? 0 : 6)
            .onAppear {
                trackedText = text
                withAnimation(.kairoSpring.delay(delay)) { appeared = true }
            }
            .onChange(of: text) { newVal in
                if newVal != trackedText {
                    trackedText = newVal
                    appeared = false
                    withAnimation(.kairoFast.delay(delay)) { appeared = true }
                }
            }
    }
}

// ═══════════════════════════════════════════
// MARK: - KAIRO AVATAR (glowing K orb)
// ═══════════════════════════════════════════

struct KairoAvatar: View {
    var size: CGFloat = 24
    @State private var glowPhase = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(K.cyan.opacity(glowPhase ? 0.6 : 0.2), lineWidth: 1)
                .frame(width: size + 6, height: size + 6)
                .scaleEffect(glowPhase ? 1.1 : 1.0)
            Circle()
                .fill(K.gradient)
                .frame(width: size, height: size)
                .shadow(color: K.cyan.opacity(glowPhase ? 0.6 : 0.3), radius: glowPhase ? 8 : 4)
            Text("K")
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) { glowPhase = true }
        }
    }
}

// ═══════════════════════════════════════════
// MARK: - LIQUID WAVEFORM (sine-wave driven)
// ═══════════════════════════════════════════

struct KairoWaveform: View {
    let color: Color
    let barCount: Int
    let maxHeight: CGFloat
    let isPlaying: Bool

    @State private var heights: [CGFloat] = []
    @State private var phase: Double = 0

    let timer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .bottom, spacing: 2.5) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(LinearGradient(colors: [color, color.opacity(0.4)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 2.5, height: i < heights.count ? heights[i] : 3)
                    .animation(.easeInOut(duration: 0.08), value: heights)
            }
        }
        .frame(height: maxHeight)
        .onAppear { heights = Array(repeating: 3, count: barCount) }
        .onReceive(timer) { _ in
            if isPlaying {
                phase += 0.25
                heights = (0..<barCount).map { i in
                    let s = sin(phase + Double(i) * 0.4)
                    let n = CGFloat.random(in: 0.7...1.0)
                    return max(3, CGFloat((s + 1) / 2) * maxHeight * n)
                }
            } else if heights.contains(where: { $0 > 4 }) {
                withAnimation(.kairoSlow) { heights = Array(repeating: 3, count: barCount) }
            }
        }
    }
}

// ═══════════════════════════════════════════
// MARK: - PREMIUM TOGGLE
// ═══════════════════════════════════════════

struct KairoToggleStyle: ToggleStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        ZStack(alignment: configuration.isOn ? .trailing : .leading) {
            Capsule()
                .fill(configuration.isOn ?
                    AnyShapeStyle(LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .leading, endPoint: .trailing)) :
                    AnyShapeStyle(Color.white.opacity(0.08)))
                .frame(width: 38, height: 22)
                .shadow(color: color.opacity(configuration.isOn ? 0.4 : 0), radius: 6)
            Circle().fill(.white).frame(width: 18, height: 18)
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2).padding(2)
        }
        .animation(.kairoFast, value: configuration.isOn)
        .onTapGesture {
            configuration.isOn.toggle()
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        }
    }
}

// ═══════════════════════════════════════════
// MARK: - TAB BAR with matchedGeometryEffect
// ═══════════════════════════════════════════

enum KairoTab: String, CaseIterable {
    case nowPlaying = "Now Playing"
    case commands   = "Commands"
    case devices    = "Devices"
    case chat       = "Chat"
    case notifs     = "Notifs"

    var icon: String {
        switch self {
        case .nowPlaying: return "waveform"
        case .commands:   return "command"
        case .devices:    return "house.fill"
        case .chat:       return "bubble.left.fill"
        case .notifs:     return "bell.fill"
        }
    }
}

struct KairoTabBar: View {
    @Binding var selected: KairoTab
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(KairoTab.allCases, id: \.self) { tab in
                let isSelected = selected == tab
                Button(action: {
                    withAnimation(.kairoFast) { selected = tab }
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(isSelected ? .white : .kTextTertiary)
                        if isSelected {
                            Text(tab.rawValue)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        }
                    }
                    .padding(.horizontal, isSelected ? 12 : 10)
                    .padding(.vertical, 7)
                    .background(
                        ZStack {
                            if isSelected {
                                Capsule().fill(.white.opacity(0.14))
                                    .matchedGeometryEffect(id: "TAB_BG", in: ns)
                                Capsule().stroke(.white.opacity(0.12), lineWidth: 1)
                                    .matchedGeometryEffect(id: "TAB_BORDER", in: ns)
                            }
                        }
                    )
                }.buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Capsule().fill(.white.opacity(0.04))
                .overlay(Capsule().stroke(.white.opacity(0.06), lineWidth: 0.5))
        )
    }
}

// ═══════════════════════════════════════════
// MARK: - MODELS
// ═══════════════════════════════════════════

struct KairoQuickAction: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let color: Color
    let handler: () -> Void
}

// ═══════════════════════════════════════════
// MARK: - AMBIENT WAKE TIMER
// ═══════════════════════════════════════════

class KairoAmbientTimer: ObservableObject {
    static let shared = KairoAmbientTimer()
    @Published var isShowingAmbient = false
    @Published var ambientProgress: Double = 0

    private var idleTimer: Timer?
    private var progressTimer: Timer?

    func startIdleWatch() { resetIdleTimer() }

    func resetIdleTimer() {
        idleTimer?.invalidate()
        if isShowingAmbient { dismissAmbient() }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.triggerAmbientShow() }
        }
    }

    func triggerAmbientShow() {
        guard MusicManager.shared.isPlaying else { resetIdleTimer(); return }
        withAnimation(.kairoSpring) { isShowingAmbient = true; ambientProgress = 0 }
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.ambientProgress += (0.1 / 30.0)
                if self.ambientProgress >= 1.0 { self.dismissAmbient() }
            }
        }
    }

    func dismissAmbient() {
        progressTimer?.invalidate()
        withAnimation(.kairoSlow) { isShowingAmbient = false; ambientProgress = 0 }
        resetIdleTimer()
    }

    func userDidInteract() { resetIdleTimer() }
}

// ═══════════════════════════════════════════
// MARK: - AMBIENT NOW PLAYING VIEW
// ═══════════════════════════════════════════

struct AmbientNowPlayingView: View {
    @ObservedObject var music = MusicManager.shared
    @ObservedObject var ambient = KairoAmbientTimer.shared
    let appColor: Color

    @State private var contentAppeared = false
    @State private var artScale: CGFloat = 0.7
    @State private var artBlur: CGFloat = 20

    var body: some View {
        ZStack {
            if contentAppeared {
                Circle()
                    .fill(RadialGradient(colors: [appColor.opacity(0.25), appColor.opacity(0.08), .clear], center: .center, startRadius: 0, endRadius: 200))
                    .frame(width: 400, height: 400).blur(radius: 40).transition(.opacity)
            }
            VStack(spacing: 0) {
                ZStack {
                    Image(nsImage: music.albumArt).resizable().scaledToFill()
                        .frame(width: 120, height: 120).clipShape(RoundedRectangle(cornerRadius: 20))
                        .blur(radius: 30).opacity(0.4).scaleEffect(1.3)
                    Image(nsImage: music.albumArt).resizable().scaledToFill()
                        .frame(width: 120, height: 120).clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.15), lineWidth: 1))
                        .shadow(color: appColor.opacity(0.5), radius: 24, y: 12)
                }
                .scaleEffect(artScale).blur(radius: artBlur).padding(.bottom, 16)

                KairoText(text: music.songTitle, font: .system(size: 18, weight: .bold, design: .rounded), color: .white, delay: 0.2)
                    .multilineTextAlignment(.center)
                KairoText(text: music.artistName, font: .system(size: 12), color: .secondary, delay: 0.3)
                    .padding(.bottom, 4)

                HStack(spacing: 5) {
                    Circle().fill(appColor).frame(width: 5, height: 5)
                    Text(platformName.uppercased()).font(.system(size: 8, design: .monospaced)).foregroundColor(appColor).tracking(2)
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(appColor.opacity(0.1)).overlay(Capsule().stroke(appColor.opacity(0.25), lineWidth: 1)))
                .opacity(contentAppeared ? 1 : 0).padding(.top, 4)

                KairoWaveform(color: appColor, barCount: 28, maxHeight: 28, isPlaying: music.isPlaying)
                    .frame(height: 32).opacity(contentAppeared ? 1 : 0).padding(.top, 12)

                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08)).frame(height: 2)
                    Capsule().fill(appColor.opacity(0.5)).frame(width: CGFloat(1.0 - ambient.ambientProgress) * 200, height: 2)
                }.frame(width: 200).padding(.top, 14).opacity(contentAppeared ? 0.6 : 0)
            }
            .padding(24)
            .background(RoundedRectangle(cornerRadius: 28).glassEffect(.regular))
            .shadow(color: appColor.opacity(0.2), radius: 40, y: 20)
            .scaleEffect(contentAppeared ? 1 : 0.85, anchor: .top)
            .opacity(contentAppeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.72)) { artScale = 1; artBlur = 0; contentAppeared = true }
        }
        .onTapGesture { ambient.dismissAmbient() }
    }

    private var platformName: String {
        let bid = music.bundleIdentifier ?? ""
        if bid.contains("spotify") { return "Spotify" }
        if bid.contains("Music") { return "Apple Music" }
        return "Music"
    }
}

// ═══════════════════════════════════════════
// MARK: - DOMINANT COLOR EXTRACTION
// ═══════════════════════════════════════════

extension NSImage {
    func dominantColor() -> Color {
        guard let tiffData = self.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return K.cyan }
        let w = bitmap.pixelsWide, h = bitmap.pixelsHigh
        guard w > 0, h > 0 else { return K.cyan }
        var rT: CGFloat = 0, gT: CGFloat = 0, bT: CGFloat = 0, count: CGFloat = 0
        let step = max(w / 5, 1)
        for x in stride(from: 0, to: w, by: step) {
            for y in stride(from: 0, to: h, by: step) {
                if let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) {
                    rT += c.redComponent; gT += c.greenComponent; bT += c.blueComponent; count += 1
                }
            }
        }
        guard count > 0 else { return K.cyan }
        return Color(red: Double(rT / count), green: Double(gT / count), blue: Double(bT / count))
    }
}
