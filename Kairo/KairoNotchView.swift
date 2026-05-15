//
//  KairoNotchView.swift
//  Kairo — Premium animated AI layer
//  Every element breathes. Every text slides. Every button springs.
//

import SwiftUI

struct KairoNotchView: View {
    @EnvironmentObject var vm: KairoViewModel
    @ObservedObject var music = MusicManager.shared
    @ObservedObject var socket = KairoSocket.shared
    @ObservedObject var ambient = KairoAmbientTimer.shared
    @ObservedObject var notifEngine = KairoNotificationEngine.shared
    @State private var activeTab: KairoTab = .nowPlaying
    @State private var kairoInput = ""
    @State private var kairoResponse = ""
    @State private var showResponse = false
    @State private var isProcessing = false
    @State private var dominantColor: Color = K.cyan
    @State private var chatMessages: [(role: String, text: String)] = [("k", "KAIRO online. All systems ready.")]
    @State private var isTyping = false
    @State private var isFocused = false
    @State private var windowAppeared = false
    @State private var breathPhase = false
    @State private var innerGlow = false
    // Voice mode
    @ObservedObject var voice = KairoVoiceEngine.shared
    @State private var voiceActive = false
    @State private var voiceWaveHeights: [CGFloat] = Array(repeating: 3, count: 40)
    // Health check
    @State private var serverOnline = false
    // Feedback pill
    @ObservedObject var feedback = KairoFeedbackEngine.shared
    @State private var feedbackVisible = false
    // Morning briefing
    @ObservedObject var briefing = KairoMorningBriefing.shared
    // Hologram
    @ObservedObject var hologram = KairoHologramManager.shared

    private var currentHologramMode: HologramMode {
        if hologram.isShowingDisplay { return .displaying }
        if feedback.isSpeaking { return .speaking }
        return .idle
    }

    // Dynamic height per tab
    private func heightForTab(_ tab: KairoTab) -> CGFloat {
        let orbHeight: CGFloat = 85
        switch tab {
        case .nowPlaying:
            if music.isPlaying || !music.isPlayerIdle { return 620 + orbHeight }
            return 720 + orbHeight
        case .commands:  return 900 + orbHeight
        case .devices:   return 700 + orbHeight
        case .chat:      return 700 + orbHeight
        case .notifs:
            let count = notifEngine.history.count
            let base: CGFloat = 520
            let perNotif: CGFloat = 70
            return max(base, base + CGFloat(count) * perNotif) + orbHeight
        }
    }

    var body: some View {
        ZStack(alignment: .top) {

        // Voice mode overlay — takes over the entire view
        if voiceActive {
            voiceModeView
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.9, anchor: .top).combined(with: .opacity),
                    removal: .scale(scale: 0.95, anchor: .top).combined(with: .opacity)
                ))
                .zIndex(10)
        }

        VStack(spacing: 0) {
            KairoTabBar(selected: $activeTab)
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 6)

            Group {
                switch activeTab {
                case .nowPlaying: nowPlayingSection
                case .commands:   commandsSection
                case .devices:    devicesSection
                case .chat:       chatSection
                case .notifs:     notifsSection
                }
            }
            .padding(.bottom, 4)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)).combined(with: .offset(y: 6)),
                removal: .opacity.combined(with: .scale(scale: 1.01, anchor: .top))
            ))
            .animation(.kairoSpring, value: activeTab)

            // Hologram display — expands to show CCTV, images, text
            if hologram.isShowingDisplay {
                KairoHologramDisplay(manager: hologram)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
                    .transition(.scale(scale: 0.6, anchor: .top).combined(with: .opacity))
            }

            inputBar.padding(.horizontal, 14).padding(.bottom, 10).padding(.top, 6)
        }
        .background(
            RadialGradient(colors: [dominantColor.opacity(0.12), .clear], center: .topLeading, startRadius: 0, endRadius: 250)
        )
        .scaleEffect(windowAppeared ? 1 : 0.92, anchor: .top)
        .opacity(windowAppeared ? 1 : 0)
        .blur(radius: windowAppeared ? 0 : 6)
        .onAppear {
            withAnimation(.kairoSpring.delay(0.05)) { windowAppeared = true }
            ambient.startIdleWatch()
            withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) { breathPhase = true }
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true).delay(0.6)) { innerGlow = true }
            socket.checkHealth { ok in serverOnline = ok }
            vm.updateOpenHeight(heightForTab(activeTab))
        }
        // Dynamic resize on tab switch
        .onChange(of: activeTab) {
            vm.updateOpenHeight(heightForTab(activeTab))
            ambient.userDidInteract()
        }
        // Resize when music state changes (idle vs playing changes height)
        .onChange(of: music.isPlaying) {
            if activeTab == .nowPlaying { vm.updateOpenHeight(heightForTab(.nowPlaying)) }
        }
        .onChange(of: music.isPlayerIdle) {
            if activeTab == .nowPlaying { vm.updateOpenHeight(heightForTab(.nowPlaying)) }
        }
        // Voice activated
        .onReceive(NotificationCenter.default.publisher(for: .kairoVoiceActivated)) { _ in
            withAnimation(.kairoSpring) { voiceActive = true }
            ambient.userDidInteract()
        }
        // Voice stopped
        .onReceive(NotificationCenter.default.publisher(for: .kairoVoiceDismissed)) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                if !voice.isSpeaking && !voice.isListening {
                    withAnimation(.kairoSlow) { voiceActive = false }
                }
            }
        }
        .onChange(of: music.albumArt) {
            withAnimation(.easeInOut(duration: 0.8)) { dominantColor = music.albumArt.dominantColor() }
        }
        .onChange(of: kairoInput) { ambient.userDidInteract() }
        .onChange(of: music.songTitle) { ambient.triggerAmbientShow() }

            // AMBIENT OVERLAY
            if ambient.isShowingAmbient && music.isPlaying {
                AmbientNowPlayingView(appColor: appColor)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.85, anchor: .top).combined(with: .opacity),
                        removal: .scale(scale: 0.9, anchor: .top).combined(with: .opacity)
                    ))
            }
        } // Close ZStack
        .animation(.kairoSpring, value: ambient.isShowingAmbient)
    }

    // MARK: - Now Playing (switches between idle, playing, notification)
    private var nowPlayingSection: some View {
        Group {
            // MORNING BRIEFING — highest priority
            if briefing.isBriefingActive {
                briefingView
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9, anchor: .top).combined(with: .opacity),
                        removal: .scale(scale: 0.95, anchor: .top).combined(with: .opacity)
                    ))
            }
            // FEEDBACK PILL — action confirmations
            else if feedbackVisible {
                feedbackPill
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            // ACTIVE NOTIFICATION — highest priority in this tab
            else if let notif = notifEngine.activeNotification {
                notificationInPill(notif)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            } else if music.isPlaying || !music.isPlayerIdle {
                // MUSIC PLAYING — waveform + quick actions
                VStack(spacing: 8) {
                    KairoWaveform(color: appColor, barCount: 28, maxHeight: 24, isPlaying: music.isPlaying)
                        .padding(.horizontal, 16)
                    quickActionsRow.padding(.horizontal, 12)
                    if showResponse { responseView.padding(.horizontal, 12) }
                }
                .padding(.vertical, 4)
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            } else {
                // IDLE — ambient info screen
                nowPlayingIdleView
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
        }
        .animation(.kairoSpring, value: music.isPlaying)
        .animation(.kairoSpring, value: music.isPlayerIdle)
        .animation(.kairoSpring, value: feedbackVisible)
        .animation(.kairoSpring, value: briefing.isBriefingActive)
        .onReceive(NotificationCenter.default.publisher(for: .kairoFeedback)) { notif in
            let text = notif.userInfo?["text"] as? String ?? ""
            let duration = notif.userInfo?["duration"] as? Double ?? 3.0
            guard !text.isEmpty else { return }
            withAnimation(.kairoFast) { feedbackVisible = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                withAnimation(.kairoFast) { feedbackVisible = false }
            }
        }
    }

    // MARK: - Feedback Pill
    private var feedbackPill: some View {
        HStack(spacing: 10) {
            KairoAvatar(size: 18)
            Text(feedback.currentText)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(2)
            Spacer()
            if feedback.isSpeaking {
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle().fill(K.cyan.opacity(0.6)).frame(width: 4, height: 4)
                            .offset(y: feedback.isSpeaking ? -3 : 0)
                            .animation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true).delay(Double(i) * 0.12), value: feedback.isSpeaking)
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial.opacity(0.5))
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [K.cyan.opacity(0.08), K.blue.opacity(0.03), .clear],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(colors: [K.cyan.opacity(0.2), .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 0.5
                    )
            }
        )
        .padding(.horizontal, 14)
    }

    // MARK: - Morning Briefing
    private var briefingView: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                KairoAvatar(size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MORNING BRIEFING")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(K.gold)
                        .tracking(1.5)
                    Text(briefingGreeting)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
                Spacer()
                Button(action: { briefing.dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.kTextTertiary)
                }.buttonStyle(.plain)
            }

            if !briefing.briefingWords.isEmpty {
                HStack(spacing: 0) {
                    FlowLayout(spacing: 4) {
                        ForEach(Array(briefing.briefingWords.enumerated()), id: \.offset) { _, word in
                            Text(word + " ")
                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                .foregroundColor(.kTextSecondary)
                                .transition(.scale(scale: 0.8).combined(with: .opacity))
                        }
                    }
                    Spacer()
                }
            }

            if feedback.isSpeaking {
                KairoWaveform(color: K.gold, barCount: 20, maxHeight: 16, isPlaying: true)
                    .padding(.horizontal, 8)
                    .transition(.opacity)
            }
        }
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial.opacity(0.4))
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [K.gold.opacity(0.06), K.orange.opacity(0.02), .clear],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        LinearGradient(colors: [K.gold.opacity(0.2), .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 0.5
                    )
            }
        )
        .padding(.horizontal, 14)
    }

    private var briefingGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 17 { return "Good afternoon" }
        return "Good evening"
    }

    // MARK: - Idle Ambient Screen
    @ObservedObject private var weather = KairoWeatherService.shared
    @ObservedObject private var home = KairoHomeService.shared
    @State private var currentTime = Date()

    private var currentWeatherType: KairoWeatherType {
        KairoWeatherType.from(condition: weather.condition)
    }

    private var nowPlayingIdleView: some View {
        GeometryReader { geo in
            ZStack {
                // Live weather animation background
                if weather.isLoaded {
                    KairoWeatherAnimationView(
                        weatherType: currentWeatherType,
                        bounds: geo.size
                    )
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 1.5), value: weather.condition)
                }

                VStack(spacing: 0) {
                    // Clock — large, elegant
                    VStack(spacing: 4) {
                        Text(timeString)
                            .font(.system(size: 48, weight: .ultraLight, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(colors: [.white, .white.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                            )
                            .monospacedDigit()
                            .shadow(color: currentWeatherType.accentColor.opacity(breathPhase ? 0.2 : 0), radius: 20)
                        Text(dateString)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.kTextSecondary)
                            .tracking(1.5)
                            .textCase(.uppercase)
                    }
                    .padding(.top, 14)
                    .padding(.bottom, 16)

                    // Info cards — 2x2 grid
                    LazyVGrid(columns: [.init(.flexible(), spacing: 10), .init(.flexible(), spacing: 10)], spacing: 10) {
                        ambientCard(icon: weather.sfSymbol, color: currentWeatherType.accentColor, title: "OUTSIDE",
                            primary: weather.isLoaded ? "\(Int(weather.temp))°" : "--°",
                            secondary: weather.condition.isEmpty ? "Loading..." : weather.condition.capitalized)
                        ambientCard(icon: home.roomTemp != nil ? "thermometer.medium" : "thermometer.variable.and.figure", color: tempColor,
                            title: "ROOM",
                            primary: home.roomTemp != nil ? "\(Int(home.roomTemp!))°" : "--°",
                            secondary: home.humidity != nil ? "\(Int(home.humidity!))% humidity" : "Sensor offline")
                        ambientCard(icon: home.acOn ? "air.conditioner.horizontal.fill" : "snowflake",
                            color: home.acOn ? K.cyan : .kTextTertiary,
                            title: "CLIMATE",
                            primary: home.acOn ? "Cooling" : "Off",
                            secondary: home.acOn ? "Active" : "Tap to start")
                        ambientCard(icon: home.lightsOnCount > 0 ? "lightbulb.fill" : "lightbulb.slash.fill",
                            color: home.lightsOnCount > 0 ? K.gold : .kTextTertiary,
                            title: "LIGHTS",
                            primary: home.lightsOnCount > 0 ? "\(home.lightsOnCount) On" : "All Off",
                            secondary: "")
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)

                    // System status bar
                    HStack(spacing: 14) {
                        statusDot(color: serverOnline ? K.green : K.red, label: serverOnline ? "SERVER" : "OFFLINE")
                        statusDot(color: socket.isConnected ? K.cyan : K.red, label: socket.isConnected ? "WS LIVE" : "WS DOWN")
                        Spacer()
                        Text("KAIRO")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.kTextMuted)
                            .tracking(2)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                }
            }
        }
        .onAppear { Task { await weather.fetch(); await home.fetchStatus() } }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { currentTime = $0 }
    }

    private func statusDot(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
                .shadow(color: color.opacity(0.6), radius: 4)
            Text(label)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(color.opacity(0.7))
                .tracking(1)
        }
    }

    private func ambientCard(icon: String, color: Color, title: String, primary: String, secondary: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .shadow(color: color.opacity(0.4), radius: 5)
                Spacer()
                Text(title)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(color.opacity(0.6))
                    .tracking(1)
            }
            Text(primary)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            if !secondary.isEmpty {
                Text(secondary)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial.opacity(0.5))
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.08), color.opacity(0.02), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        LinearGradient(
                            colors: [color.opacity(0.15), .white.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            }
        )
    }

    private var tempColor: Color {
        guard let t = home.roomTemp else { return .kTextTertiary }
        if t > 28 { return Color(hex: 0xFF3B30) }
        if t > 25 { return Color(hex: 0xFF9F0A) }
        return Color(hex: 0x30D158)
    }

    private var timeString: String { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: currentTime) }
    private var dateString: String { let f = DateFormatter(); f.dateFormat = "EEEE, MMMM d"; return f.string(from: currentTime) }

    // MARK: - Notifications (proposals + camera alerts + app notifs)
    private var notifsSection: some View {
        VStack(spacing: 10) {
            // Pending proposal — highest priority
            if let proposal = socket.pendingProposal {
                proposalCard(proposal)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Camera motion alert
            if let motionData = socket.latestMotionImage {
                cameraAlertCard(imageData: motionData, camera: socket.latestMotionCamera, description: socket.latestMotionDescription)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Regular notification history
            NotificationHistoryTab()
        }
        .padding(.horizontal, 14)
        .animation(.kairoSpring, value: socket.pendingProposal?.id)
        .animation(.kairoSpring, value: socket.latestMotionImage)
    }

    // MARK: - Proposal Card
    private func proposalCard(_ proposal: KairoProposal) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(LinearGradient(colors: [K.orange, K.gold], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 32, height: 32)
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("APPROVAL REQUIRED")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(K.orange)
                        .tracking(1)
                    Text(proposal.trigger)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                Spacer()
            }

            Text(proposal.message)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundColor(.kTextSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if let action = proposal.actionName, !action.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "gearshape.fill").font(.system(size: 9))
                    Text(action)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .foregroundColor(.kTextTertiary)
            }

            HStack(spacing: 10) {
                Button(action: {
                    socket.respondToProposal(id: proposal.id, approved: true)
                    withAnimation(.kairoSpring) { socket.pendingProposal = nil }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                        Text("Approve")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(K.green)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(
                        Capsule().fill(K.green.opacity(0.12))
                            .overlay(Capsule().stroke(K.green.opacity(0.25), lineWidth: 0.5))
                    )
                }.buttonStyle(KairoBounce())

                Button(action: {
                    socket.respondToProposal(id: proposal.id, approved: false)
                    withAnimation(.kairoSpring) { socket.pendingProposal = nil }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                        Text("Reject")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(K.red)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(
                        Capsule().fill(K.red.opacity(0.1))
                            .overlay(Capsule().stroke(K.red.opacity(0.2), lineWidth: 0.5))
                    )
                }.buttonStyle(KairoBounce())

                Spacer()
            }
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial.opacity(0.4))
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(colors: [K.orange.opacity(0.08), K.gold.opacity(0.02), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                RoundedRectangle(cornerRadius: 16)
                    .stroke(LinearGradient(colors: [K.orange.opacity(0.2), .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.5)
            }
        )
    }

    // MARK: - Camera Alert Card
    private func cameraAlertCard(imageData: Data, camera: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(LinearGradient(colors: [K.red, K.orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 32, height: 32)
                    Image(systemName: "video.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("MOTION DETECTED")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(K.red)
                        .tracking(1)
                    Text(camera)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
                Spacer()
                Button(action: { withAnimation(.kairoSpring) { socket.latestMotionImage = nil } }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.kTextTertiary)
                }
                .buttonStyle(.plain)
            }

            // Thumbnail
            if let nsImage = NSImage(data: imageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(K.red.opacity(0.15), lineWidth: 0.5)
                    )
            }

            if !description.isEmpty {
                Text(description)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(.kTextSecondary)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial.opacity(0.4))
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(colors: [K.red.opacity(0.06), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                RoundedRectangle(cornerRadius: 16)
                    .stroke(LinearGradient(colors: [K.red.opacity(0.15), .white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.5)
            }
        )
    }

    // MARK: - Commands (staggered appear, unique colors)
    private var commandsSection: some View {
        LazyVGrid(columns: [.init(.flexible(), spacing: 10), .init(.flexible(), spacing: 10), .init(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(Array(commands.enumerated()), id: \.offset) { i, cmd in
                cmdCard(cmd.icon, cmd.label, cmd.sub, cmd.command, color: cmd.color, index: i)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var commands: [(icon: String, label: String, sub: String, command: String, color: Color)] {
        [
            ("film.stack.fill",        "Cinema",  "Lights + Dolby", "Movie time",               K.violet),
            ("music.note.list",        "Spotify", "Play music",     "Play chill on Spotify",    K.spotify),
            ("music.quarternote.3",    "Music",   "Your library",   "Play on Apple Music",      K.pink),
            ("play.rectangle.fill",    "YouTube", "Watch video",    "Play video on YouTube",    K.red),
            ("moon.stars.fill",        "Night",   "All off",        "Good night",               K.blue),
            ("video.doorbell.fill",    "Camera",  "Live feed",      "Show camera",              K.orange),
            ("lightbulb.2.fill",       "Lights",  "Toggle",         "Toggle lights",            K.gold),
            ("figure.walk.departure",  "Away",    "Away mode",      "I am leaving",             K.green),
            ("calendar",               "Brief",   "Schedule",       "What's on my calendar?",   K.cyan),
        ]
    }

    // MARK: - Devices
    private var devicesSection: some View {
        LazyVGrid(columns: [.init(.flexible(), spacing: 8), .init(.flexible(), spacing: 8)], spacing: 8) {
            devCard("lightbulb.fill", "Hue Lights", "Connected", K.gold, true)
            devCard("hifispeaker.2.fill", "Denon AVR", "Standby", K.blue, true)
            devCard("tv.inset.filled", "Govee Bias", "Synced", K.green, true)
            devCard("snowflake", "AC Unit", "Off", K.cyan, false)
            devCard("video.fill", "Cameras", "Recording", K.red, true)
            devCard("house.fill", "Home Assist", "Online", K.violet, true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Chat
    private var chatSection: some View {
        ScrollViewReader { proxy in
            LazyVStack(spacing: 8) {
                ForEach(Array(chatMessages.enumerated()), id: \.offset) { i, msg in
                    chatBubble(role: msg.role, text: msg.text, index: i).id(i)
                }
                if isTyping { typingDots.id("typing") }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .onChange(of: chatMessages.count) { proxy.scrollTo(chatMessages.count - 1, anchor: .bottom) }
        }
    }

    // MARK: - Voice Mode (full notch takeover)
    private var voiceModeView: some View {
        // Voice mode's green/cyan is preserved as its own character —
        // recording (green) vs returning (cyan). Typography, spacing,
        // and radii migrate to design system tokens.
        let activeColor = voice.isListening ? K.green : K.cyan

        return VStack(spacing: Kairo.Space.lg) {
            Spacer().frame(height: Kairo.Space.md)

            // Pulsing K orb with rings
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(activeColor.opacity(voice.isListening ? 0.25 / Double(i + 1) : 0), lineWidth: 1)
                        .frame(width: CGFloat(56 + i * 22), height: CGFloat(56 + i * 22))
                        .scaleEffect(voice.isListening ? 1.0 : 0.7)
                        .animation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true).delay(Double(i) * 0.2), value: voice.isListening)
                }
                Circle()
                    .fill(
                        LinearGradient(
                            colors: voice.isListening ? [K.green, K.cyan] : [K.cyan, K.blue],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                    .shadow(color: activeColor.opacity(0.6), radius: voice.isListening ? 20 : 8)
                Text("K")
                    .font(Kairo.Typography.title)
                    .foregroundStyle(.white)
            }

            // Status text
            KairoText(
                text: voice.isListening
                    ? "Listening…"
                    : (voice.isSpeaking && voice.kairoResponse.isEmpty
                        ? "Processing…"
                        : (voice.isSpeaking ? "Speaking…" : "Complete")),
                font: Kairo.Typography.titleSmall,
                color: activeColor,
                delay: 0.1
            )

            // Live waveform
            if voice.isListening {
                HStack(alignment: .center, spacing: 2.5) {
                    ForEach(0..<40, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(
                                    colors: [K.green, K.cyan.opacity(0.4)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .frame(width: 2.5, height: voiceWaveHeights[i])
                    }
                }
                .frame(height: 40)
                .padding(.horizontal, Kairo.Space.xl)
                .onReceive(Timer.publish(every: 0.06, on: .main, in: .common).autoconnect()) { _ in
                    if voice.isListening {
                        let level = voice.currentMicLevel
                        voiceWaveHeights = voiceWaveHeights.indices.map { i in
                            let base = CGFloat(level) * 34
                            let noise = CGFloat.random(in: 0.5...1.3)
                            let sine = sin(Date().timeIntervalSince1970 * 8 + Double(i) * 0.35)
                            return max(3, base * CGFloat((sine + 1) / 2) * noise)
                        }
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            // User transcript
            if !voice.userTranscript.isEmpty {
                transcriptBlock(label: "YOU", labelColor: .kTextTertiary, accent: nil) {
                    Text(voice.userTranscript)
                        .font(Kairo.Typography.body)
                        .foregroundStyle(Color.kTextSecondary)
                }
            }

            // Kairo response
            if !voice.kairoResponse.isEmpty {
                transcriptBlock(label: "KAIRO", labelColor: K.cyan, accent: K.cyan) {
                    KairoText(
                        text: voice.kairoResponse,
                        font: Kairo.Typography.bodyEmphasis,
                        color: .kTextPrimary,
                        delay: 0.04
                    )
                }
            }

            // Dismiss button
            if !voice.isListening && !voice.isSpeaking && !voice.kairoResponse.isEmpty {
                Button(action: { withAnimation(.kairoSpring) { voiceActive = false }; voice.dismiss() }) {
                    HStack(spacing: Kairo.Space.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                        Text("Done")
                            .font(Kairo.Typography.bodyEmphasis)
                    }
                    .foregroundStyle(K.green)
                    .padding(.horizontal, Kairo.Space.xl - Kairo.Space.xs)
                    .padding(.vertical, Kairo.Space.sm + 1)
                    .background(
                        Capsule().fill(K.green.opacity(0.1))
                            .overlay(Capsule().stroke(K.green.opacity(0.2), lineWidth: 0.5))
                    )
                }
                .buttonStyle(KairoBounce())
                .transition(.scale.combined(with: .opacity))
            }

            Spacer().frame(height: Kairo.Space.md)
        }
        .frame(maxWidth: .infinity)
        .background(
            RadialGradient(
                colors: [activeColor.opacity(0.10), activeColor.opacity(0.03), .clear],
                center: .center, startRadius: 0, endRadius: 220
            )
        )
        .animation(.kairoFast, value: voice.isListening)
        .animation(.kairoFast, value: voice.isSpeaking)
        .animation(.kairoFast, value: voice.kairoResponse)
    }

    /// Section block used inside voice mode for YOU / KAIRO transcripts.
    /// Accent color (when provided) tints the background and stroke.
    @ViewBuilder
    private func transcriptBlock<Content: View>(
        label: String,
        labelColor: Color,
        accent: Color?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Kairo.Space.xs + 2) {
            Text(label)
                .font(Kairo.Typography.captionStrong)
                .tracking(1.5)
                .foregroundStyle(labelColor)
            content()
                .padding(Kairo.Space.md + 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Kairo.Radius.md, style: .continuous)
                        .fill((accent ?? .white).opacity(accent == nil ? 0.04 : 0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Kairo.Radius.md, style: .continuous)
                        .strokeBorder((accent ?? .white).opacity(accent == nil ? 0.06 : 0.10), lineWidth: 0.5)
                )
        }
        .padding(.horizontal, Kairo.Space.lg + 2)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Notification In Pill
    private func notificationInPill(_ notif: KairoNotif) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if let icon = notif.appIcon {
                    Image(nsImage: icon).resizable().scaledToFit()
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(color: notif.appColor.opacity(0.4), radius: 8)
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(colors: [notif.appColor, notif.appColor.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 36, height: 36)
                        .overlay(Text(String(notif.appName.prefix(1))).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundColor(.white))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(notif.appName.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(notif.appColor)
                        .tracking(1)
                    Text(notif.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                Spacer()
                Text(notif.timeString)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.kTextTertiary)
            }
            if !notif.body.isEmpty {
                Text(notif.body)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundColor(.kTextSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Button(action: {
                    if !notif.bundleID.isEmpty, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: notif.bundleID) { NSWorkspace.shared.open(url) }
                    notifEngine.dismissCurrent()
                }) {
                    Text("Open")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(notif.appColor)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(
                            Capsule().fill(notif.appColor.opacity(0.12))
                                .overlay(Capsule().stroke(notif.appColor.opacity(0.25), lineWidth: 0.5))
                        )
                }.buttonStyle(KairoBounce())
                Button(action: { notifEngine.dismissCurrent() }) {
                    Text("Dismiss")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.kTextTertiary)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(
                            Capsule().fill(Color.white.opacity(0.05))
                                .overlay(Capsule().stroke(.white.opacity(0.06), lineWidth: 0.5))
                        )
                }.buttonStyle(KairoBounce())
                Spacer()
            }
        }
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial.opacity(0.4))
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [notif.appColor.opacity(0.08), notif.appColor.opacity(0.02), .clear],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        LinearGradient(
                            colors: [notif.appColor.opacity(0.2), .white.opacity(0.05)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            }
        )
        .gesture(DragGesture(minimumDistance: 10).onEnded { v in if v.translation.height < -30 { notifEngine.dismissCurrent() } })
    }

    // MARK: - Quick Actions
    private var quickActionsRow: some View {
        HStack(spacing: 10) {
            ForEach(quickActions) { action in
                Button(action: action.handler) {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [action.color.opacity(0.9), action.color.opacity(0.5)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 40, height: 40)
                                .shadow(color: action.color.opacity(0.4), radius: 10, y: 2)
                            Circle()
                                .fill(
                                    LinearGradient(colors: [.white.opacity(0.3), .clear], startPoint: .top, endPoint: .center)
                                )
                                .frame(width: 40, height: 40)
                            Image(systemName: action.icon)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                        }
                        Text(action.label)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundColor(.kTextTertiary)
                    }
                }
                .buttonStyle(KairoBounce())
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Input Bar
    private var inputBar: some View {
        HStack(spacing: 10) {
            Button(action: {
                withAnimation(.kairoSpring) { voiceActive = true }
            }) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [K.cyan.opacity(0.12), K.blue.opacity(0.06)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)
                        .overlay(Circle().stroke(K.cyan.opacity(0.2), lineWidth: 0.5))
                    Image(systemName: "mic.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(K.cyan)
                }
            }
            .buttonStyle(KairoBounce())

            TextField("Ask Kairo anything…", text: $kairoInput)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundColor(.kTextPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    ZStack {
                        Capsule().fill(.ultraThinMaterial.opacity(0.3))
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        K.cyan.opacity(isFocused ? 0.4 : 0.1),
                                        K.blue.opacity(isFocused ? 0.25 : 0.05)
                                    ],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ),
                                lineWidth: isFocused ? 1 : 0.5
                            )
                    }
                )
                .shadow(color: K.cyan.opacity(isFocused ? 0.15 : 0), radius: isFocused ? 12 : 0)
                .animation(.kairoFast, value: isFocused)
                .onSubmit { sendToKairo() }

            if !kairoInput.isEmpty {
                Button(action: sendToKairo) {
                    Circle()
                        .fill(K.cyanBlue)
                        .frame(width: 30, height: 30)
                        .overlay(
                            Image(systemName: "arrow.up")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                        )
                        .shadow(color: K.cyan.opacity(0.4), radius: 8)
                }
                .buttonStyle(KairoBounce())
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.kairoFast, value: kairoInput.isEmpty)
    }

    // MARK: - Response
    private var responseView: some View {
        HStack(spacing: 8) {
            KairoAvatar(size: 20)
            KairoText(text: kairoResponse, font: .system(size: 12, weight: .regular, design: .rounded), color: K.cyan, delay: 0.04)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(K.cyan.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(K.cyan.opacity(0.08), lineWidth: 0.5))
        )
        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
    }

    // MARK: - Chat Bubble (animated)
    private func chatBubble(role: String, text: String, index: Int) -> some View {
        let isKairo = role == "k"
        return HStack(alignment: .top, spacing: 8) {
            if isKairo { KairoAvatar(size: 22) }
            KairoText(
                text: text,
                font: .system(size: 12, weight: isKairo ? .regular : .regular, design: .rounded),
                color: isKairo ? .white.opacity(0.9) : .white.opacity(0.7),
                delay: 0.03
            )
            .lineSpacing(3)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .lineLimit(6)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isKairo ? K.cyan.opacity(0.06) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isKairo ? K.cyan.opacity(0.1) : .white.opacity(0.05), lineWidth: 0.5)
            )
            if !isKairo {
                Circle()
                    .fill(
                        LinearGradient(colors: [.white.opacity(0.1), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: 22, height: 22)
                    .overlay(Image(systemName: "person.fill").font(.system(size: 10)).foregroundColor(.kTextSecondary))
            }
        }
        .frame(maxWidth: .infinity, alignment: isKairo ? .leading : .trailing)
    }

    private var typingDots: some View {
        HStack(spacing: 5) {
            KairoAvatar(size: 18)
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(K.cyan.opacity(0.6)).frame(width: 5, height: 5)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(Double(i) * 0.15), value: isTyping)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14).fill(K.cyan.opacity(0.04)))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Command Card (staggered + press feel)
    private func cmdCard(_ icon: String, _ label: String, _ sub: String, _ cmd: String, color: Color = K.cyan, index: Int) -> some View {
        CmdCardView(icon: icon, label: label, sub: sub, color: color, index: index) { sendCommand(cmd) }
    }

    private func devCard(_ icon: String, _ name: String, _ val: String, _ color: Color, _ on: Bool) -> some View {
        Button(action: { sendCommand("Toggle \(name)") }) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            on ? LinearGradient(colors: [color.opacity(0.2), color.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 38, height: 38)
                        .overlay(Circle().stroke(on ? color.opacity(0.25) : .white.opacity(0.06), lineWidth: 0.5))
                        .shadow(color: color.opacity(on ? 0.3 : 0), radius: 8)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(on ? color : .secondary)
                        .opacity(on ? 1 : 0.4)
                }
                .animation(.kairoFast, value: on)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(on ? .white : .secondary)
                    Text(val)
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundColor(on ? color.opacity(0.8) : .kTextTertiary)
                }
                Spacer()
                Circle()
                    .fill(on ? color : K.muted.opacity(0.3))
                    .frame(width: 7, height: 7)
                    .shadow(color: on ? color.opacity(0.6) : .clear, radius: 4)
            }
            .padding(12)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial.opacity(0.3))
                    RoundedRectangle(cornerRadius: 14).fill(on ? color.opacity(0.03) : .clear)
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(on ? color.opacity(0.15) : .white.opacity(0.05), lineWidth: 0.5)
                }
            )
        }
        .buttonStyle(KairoBounce())
    }

    // MARK: - Data
    private var quickActions: [KairoQuickAction] {
        [.init(icon:"lightbulb.2.fill",label:"LIGHTS",color:K.gold){sendCommand("Toggle lights")},
         .init(icon:"film.stack.fill",label:"CINEMA",color:K.violet){sendCommand("Movie time")},
         .init(icon:"speaker.wave.3.fill",label:"VOL+",color:K.blue){sendCommand("Volume up")},
         .init(icon:"snowflake",label:"AC",color:K.cyan){sendCommand("Toggle AC")},
         .init(icon:"video.doorbell.fill",label:"CAM",color:K.red){sendCommand("Show camera")}]
    }

    private var appColor: Color {
        let bid = music.bundleIdentifier ?? ""
        if bid.contains("spotify") { return K.spotify }
        if bid.contains("Music") { return K.apple }
        if bid.contains("Chrome") || bid.contains("Safari") { return K.youtube }
        return dominantColor
    }

    // MARK: - Actions (local intent detection + backend fallback)
    private func sendToKairo() {
        let text = kairoInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        KairoCommandHistory.shared.add(text)
        kairoInput = ""
        if activeTab == .chat { withAnimation(.kairoFast) { chatMessages.append(("u", text)) } }

        // Try local action first
        if let localResponse = handleLocally(text) {
            withAnimation(.kairoFast) { chatMessages.append(("k", localResponse)) }
            kairoResponse = localResponse; withAnimation(.kairoFast) { showResponse = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { withAnimation(.kairoFast) { showResponse = false } }
            return
        }

        // Fallback to backend
        isTyping = true; isProcessing = true
        socket.sendTextCommand(text) { response in
            isProcessing = false
            if activeTab == .chat { isTyping = false; withAnimation(.kairoFast) { chatMessages.append(("k", response)) } }
            else { kairoResponse = response; withAnimation(.kairoFast) { showResponse = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { withAnimation(.kairoFast) { showResponse = false } } }
        }
    }

    private func sendCommand(_ cmd: String) {
        KairoCommandHistory.shared.add(cmd)
        withAnimation(.kairoFast) { chatMessages.append(("u", cmd)) }; activeTab = .chat

        if let localResponse = handleLocally(cmd) {
            withAnimation(.kairoFast) { chatMessages.append(("k", localResponse)) }
            kairoResponse = localResponse; withAnimation(.kairoFast) { showResponse = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { withAnimation(.kairoFast) { showResponse = false } }
            return
        }

        isTyping = true; isProcessing = true
        socket.sendTextCommand(cmd) { response in
            isProcessing = false; isTyping = false
            withAnimation(.kairoFast) { chatMessages.append(("k", response)) }
            kairoResponse = response; withAnimation(.kairoFast) { showResponse = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { withAnimation(.kairoFast) { showResponse = false } }
        }
    }

    // MARK: - Local Intent Detection (instant, no backend needed)
    private func handleLocally(_ text: String) -> String? {
        let t = text.lowercased()
        let ctrl = KairoAppController.shared

        // YouTube — use API to get exact video, open with autoplay
        if t.contains("youtube") && (t.contains("play") || t.contains("open")) {
            let query = text.replacingOccurrences(of: "(?i)play |on youtube|youtube|open ", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            let searchQuery = query.isEmpty ? text : query
            // Get video ID via YouTube API and open directly
            let ytKey = ProcessInfo.processInfo.environment["YOUTUBE_API_KEY"] ?? ""
            if !ytKey.isEmpty {
                let encoded = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? searchQuery
                Task {
                    if let apiURL = URL(string: "https://www.googleapis.com/youtube/v3/search?part=snippet&q=\(encoded)&type=video&maxResults=1&key=\(ytKey)") {
                        do {
                            let (data, _) = try await URLSession.shared.data(from: apiURL)
                            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let items = json["items"] as? [[String: Any]], let first = items.first,
                               let id = first["id"] as? [String: Any], let videoID = id["videoId"] as? String {
                                let videoURL = "https://www.youtube.com/watch?v=\(videoID)"
                                await MainActor.run {
                                    if let url = URL(string: videoURL) { NSWorkspace.shared.open(url) }
                                }
                                return
                            }
                        } catch {}
                    }
                    // Fallback to search
                    await MainActor.run { ctrl.playOnYouTube(searchQuery) }
                }
            } else {
                ctrl.playOnYouTube(searchQuery)
            }
            return "Playing \(searchQuery) on YouTube..."
        }

        // Spotify
        if t.contains("spotify") && (t.contains("play") || t.contains("open")) {
            let query = text.replacingOccurrences(of: "(?i)play |on spotify|spotify|open ", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            ctrl.playOnSpotify(query.isEmpty ? text : query)
            return "Opening Spotify for \(query.isEmpty ? text : query)"
        }

        // Apple Music
        if (t.contains("apple music") || t.contains("apple")) && t.contains("play") {
            let query = text.replacingOccurrences(of: "(?i)play |on apple music|apple music|open ", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            ctrl.playOnAppleMusic(query.isEmpty ? text : query)
            return "Playing on Apple Music"
        }

        // Open app
        if t.hasPrefix("open ") {
            let app = String(text.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            ctrl.openApp(app)
            return "Opening \(app)"
        }

        // Google search
        if t.hasPrefix("search ") || t.hasPrefix("google ") {
            let query = text.replacingOccurrences(of: "(?i)^search |^google |^search google for |^google for ", with: "", options: .regularExpression)
            ctrl.googleSearch(query)
            return "Searching Google for \(query)"
        }

        // Volume
        if t.contains("volume") && t.contains("up") { ctrl.setSystemVolume(min(100, 70)); return "Volume up" }
        if t.contains("volume") && t.contains("down") { ctrl.setSystemVolume(max(0, 30)); return "Volume down" }
        if t.contains("mute") { ctrl.setSystemVolume(0); return "Muted" }

        // Screenshot
        if t.contains("screenshot") { ctrl.takeScreenshot(); return "Screenshot tool opened" }

        // Lock
        if t.contains("lock") && t.contains("screen") { ctrl.lockScreen(); return "Screen locked" }

        // Not a local action — let backend handle
        return nil
    }
}

// MARK: - Command Card with staggered animation + press feel
struct CmdCardView: View {
    let icon: String, label: String, sub: String
    var color: Color = K.cyan
    var index: Int = 0
    let action: () -> Void
    @State private var appeared = false
    @State private var isPressed = false

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.18), color.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(color.opacity(isPressed ? 0.4 : 0.15), lineWidth: 0.5)
                    )
                    .shadow(color: color.opacity(isPressed ? 0.3 : 0.1), radius: isPressed ? 12 : 6)
                    .scaleEffect(isPressed ? 0.88 : 1.0)
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                    )
                    .scaleEffect(isPressed ? 0.9 : 1.0)
                    .shadow(color: color.opacity(0.4), radius: 8)
            }
            VStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                Text(sub)
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundColor(.kTextTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 8)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial.opacity(0.3))
                RoundedRectangle(cornerRadius: 14)
                    .fill(color.opacity(isPressed ? 0.06 : 0.02))
                RoundedRectangle(cornerRadius: 14)
                    .stroke(color.opacity(isPressed ? 0.2 : 0.06), lineWidth: 0.5)
            }
        )
        .scaleEffect(isPressed ? 0.94 : (appeared ? 1 : 0.85))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .animation(.kairoFast, value: isPressed)
        .onAppear { withAnimation(.kairoSpring.delay(Double(index) * 0.04)) { appeared = true } }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isPressed { isPressed = true; NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default) } }
                .onEnded { _ in isPressed = false; action() }
        )
    }
}
