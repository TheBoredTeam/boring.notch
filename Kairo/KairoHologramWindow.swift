import SwiftUI
import AppKit

// MARK: - Hologram Window

class KairoHologramWindow {
    static let shared = KairoHologramWindow()

    private(set) var panel: NSPanel?

    func show() {
        if panel == nil {
            createWindow()
        }
        panel?.orderFrontRegardless()
        KairoOrbAnimator.shared.start()
    }

    func dismiss() {
        KairoOrbAnimator.shared.stop()
        panel?.orderOut(nil)
    }

    private func createWindow() {
        let rect = NSRect(x: 0, y: 0, width: 500, height: 500)
        let panel = NSPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isMovableByWindowBackground = false
        panel.isMovable = true
        panel.level = .statusBar
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false

        let hostView = OrbHostingView(rootView: HologramOrbWindowContent())
        hostView.frame = rect
        panel.contentView = hostView

        if let screen = NSScreen.main {
            let sf = screen.visibleFrame
            let x = sf.midX - 250
            let y = sf.minY
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        self.panel = panel
    }
}

// MARK: - Autonomous Orb Animator

class KairoOrbAnimator: ObservableObject {
    static let shared = KairoOrbAnimator()

    @Published var isPaused = false

    private var displayLink: CVDisplayLink?
    private var velocity: CGPoint = .zero
    private var pauseStartTime: Date?
    private let pauseDuration: TimeInterval = 30
    private var isRunning = false
    private var startTime: Double = 0

    // Layered wave frequencies — each layer creates a different organic motion
    // Ultra-slow breathing waves — like something alive, drifting, searching
    private var wave1 = WaveLayer(freqX: 0.012, freqY: 0.009, ampX: 0.35, ampY: 0.30, phase: 0)
    private var wave2 = WaveLayer(freqX: 0.007, freqY: 0.011, ampX: 0.25, ampY: 0.22, phase: 1.8)
    private var wave3 = WaveLayer(freqX: 0.018, freqY: 0.005, ampX: 0.10, ampY: 0.12, phase: 3.6)
    private var wave4 = WaveLayer(freqX: 0.003, freqY: 0.004, ampX: 0.40, ampY: 0.35, phase: 5.1)
    private var microWave = WaveLayer(freqX: 0.035, freqY: 0.028, ampX: 0.015, ampY: 0.012, phase: 0.7)

    struct WaveLayer {
        var freqX: Double
        var freqY: Double
        var ampX: Double
        var ampY: Double
        var phase: Double
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        startTime = Date().timeIntervalSinceReferenceDate

        var dl: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&dl)
        guard let link = dl else { return }

        CVDisplayLinkSetOutputHandler(link) { [weak self] _, _, _, _, _ in
            self?.tick()
            return kCVReturnSuccess
        }
        CVDisplayLinkStart(link)
        displayLink = link
    }

    func stop() {
        guard let link = displayLink else { return }
        CVDisplayLinkStop(link)
        displayLink = nil
        isRunning = false
    }

    func userDragged() {
        pauseStartTime = Date()
        DispatchQueue.main.async { self.isPaused = true }
    }

    private func tick() {
        guard let panel = KairoHologramWindow.shared.panel,
              let screen = NSScreen.main else { return }

        let mouseLocation = NSEvent.mouseLocation
        let windowCenter = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        let dx = mouseLocation.x - windowCenter.x
        let dy = mouseLocation.y - windowCenter.y
        let mouseDistance = sqrt(dx * dx + dy * dy)

        // Mouse proximity pause
        if mouseDistance < 80 && pauseStartTime == nil {
            pauseStartTime = Date()
            DispatchQueue.main.async { self.isPaused = true }
        }

        // Check pause state
        if let start = pauseStartTime {
            if Date().timeIntervalSince(start) > pauseDuration && mouseDistance > 120 {
                pauseStartTime = nil
                DispatchQueue.main.async { self.isPaused = false }
            }
            return
        }

        let sf = screen.visibleFrame
        let t = Date().timeIntervalSinceReferenceDate - startTime

        // Layered sinusoidal waves — like liquid mercury floating in zero gravity
        // Each wave layer operates at different frequencies creating organic Lissajous-like paths
        let nx = sampleWaveX(wave1, t) + sampleWaveX(wave2, t) + sampleWaveX(wave3, t)
                + sampleWaveX(wave4, t) + sampleWaveX(microWave, t)
        let ny = sampleWaveY(wave1, t) + sampleWaveY(wave2, t) + sampleWaveY(wave3, t)
                + sampleWaveY(wave4, t) + sampleWaveY(microWave, t)

        // Normalize to 0...1 range (sum of amplitudes gives max extent)
        let totalAmpX = wave1.ampX + wave2.ampX + wave3.ampX + wave4.ampX + microWave.ampX
        let totalAmpY = wave1.ampY + wave2.ampY + wave3.ampY + wave4.ampY + microWave.ampY
        let normX = (nx / totalAmpX + 1.0) / 2.0  // 0...1
        let normY = (ny / totalAmpY + 1.0) / 2.0

        // Map to screen with generous padding so the orb reaches edges
        let padding: CGFloat = 60
        let targetX = sf.minX + padding + CGFloat(normX) * (sf.width - padding * 2) - 250
        let targetY = sf.minY + padding + CGFloat(normY) * (sf.height - padding * 2) - 250

        // Very heavy, syrupy blending — barely moving, like it's breathing
        let smoothing: CGFloat = 0.003
        velocity.x += (targetX - panel.frame.origin.x) * smoothing
        velocity.y += (targetY - panel.frame.origin.y) * smoothing
        velocity.x *= 0.97
        velocity.y *= 0.97

        let newX = panel.frame.origin.x + velocity.x
        let newY = panel.frame.origin.y + velocity.y

        DispatchQueue.main.async {
            panel.setFrameOrigin(NSPoint(x: newX, y: newY))
        }
    }

    private func sampleWaveX(_ w: WaveLayer, _ t: Double) -> Double {
        w.ampX * sin(t * w.freqX * 2 * .pi + w.phase)
    }

    private func sampleWaveY(_ w: WaveLayer, _ t: Double) -> Double {
        w.ampY * sin(t * w.freqY * 2 * .pi + w.phase + .pi / 3)
    }
}

// MARK: - Hit-testing host view

class OrbHostingView<Content: View>: NSHostingView<Content> {
    private let orbRadius: CGFloat = 50
    private var mouseDownLocation: NSPoint?
    private var isDragging = false
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
            owner: self, userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let dx = point.x - center.x
        let dy = point.y - center.y
        if dx * dx + dy * dy <= orbRadius * orbRadius {
            return super.hitTest(point)
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
        isDragging = false
        KairoOrbAnimator.shared.userDragged()

        if event.clickCount == 2 {
            NotificationCenter.default.post(name: .orbDoubleClick, object: nil)
            return
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownLocation else { return }
        let current = event.locationInWindow
        let dx = current.x - start.x
        let dy = current.y - start.y
        if !isDragging && (dx * dx + dy * dy) > 16 {
            isDragging = true
        }
        if isDragging {
            KairoOrbAnimator.shared.userDragged()
            window?.performDrag(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if !isDragging && event.clickCount == 1 {
            NotificationCenter.default.post(name: .orbSingleClick, object: nil)
        }
        mouseDownLocation = nil
        isDragging = false
    }

    override func rightMouseDown(with event: NSEvent) {
        KairoOrbAnimator.shared.userDragged()
        NotificationCenter.default.post(name: .orbRightClick, object: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        if abs(delta) > 0.5 {
            NotificationCenter.default.post(name: .orbScroll, object: NSNumber(value: delta))
        }
    }
}

// MARK: - Orb interaction notifications

extension NSNotification.Name {
    static let orbSingleClick = NSNotification.Name("kairoOrbSingleClick")
    static let orbDoubleClick = NSNotification.Name("kairoOrbDoubleClick")
    static let orbRightClick  = NSNotification.Name("kairoOrbRightClick")
    static let orbScroll      = NSNotification.Name("kairoOrbScroll")
}

// MARK: - Orb Interaction Controller

class KairoOrbController: ObservableObject {
    static let shared = KairoOrbController()

    @Published var isHovered = false
    @Published var showingQuickActions = false
    @Published var volumeIndicator: CGFloat? = nil

    private var volumeHideTask: DispatchWorkItem?

    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleSingleClick), name: .orbSingleClick, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDoubleClick), name: .orbDoubleClick, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRightClick(_:)), name: .orbRightClick, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleScroll(_:)), name: .orbScroll, object: nil)
    }

    @objc private func handleSingleClick() {
        let engine = KairoVoiceEngine.shared
        if engine.isListening {
            engine.stopListening()
        } else {
            engine.startListening()
            NotificationCenter.default.post(name: .kairoVoiceActivated, object: nil)
        }
    }

    @objc private func handleDoubleClick() {
        Task { await MusicManager.shared.playPause() }
    }

    @objc private func handleRightClick(_ notification: Notification) {
        guard let event = notification.object as? NSEvent,
              let window = KairoHologramWindow.shared.panel else { return }

        let menu = NSMenu()
        menu.addItem(withTitle: "Talk to Kairo", action: #selector(menuVoice), keyEquivalent: "").target = self
        menu.addItem(.separator())

        let musicItem = NSMenuItem(title: "Now Playing", action: nil, keyEquivalent: "")
        let musicSub = NSMenu()
        musicSub.addItem(withTitle: "Play / Pause", action: #selector(menuPlayPause), keyEquivalent: "").target = self
        musicSub.addItem(withTitle: "Next Track", action: #selector(menuNextTrack), keyEquivalent: "").target = self
        musicSub.addItem(withTitle: "Previous Track", action: #selector(menuPrevTrack), keyEquivalent: "").target = self
        musicItem.submenu = musicSub
        menu.addItem(musicItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Weather", action: #selector(menuWeather), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Calendar", action: #selector(menuCalendar), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Screenshot", action: #selector(menuScreenshot), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Lock Screen", action: #selector(menuLockScreen), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings", action: #selector(menuSettings), keyEquivalent: "").target = self

        let location = window.contentView?.convert(event.locationInWindow, from: nil) ?? .zero
        menu.popUp(positioning: nil, at: location, in: window.contentView)
    }

    @objc private func handleScroll(_ notification: Notification) {
        guard let delta = (notification.object as? NSNumber)?.doubleValue else { return }
        DispatchQueue.main.async {
            if delta > 0 {
                VolumeManager.shared.increase()
            } else {
                VolumeManager.shared.decrease()
            }
        }
    }

    // MARK: - Menu Actions

    @objc private func menuVoice() { handleSingleClick() }
    @objc private func menuPlayPause() { Task { await MusicManager.shared.playPause() } }
    @objc private func menuNextTrack() { Task { await MusicManager.shared.nextTrack() } }
    @objc private func menuPrevTrack() { Task { await MusicManager.shared.previousTrack() } }

    @objc private func menuWeather() {
        Task {
            await KairoWeatherService.shared.fetch()
            let w = KairoWeatherService.shared
            let text = "\(w.condition), \(w.temp)°"
            await MainActor.run {
                KairoFeedbackEngine.shared.say(text, pillText: "Weather", speak: true)
            }
        }
    }

    @objc private func menuCalendar() {
        Task { @MainActor in
            let count = CalendarManager.shared.events.count
            let text = count == 0 ? "No events today." : "\(count) events on your calendar today."
            KairoFeedbackEngine.shared.say(text, pillText: "Calendar", speak: true)
        }
    }

    @objc private func menuScreenshot() {
        let task = Process()
        task.launchPath = "/usr/bin/screencapture"
        task.arguments = ["-i"]
        task.launch()
    }

    @objc private func menuLockScreen() {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 0x0C, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 0x0C, keyDown: false)
        down?.flags = [.maskCommand, .maskControl]
        up?.flags = [.maskCommand, .maskControl]
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    @objc private func menuSettings() {
        DispatchQueue.main.async {
            SettingsWindowController.shared.showWindow()
        }
    }
}

// MARK: - Window Content View

struct HologramOrbWindowContent: View {
    @ObservedObject private var feedback = KairoFeedbackEngine.shared
    @ObservedObject private var hologram = KairoHologramManager.shared
    @ObservedObject private var voice = KairoVoiceEngine.shared
    @ObservedObject private var music = MusicManager.shared
    @ObservedObject private var notifications = KairoNotificationEngine.shared
    @ObservedObject private var controller = KairoOrbController.shared
    @ObservedObject private var animator = KairoOrbAnimator.shared

    private var activeMode: HologramMode {
        if voice.isListening { return .listening }
        if hologram.isShowingDisplay { return .displaying }
        if feedback.isSpeaking { return .speaking }
        return .idle
    }

    var body: some View {
        ZStack {
            KairoHologramOrb(size: 90, mode: activeMode)
                .scaleEffect(animator.isPaused ? 1.0 : 0.95)
                .animation(.easeInOut(duration: 2.0), value: animator.isPaused)

            // Notification badge — sits at the upper-right of the orb
            if notifications.unreadCount > 0 {
                Text("\(notifications.unreadCount)")
                    .font(Kairo.Typography.captionStrong)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, Kairo.Space.xs + 1)
                    .padding(.vertical, Kairo.Space.xxs)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Kairo.Palette.danger)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5)
                    )
                    .shadow(color: Kairo.Palette.danger.opacity(0.6), radius: 6, x: 0, y: 0)
                    .offset(x: 32, y: -32)
                    .transition(.scale.combined(with: .opacity))
            }

            // Mic indicator when listening
            if voice.isListening {
                micWaveform
                    .offset(y: 55)
                    .transition(.opacity)
            }

            // Now-playing indicator
            if music.isPlaying && !voice.isListening {
                nowPlayingBadge
                    .offset(y: 55)
                    .transition(.opacity)
            }
        }
        .frame(width: 500, height: 500)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: voice.isListening)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: notifications.unreadCount)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: music.isPlaying)
    }

    private var micWaveform: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                MicBar(index: i, level: voice.currentMicLevel)
            }
        }
    }

    private var nowPlayingBadge: some View {
        HStack(spacing: Kairo.Space.xs) {
            ForEach(0..<3, id: \.self) { i in
                MusicBar(index: i)
            }
            if !music.songTitle.isEmpty {
                Text(music.songTitle)
                    .font(Kairo.Typography.caption)
                    .foregroundStyle(Color.white.opacity(0.78))
                    .lineLimit(1)
                    .frame(maxWidth: 80)
            }
        }
        .padding(.horizontal, Kairo.Space.sm)
        .padding(.vertical, Kairo.Space.xs)
        .background {
            Capsule(style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    Capsule(style: .continuous).fill(Color.black.opacity(0.35))
                }
                .overlay {
                    Capsule(style: .continuous).fill(Kairo.Palette.glassTint)
                }
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        }
    }
}

// MARK: - Mic Level Bars

struct MicBar: View {
    let index: Int
    let level: Float

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let h = max(4, CGFloat(level + 50) * 0.4 + sin(t * 6 + Double(index) * 1.2) * 3)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(LinearGradient(colors: [.cyan, .purple], startPoint: .bottom, endPoint: .top))
                .frame(width: 3, height: h)
        }
    }
}

// MARK: - Music Equalizer Bars

struct MusicBar: View {
    let index: Int

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let h = 4 + sin(t * 3.5 + Double(index) * 2.1) * 3 + 3
            RoundedRectangle(cornerRadius: 1)
                .fill(.cyan.opacity(0.8))
                .frame(width: 2, height: h)
        }
    }
}
