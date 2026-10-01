// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

//
//  FileShareView.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-24.
//

import AppKit
import Defaults
import SwiftUI
import UniformTypeIdentifiers

struct FileShareView: View {
    var compact: Bool = false
    @EnvironmentObject private var vm: BoringViewModel
    @StateObject private var quickShare = QuickShareService.shared
    @Default(.quickShareProvider) var quickShareProvider: String

    @State private var hostView: NSView?
    @State private var interactionNonce: UUID = .init()
    @State private var isProcessing = false
    
    private var selectedProvider: QuickShareProvider {
        quickShare.availableProviders.first(where: { $0.id == quickShareProvider }) ?? QuickShareProvider(id: "System Share Menu", imageData: nil, supportsRawText: true)
    }

    var body: some View {
        dropArea
            .background(NSViewHost(view: $hostView))
            .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data, .image], isTargeted: $vm.dropZoneTargeting) { providers in
                interactionNonce = .init()
                vm.dropEvent = true
                Task { await handleDrop(providers) }
                return true
            }
            .onTapGesture {
                Task {
                    await handleClick()
                }
            }
    }

    private var dropArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(colors: [Color.black.opacity(0.35), Color.black.opacity(0.20)], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            vm.dropZoneTargeting
                                ? Color.accentColor.opacity(0.9)
                                : Color.white.opacity(0.1),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10])
                        )
                )
                .shadow(color: Color.black.opacity(0.6), radius: 6, x: 0, y: 2)

            // Content
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(
                            vm.dropZoneTargeting ? 0.11 : 0.09
                        ))
                        .frame(width: compact ? 40 : 55, height: compact ? 40 : 55)
                    Image(systemName: "square.and.arrow.up")
                    Group {
                        if let imgData = selectedProvider.imageData, let nsImg = NSImage(data: imgData) {
                            Image(nsImage: nsImg)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .frame(width: compact ? 24 : 34, height: compact ? 24 : 34)
                        .foregroundStyle(
                            vm.dropZoneTargeting ? Color.accentColor : Color.gray
                        )
                        .scaleEffect(
                            vm.dropZoneTargeting ? 1.06 : 1.0
                        )
                        .animation(.spring(response: 0.36, dampingFraction: 0.7), value: vm.dropZoneTargeting)
                }

                Text(selectedProvider.id)
                    .font(.system(compact ? .caption : .headline, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineLimit(compact ? 2 : nil)

            }
            .padding(compact ? 6 : 18)
            
            // Loading overlay
            if isProcessing || quickShare.isPickerOpen {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.black.opacity(0.3))
                    .overlay(
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    )
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions

    private func handleDrop(_ providers: [NSItemProvider]) async {
        isProcessing = true
        defer { isProcessing = false }
        await quickShare.shareDroppedFiles(providers, using: selectedProvider, from: hostView)
    }
    
    private func handleClick() async {
        await quickShare.showFilePicker(for: selectedProvider, from: hostView)
    }
}

// MARK: - Host NSView extractor for anchoring share sheet

private struct NSViewHost: NSViewRepresentable {
    @Binding var view: NSView?
    
    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        DispatchQueue.main.async { self.view = v }
        return v
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { self.view = nsView }
    }
}
