//
//  AppleIntelligencePDFDropView.swift
//  boringNotch
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PDFSummaryChatMessage: Identifiable, Equatable {
    enum Role {
        case user
        case assistant
        case error
    }

    let id = UUID()
    let role: Role
    let text: String
}

@MainActor
final class AppleIntelligencePDFSummaryState: ObservableObject {
    static let shared = AppleIntelligencePDFSummaryState()

    @Published var isPresented = false
    @Published var isProcessing = false
    @Published var progress = 0.0
    @Published var title = "Apple Intelligence"
    @Published var summary = ""
    @Published var statusMessage = "Preparing PDF"
    @Published var errorMessage: String?
    @Published var chatMessages: [PDFSummaryChatMessage] = []
    @Published var isAnswering = false

    private var documentText = ""
    private var progressTask: Task<Void, Never>?

    func start(title: String) {
        progressTask?.cancel()
        self.title = title
        self.summary = ""
        self.documentText = ""
        self.errorMessage = nil
        self.chatMessages = []
        self.isAnswering = false
        self.statusMessage = "Reading PDF"
        self.progress = 0.06
        self.isProcessing = true
        self.isPresented = true

        progressTask = Task { @MainActor in
            while !Task.isCancelled && self.isProcessing {
                try? await Task.sleep(for: .milliseconds(520))
                guard !Task.isCancelled && self.isProcessing else { return }

                let remaining = 0.92 - self.progress
                let step = max(0.012, remaining * 0.16)
                withAnimation(.smooth(duration: 0.5)) {
                    self.progress = min(0.92, self.progress + step)
                    self.statusMessage = self.statusMessage(for: self.progress)
                }
            }
        }
    }

    func show(summary: String, title: String, documentText: String = "") {
        progressTask?.cancel()
        self.title = title
        self.summary = summary
        self.documentText = documentText
        self.errorMessage = nil
        self.chatMessages = []
        self.isAnswering = false
        self.statusMessage = "Done"
        withAnimation(.smooth(duration: 0.25)) {
            self.progress = 1
            self.isProcessing = false
            self.isPresented = true
        }
    }

    func showError(_ message: String) {
        progressTask?.cancel()
        self.title = "Apple Intelligence"
        self.summary = ""
        self.documentText = ""
        self.statusMessage = "Stopped"
        self.errorMessage = message
        self.chatMessages = []
        self.isAnswering = false
        withAnimation(.smooth(duration: 0.25)) {
            self.progress = 1
            self.isProcessing = false
            self.isPresented = true
        }
    }

    func dismiss() {
        progressTask?.cancel()
        isPresented = false
        isProcessing = false
        isAnswering = false
        progress = 0
    }

    func ask(_ question: String) async {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty, !isProcessing, errorMessage == nil else { return }

        withAnimation(.smooth(duration: 0.22)) {
            chatMessages.append(PDFSummaryChatMessage(role: .user, text: trimmedQuestion))
            isAnswering = true
        }

        do {
            let response = try await PDFAppleIntelligenceSummaryService.shared.answerQuestion(
                trimmedQuestion,
                summary: summary,
                documentText: documentText
            )
            withAnimation(.smooth(duration: 0.25)) {
                self.chatMessages.append(PDFSummaryChatMessage(role: .assistant, text: response))
                self.isAnswering = false
            }
        } catch {
            withAnimation(.smooth(duration: 0.25)) {
                self.chatMessages.append(PDFSummaryChatMessage(role: .error, text: error.localizedDescription))
                self.isAnswering = false
            }
        }
    }

    private func statusMessage(for progress: Double) -> String {
        switch progress {
        case ..<0.24:
            return "Reading PDF"
        case ..<0.46:
            return "Finding the important parts"
        case ..<0.68:
            return "Apple Intelligence is summarizing"
        case ..<0.88:
            return "Almost done"
        default:
            return "Finishing up"
        }
    }
}

struct AppleIntelligencePDFDropView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @StateObject private var summaryState = AppleIntelligencePDFSummaryState.shared
    @State private var isProcessing = false

    private var isVisuallyTargeted: Bool { vm.appleIntelligenceDropTargeting }

    var body: some View {
        dropArea
            .onTapGesture {
                Task { await choosePDFsAndSummarize() }
            }
    }

    private var dropArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.35), Color.black.opacity(0.20)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isVisuallyTargeted ? Color.white.opacity(0.72) : Color.white.opacity(0.1),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10])
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(appleIntelligenceGradient, lineWidth: 2)
                        .opacity(isVisuallyTargeted ? 1 : 0)
                )
                .shadow(color: Color.black.opacity(0.6), radius: 6, x: 0, y: 2)

            VStack(spacing: 5) {
                appleIntelligenceMark

                Text("Summarize with Apple Intelligence")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.86))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)

            if isProcessing {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.black.opacity(0.35))
                    .overlay(
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    )
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    private var appleIntelligenceMark: some View {
        ZStack {
            if isVisuallyTargeted {
                Image("apple_intelligence-logo_brandlogos.net_zmypw-512x504")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            } else {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 31, weight: .semibold))
                    .foregroundStyle(.gray)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .frame(width: 56, height: 56)
        .scaleEffect(isVisuallyTargeted ? 1.06 : 1.0)
        .animation(.spring(response: 0.36, dampingFraction: 0.7), value: isVisuallyTargeted)
    }

    private var appleIntelligenceGradient: AngularGradient {
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

    @MainActor
    private func summarizeDroppedPDFs(from providers: [NSItemProvider]) async {
        isProcessing = true
        defer {
            isProcessing = false
            vm.appleIntelligenceDropTargeting = false
            vm.dropEvent = false
        }

        let pdfURLs = await AppleIntelligencePDFDropHandler.pdfURLs(from: providers)
        await summarizePDFs(at: pdfURLs)
    }

    @MainActor
    private func choosePDFsAndSummarize() async {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.pdf]
        panel.title = "Select PDFs to summarize"
        panel.message = "Choose PDFs to summarize with Apple Intelligence"

        guard panel.runModal() == .OK else { return }

        isProcessing = true
        defer { isProcessing = false }
        await summarizePDFs(at: panel.urls)
    }

    @MainActor
    private func summarizePDFs(at pdfURLs: [URL]) async {
        guard !pdfURLs.isEmpty else {
            summaryState.showError("Drop a PDF file on the AI PDF tile to summarize it.")
            vm.open()
            return
        }

            let title = pdfSummaryTitle(for: pdfURLs)
            summaryState.start(title: title)
            vm.open()
            withAnimation(vm.animation) {
                vm.notchSize = appleIntelligenceSummaryNotchSize
            }

            do {
            let result = try await pdfURLs.accessSecurityScopedResources { urls in
                try await PDFAppleIntelligenceSummaryService.shared.summarizePDFsWithContext(at: urls)
            }

            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(result.summary, forType: .string)
            summaryState.show(summary: result.summary, title: title, documentText: result.documentText)
        } catch {
            print("Failed to summarize dropped PDF: \(error.localizedDescription)")
            summaryState.showError(error.localizedDescription)
        }
    }

    private func pdfSummaryTitle(for urls: [URL]) -> String {
        guard let first = urls.first else { return "Apple Intelligence" }
        if urls.count == 1 {
            return first.deletingPathExtension().lastPathComponent
        }
        return "\(urls.count) PDFs summarized"
    }

}

enum AppleIntelligencePDFDropHandler {
    static func pdfURLs(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []

        for provider in providers {
            if let fileURL = await provider.extractFileURL(), isPDF(fileURL) {
                urls.append(fileURL)
            } else if let url = await provider.extractURL(), url.isFileURL, isPDF(url) {
                urls.append(url)
            } else if let itemURL = await provider.extractItem(), isPDF(itemURL) {
                urls.append(itemURL)
            }
        }

        return urls.removingDuplicatesByStandardizedPath()
    }

    static func isPDF(_ url: URL) -> Bool {
        if url.pathExtension.lowercased() == "pdf" {
            return true
        }
        if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return contentType.conforms(to: .pdf)
        }
        return false
    }
}

private extension Array where Element == URL {
    func removingDuplicatesByStandardizedPath() -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []

        for url in self {
            let key = url.standardizedFileURL.path
            guard seen.insert(key).inserted else { continue }
            result.append(url)
        }

        return result
    }
}
