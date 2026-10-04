//
//  AppleIntelligencePDFSummaryOverlay.swift
//  boringNotch
//

import AppKit
import SwiftUI

struct AppleIntelligencePDFSummaryOverlay: View {
    @EnvironmentObject private var vm: BoringViewModel
    @StateObject private var state = AppleIntelligencePDFSummaryState.shared
    @State private var questionDraft = ""
    @FocusState private var isQuestionFieldFocused: Bool

    private let chatBottomID = "pdf-summary-chat-bottom"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if state.isProcessing {
                processingBody
            } else {
                summaryBody

                if state.errorMessage == nil {
                    askBar
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(summaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .top) {
            topAccent
        }
        .animation(.smooth(duration: 0.28), value: state.isProcessing)
    }

    private var header: some View {
        HStack(spacing: 10) {
            appleIntelligenceGlyph

            VStack(alignment: .leading, spacing: 2) {
                Text(headerEyebrow)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.50))
                Text(state.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
            }

            Spacer()

            if !state.isProcessing && state.errorMessage == nil {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(state.summary, forType: .string)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.on.doc")
                        Text("Copy")
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.76))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }

            Button {
                vm.resetDropSessionState()
                state.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.68))
                    .frame(width: 24, height: 24)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
    }

    private var processingBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer(minLength: 2)

            HStack(alignment: .firstTextBaseline) {
                Text(state.statusMessage)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)

                Spacer()

                Text("\(Int(state.progress * 100))%")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.64))
            }

            progressTrack

            Text("Almost done when the bar reaches the end.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.44))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }

    private var progressTrack: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.white.opacity(0.11))

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(pastelLinearGradient)
                    .frame(width: max(10, geometry.size.width * state.progress))
                    .blur(radius: 6)
                    .opacity(0.70)

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(pastelLinearGradient)
                    .frame(width: max(10, geometry.size.width * state.progress))
                    .shadow(color: Color(red: 0.50, green: 0.82, blue: 1.0).opacity(0.65), radius: 8)
                    .shadow(color: Color(red: 1.0, green: 0.66, blue: 0.86).opacity(0.45), radius: 12)

            }
        }
        .frame(height: 10)
    }

    private var summaryBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(state.errorMessage ?? state.summary)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)

                    if state.errorMessage == nil {
                        chatSection
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(chatBottomID)
                }
            }
            .scrollIndicators(.visible)
            .onChange(of: state.chatMessages.count) { _, _ in
                scrollToChatBottom(with: proxy)
            }
            .onChange(of: state.isAnswering) { _, _ in
                scrollToChatBottom(with: proxy)
            }
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.05),
                    .init(color: .black, location: 0.95),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func scrollToChatBottom(with proxy: ScrollViewProxy) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(40))
            withAnimation(.smooth(duration: 0.24)) {
                proxy.scrollTo(chatBottomID, anchor: .bottom)
            }
        }
    }

    private var chatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(state.chatMessages) { message in
                chatBubble(for: message)
                    .id(message.id)
                    .transition(.move(edge: message.role == .user ? .trailing : .leading).combined(with: .opacity))
            }

            if state.isAnswering {
                typingBubble
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private func chatBubble(for message: PDFSummaryChatMessage) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            if message.role == .user {
                Spacer(minLength: 54)
            }

            Text(message.text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(message.role == .user ? .white : .white.opacity(0.90))
                .lineSpacing(3)
                .textSelection(.enabled)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(chatBubbleBackground(for: message.role))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            if message.role != .user {
                Spacer(minLength: 54)
            }
        }
    }

    private var typingBubble: some View {
        HStack(alignment: .bottom, spacing: 6) {
            HStack(spacing: 5) {
                ProgressView()
                    .scaleEffect(0.55)
                Text("Apple Intelligence...")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Spacer(minLength: 54)
        }
    }

    private func chatBubbleBackground(for role: PDFSummaryChatMessage.Role) -> some ShapeStyle {
        switch role {
        case .user:
            AnyShapeStyle(
                LinearGradient(
                    colors: [Color(red: 0.18, green: 0.45, blue: 1.0), Color(red: 0.32, green: 0.63, blue: 1.0)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .assistant:
            AnyShapeStyle(.white.opacity(0.075))
        case .error:
            AnyShapeStyle(.yellow.opacity(0.18))
        }
    }

    private var askBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(pastelLinearGradient)

            TextField("Ask about this document...", text: $questionDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.86))
                .focused($isQuestionFieldFocused)
                .disabled(state.isAnswering)
                .onSubmit { submitQuestion() }

            Button {
                submitQuestion()
            } label: {
                if state.isAnswering {
                    ProgressView()
                        .scaleEffect(0.55)
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 18, height: 18)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(canSubmitQuestion ? .white.opacity(0.74) : .white.opacity(0.28))
            .disabled(!canSubmitQuestion)
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            isQuestionFieldFocused = true
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var canSubmitQuestion: Bool {
        !questionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !state.isAnswering
    }

    private func submitQuestion() {
        guard canSubmitQuestion else { return }
        let question = questionDraft
        questionDraft = ""
        Task { await state.ask(question) }
    }

    private var headerEyebrow: String {
        if state.isProcessing { return "Apple Intelligence" }
        return state.errorMessage == nil ? "Summary" : "PDF Summary Failed"
    }

    private var appleIntelligenceGlyph: some View {
        ZStack {
            Circle()
                .stroke(pastelAngularGradient, lineWidth: state.isProcessing ? 3 : 2.5)
                .frame(width: 28, height: 28)
                .rotationEffect(.degrees(state.isProcessing ? state.progress * 360 : 0))
                .animation(.smooth(duration: 0.5), value: state.progress)

            Image(systemName: glyphName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(state.errorMessage == nil ? AnyShapeStyle(pastelLinearGradient) : AnyShapeStyle(.yellow))
        }
    }

    private var glyphName: String {
        if state.isProcessing { return "sparkles" }
        return state.errorMessage == nil ? "sparkles" : "exclamationmark"
    }

    private var summaryBackground: some View {
        ZStack {
            Color.black
            LinearGradient(
                colors: [.white.opacity(0.04), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var topAccent: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(pastelLinearGradient)
            .frame(height: 3)
            .padding(.horizontal, 18)
            .allowsHitTesting(false)
    }

    private var pastelLinearGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.50, green: 0.82, blue: 1.0),
                Color(red: 0.72, green: 0.66, blue: 1.0),
                Color(red: 1.0, green: 0.66, blue: 0.86),
                Color(red: 1.0, green: 0.78, blue: 0.62),
                Color(red: 1.0, green: 0.92, blue: 0.58)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var pastelAngularGradient: AngularGradient {
        AngularGradient(
            colors: [
                Color(red: 0.50, green: 0.82, blue: 1.0),
                Color(red: 0.72, green: 0.66, blue: 1.0),
                Color(red: 1.0, green: 0.66, blue: 0.86),
                Color(red: 1.0, green: 0.78, blue: 0.62),
                Color(red: 1.0, green: 0.92, blue: 0.58),
                Color(red: 0.50, green: 0.82, blue: 1.0)
            ],
            center: .center
        )
    }
}
