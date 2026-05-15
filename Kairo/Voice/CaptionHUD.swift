//
//  CaptionHUD.swift
//  Kairo — guaranteed-visible speech caption window
//
//  Sits below the notch, always on top, full screen width. Shows what
//  Kairo is currently saying (typewriter-revealed) so the user *always*
//  has visual confirmation that the assistant is speaking — independent
//  of whether the Orbie panel reached on-screen or not.
//
//  Lifecycle is driven by `KairoCaptionHUD.shared.show(text:duration:)`
//  / `.hide()`. PresenceCoordinator calls these around beginSpeaking /
//  endSpeaking.
//

import AppKit
import SwiftUI
import Combine

// MARK: - Window controller (singleton)

@MainActor
final class KairoCaptionHUD {
    static let shared = KairoCaptionHUD()

    private var window: NSPanel?
    private let state = CaptionState()
    private var fadeTask: Task<Void, Never>?

    private init() {}

    /// Show a caption. Text reveals character-by-character. Auto-hides after
    /// `duration` (defaults to a length-based estimate).
    func show(text: String, query: String? = nil, duration: TimeInterval? = nil) {
        ensureWindow()
        fadeTask?.cancel()

        let estimated = duration ?? Self.estimatedDuration(for: text)
        state.startReveal(text: text, query: query, totalDuration: estimated)

        guard let panel = window else { return }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        // Auto-hide after the reveal completes + a brief read-time
        let dwell: TimeInterval = 1.5
        fadeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(estimated + dwell))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.hide() }
        }
    }

    /// Update amplitude (0...1) — drives the side pulse bars on the caption.
    func updateAmplitude(_ amp: Float) {
        state.amplitude = Double(amp)
    }

    func hide() {
        fadeTask?.cancel()
        fadeTask = nil
        guard let panel = window else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.window?.orderOut(nil)
                self.state.reset()
            }
        })
    }

    // MARK: - Window setup

    private func ensureWindow() {
        if window != nil { return }

        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        // Sit just under the notch — wide bar, ~120pt tall.
        let width: CGFloat = min(880, visible.width - 80)
        let height: CGFloat = 130
        let x = visible.midX - width / 2
        let y = visible.maxY - height - 24

        let panel = NSPanel(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar          // above the notch, above other apps
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = true   // never steals clicks
        panel.alphaValue = 0

        let host = NSHostingView(rootView: CaptionHUDView(state: state))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        panel.contentView = host
        window = panel
    }

    // MARK: - Heuristic

    private static func estimatedDuration(for text: String) -> TimeInterval {
        // ~5 chars per word, ~155 wpm normal speech → ~12.4 chars/sec.
        // Bump the floor so single-sentence replies have time to be read.
        let chars = max(20, text.count)
        return max(2.5, Double(chars) / 12.0)
    }
}

// MARK: - State

@MainActor
final class CaptionState: ObservableObject {
    @Published var query: String? = nil
    @Published var revealed: String = ""
    @Published var fullText: String = ""
    @Published var isActive: Bool = false
    @Published var amplitude: Double = 0

    private var revealTimer: Timer?

    func startReveal(text: String, query: String?, totalDuration: TimeInterval) {
        revealTimer?.invalidate()
        self.query = query
        self.fullText = text
        self.revealed = ""
        self.isActive = true

        let chars = max(1, text.count)
        let interval = max(0.01, min(0.06, totalDuration / Double(chars)))
        var index = 0

        revealTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            Task { @MainActor in
                if index < self.fullText.count {
                    let upTo = self.fullText.index(self.fullText.startIndex, offsetBy: index + 1)
                    self.revealed = String(self.fullText[..<upTo])
                    index += 1
                } else {
                    timer.invalidate()
                }
            }
        }
    }

    func reset() {
        revealTimer?.invalidate()
        revealTimer = nil
        query = nil
        revealed = ""
        fullText = ""
        isActive = false
        amplitude = 0
    }
}

// MARK: - View

struct CaptionHUDView: View {
    @ObservedObject var state: CaptionState

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        return ZStack {
            // Background: dark glass + scan lines + animated cyan rim
            shape
                .fill(Color.black.opacity(0.70))
                .overlay(shape.fill(.ultraThinMaterial))
            HUDScanLines(spacing: 3, opacity: 0.03, sweepOpacity: 0.06, sweepPeriod: 3.5)
                .clipShape(shape)
                .padding(2)

            // Content
            HStack(alignment: .center, spacing: Kairo.Space.lg) {
                pulseBars(leading: true)
                VStack(alignment: .leading, spacing: Kairo.Space.xs) {
                    header
                    Text(state.revealed)
                        .font(.system(size: 22, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.white)
                        .shadow(color: HUDPalette.primary.opacity(0.5), radius: 6, x: 0, y: 0)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .animation(.none, value: state.revealed)
                }
                pulseBars(leading: false)
            }
            .padding(.horizontal, Kairo.Space.xl)
            .padding(.vertical, Kairo.Space.lg)
        }
        .overlay {
            // Animated cyan rim
            Color.clear.modifier(HUDRimGlow(color: HUDPalette.primary, thickness: 1.2, radius: 22, period: 4.0))
        }
        .overlay {
            HUDBrackets(color: HUDPalette.primary, thickness: 1, length: 16, inset: 6)
        }
        .shadow(color: HUDPalette.primary.opacity(0.35), radius: 20, x: 0, y: 0)
        .shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 8)
    }

    // MARK: - Header line

    private var header: some View {
        HStack(spacing: Kairo.Space.sm) {
            Text("◆ KAIRO")
                .font(Kairo.Typography.captionStrong.monospaced())
                .tracking(2)
                .foregroundStyle(HUDPalette.primary.opacity(0.9))
            if let q = state.query, !q.isEmpty {
                Text("·").foregroundStyle(HUDPalette.primary.opacity(0.4))
                Text(q.uppercased())
                    .font(Kairo.Typography.monoSmall)
                    .tracking(1)
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer()
            Text(timeStamp)
                .font(Kairo.Typography.monoSmall)
                .foregroundStyle(HUDPalette.primary.opacity(0.45))
        }
    }

    private var timeStamp: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        return "T+" + f.string(from: Date()).suffix(8)
    }

    // MARK: - Pulse bars (one bar set on each side)

    private func pulseBars(leading: Bool) -> some View {
        // 4 small vertical bars whose height responds to amplitude — purely
        // decorative but communicates "active speech" at a glance.
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<4, id: \.self) { i in
                let phase = Double(i) * 0.32
                let h = barHeight(forPhase: phase)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(HUDPalette.primary)
                    .frame(width: 3, height: h)
                    .shadow(color: HUDPalette.primary.opacity(0.5), radius: 4)
            }
        }
        .frame(width: 32, height: 44)
        .rotationEffect(.degrees(leading ? 0 : 180))
        .animation(.linear(duration: 0.05), value: state.amplitude)
    }

    private func barHeight(forPhase phase: Double) -> CGFloat {
        guard state.isActive else { return 4 }
        let base: Double = 6 + 32 * state.amplitude
        // Phase-jittered so the 4 bars don't all match
        let v = base + sin(Date().timeIntervalSinceReferenceDate * 12 + phase * 3) * 6
        return CGFloat(max(4, min(40, v)))
    }
}
