//
//  TeleprompterView.swift
//  boringNotch
//
//  The teleprompter tab shown inside the open notch: a scrolling script that
//  follows your voice, a control bar, and arrow-key scrubbing. Script editing
//  lives in Settings (the notch panel can't take keyboard focus).
//

import SwiftUI
import Defaults

struct TeleprompterView: View {
    @StateObject private var model = TeleprompterViewModel.shared
    @State private var keyMonitor: TeleprompterKeyMonitor?
    @State private var dragStartHeight: CGFloat?
    @State private var dragStartWidth: CGFloat?

    var body: some View {
        VStack(spacing: 6) {
            controlBar
            if model.words.isEmpty {
                emptyState
            } else {
                script
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) { heightHandle }
        .overlay(alignment: .trailing) { widthHandle }
        .onAppear(perform: installKeyMonitor)
        .onDisappear {
            keyMonitor?.stop()
            keyMonitor = nil
            model.viewDisappeared()
        }
        .onChange(of: Defaults[.teleprompterArrowKeys]) { _, enabled in
            if enabled {
                installKeyMonitor()
            } else {
                keyMonitor?.stop()
                keyMonitor = nil
            }
        }
    }

    // MARK: - Control bar

    private var controlBar: some View {
        HStack(spacing: 12) {
            iconButton(model.isRunning ? "pause.fill" : "play.fill") { model.toggleRun() }
                .disabled(model.words.isEmpty)
            iconButton("backward.end.fill") { model.restart() }
            voiceToggle

            // Always-works manual scrub: previous / next line (mouse clicks
            // reach the notch panel even though it can't take key focus).
            iconButton("chevron.up") { model.step(chunks: -1) }
                .disabled(model.words.isEmpty)
            iconButton("chevron.down") { model.step(chunks: 1) }
                .disabled(model.words.isEmpty)

            Spacer(minLength: 6)
            statusLabel
            Spacer(minLength: 6)

            iconButton("textformat.size.smaller") { model.fontSize = max(12, model.fontSize - 2) }
            iconButton("textformat.size.larger") { model.fontSize = min(40, model.fontSize + 2) }
            iconButton(model.mirror ? "arrow.left.and.right.circle.fill"
                                    : "arrow.left.and.right.circle") {
                model.mirror.toggle()
            }
            iconButton("square.and.pencil") { TeleprompterSettingsRoute.open() }
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.gray)
        .frame(height: 22)
    }

    private var voiceToggle: some View {
        Button {
            model.setFollowVoice(!model.followVoice)
        } label: {
            Image(systemName: model.followVoice ? "mic.fill" : "mic.slash.fill")
                .foregroundStyle(voiceTint)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.followVoice ? "Following your voice" : "Voice following off")
    }

    private var voiceTint: Color {
        guard model.followVoice else { return .gray }
        if model.statusMessage != nil { return .orange }
        return model.isListening ? .green : .gray
    }

    @ViewBuilder
    private var statusLabel: some View {
        if let message = model.statusMessage {
            Text(message)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.orange)
                .font(.system(size: 10, weight: .medium))
        } else if !model.words.isEmpty {
            Text("\(model.currentWordIndex)/\(model.words.count)")
                .foregroundStyle(.gray)
                .font(.system(size: 10, weight: .medium).monospacedDigit())
        }
    }

    // MARK: - Script

    private var script: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    Color.clear.frame(height: 34)
                    ForEach(model.chunks) { chunk in
                        chunkText(chunk)
                            .id(chunk.id)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Color.clear.frame(height: 44)
                }
                .padding(.horizontal, 6)
            }
            // Let the voice drive scrolling while following; allow manual
            // trackpad scrolling otherwise.
            .scrollDisabled(model.isRunning && model.followVoice)
            .mask(fadeMask)
            .scaleEffect(x: model.mirror ? -1 : 1, y: 1, anchor: .center)
            .onChange(of: model.currentChunkIndex) { _, newValue in
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
            .onAppear {
                proxy.scrollTo(model.currentChunkIndex, anchor: .center)
            }
        }
    }

    private func chunkText(_ chunk: ScriptChunk) -> some View {
        Text(attributed(for: chunk))
            .font(TeleprompterFont.body(size: model.fontSize))
            .lineSpacing(2)
            .opacity(chunk.id == model.currentChunkIndex ? 1 : 0.5)
            .animation(.easeInOut(duration: 0.25), value: model.currentChunkIndex)
            .animation(.easeInOut(duration: 0.2), value: model.currentWordIndex)
    }

    private func attributed(for chunk: ScriptChunk) -> AttributedString {
        var result = AttributedString()
        for (offset, word) in chunk.words.enumerated() {
            var piece = AttributedString(word.display)
            let index = word.globalIndex
            if index < model.currentWordIndex {
                piece.foregroundColor = .white.opacity(0.32)      // already read
            } else if index == model.currentWordIndex {
                piece.foregroundColor = .white                    // current word
                piece.font = TeleprompterFont.emphasis(size: model.fontSize)
            } else {
                piece.foregroundColor = .white.opacity(0.78)      // upcoming
            }
            result += piece
            if offset < chunk.words.count - 1 {
                result += AttributedString(" ")
            }
        }
        return result
    }

    private var fadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.18),
                .init(color: .black, location: 0.82),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 22))
                .foregroundStyle(.gray)
            Text("No script yet")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.gray)
            Button("Add a script…") { TeleprompterSettingsRoute.open() }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.12)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Building blocks

    private func iconButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Edge resize handles (drag the notch's bottom / side to resize)

    private var heightHandle: some View {
        Capsule()
            .fill(.white.opacity(0.22))
            .frame(width: 46, height: 5)
            .frame(width: 140, height: 16)          // larger, invisible hit area
            .contentShape(Rectangle())
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        let base = dragStartHeight ?? Defaults[.notchOpenHeight]
                        if dragStartHeight == nil { dragStartHeight = base }
                        Defaults[.notchOpenHeight] = min(max((base + value.translation.height).rounded(), 150), 460)
                    }
                    .onEnded { _ in dragStartHeight = nil }
            )
            .help("Drag to resize the notch height")
    }

    private var widthHandle: some View {
        Capsule()
            .fill(.white.opacity(0.22))
            .frame(width: 5, height: 46)
            .frame(width: 16, height: 120)          // larger, invisible hit area
            .contentShape(Rectangle())
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        let base = dragStartWidth ?? Defaults[.notchOpenWidth]
                        if dragStartWidth == nil { dragStartWidth = base }
                        // Notch is centre-anchored, so both edges move — apply 2× the drag.
                        Defaults[.notchOpenWidth] = min(max((base + value.translation.width * 2).rounded(), 520), 900)
                    }
                    .onEnded { _ in dragStartWidth = nil }
            )
            .help("Drag to resize the notch width")
    }

    private func installKeyMonitor() {
        guard Defaults[.teleprompterArrowKeys], keyMonitor == nil else { return }
        let monitor = TeleprompterKeyMonitor { key in
            switch key {
            case .up:    model.step(chunks: -1)
            case .down:  model.step(chunks: 1)
            case .left:  model.step(words: -1)
            case .right: model.step(words: 1)
            case .space: model.toggleRun()
            }
        }
        monitor.start()
        keyMonitor = monitor
    }
}

#Preview {
    TeleprompterView()
        .environmentObject(BoringViewModel())
        .frame(width: 640, height: 160)
        .background(.black)
}
