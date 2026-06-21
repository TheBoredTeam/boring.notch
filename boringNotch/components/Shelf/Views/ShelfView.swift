//
//  ShelfItemView.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-24.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ShelfView: View {
    @EnvironmentObject var vm: BoringViewModel
    @StateObject var tvm = ShelfStateViewModel.shared
    @StateObject var selection = ShelfSelectionModel.shared
    @StateObject private var quickLookService = QuickLookService()
    @StateObject private var pdfSummaryState = AppleIntelligencePDFSummaryState.shared
    private let spacing: CGFloat = 8
    private let tileSpacing: CGFloat = 12
    private let acceptedDropTypes: [UTType] = [.fileURL, .url, .pdf, .item, .data, .image, .utf8PlainText, .plainText]

    var body: some View {
        HStack(spacing: tileSpacing) {
            FileShareView()
                .aspectRatio(1, contentMode: .fit)
                .environmentObject(vm)
            AppleIntelligencePDFDropView()
                .aspectRatio(1, contentMode: .fit)
                .environmentObject(vm)
            panel
        }
        .onDrop(
            of: acceptedDropTypes,
            delegate: ShelfDropRoutingDelegate(
                acceptedDropTypes: acceptedDropTypes,
                tileSpacing: tileSpacing,
                tileSide: max(80, vm.notchSize.height - vm.effectiveClosedNotchHeight - 24),
                vm: vm,
                storeProviders: handleDrop,
                summarizeProviders: summarizeDroppedPDFs
            )
        )
        // Bind Quick Look to shelf selection
        .onChange(of: selection.selectedIDs) {
            updateQuickLookSelection()
        }
        .quickLookPresenter(using: quickLookService)
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !selection.isDragging else { return false }
        vm.dropEvent = true

        Task { @MainActor in
            ShelfStateViewModel.shared.load(providers)
            vm.dropEvent = false
            vm.storageDropTargeting = false
            vm.dragDetectorTargeting = false
            try? await Task.sleep(for: .milliseconds(250))

            vm.suppressAutoOpenUntil = Date().addingTimeInterval(1.2)
            vm.dropEvent = false
            vm.storageDropTargeting = false
            vm.dragDetectorTargeting = false
            vm.generalDropTargeting = false
            vm.appleIntelligenceDropTargeting = false

            guard !vm.appleIntelligenceDropTargeting,
                  !vm.storageDropTargeting else { return }

            withAnimation(vm.animation) {
                vm.close(ignoringSharingState: true)
            }
        }
        return true
    }

    private func summarizeDroppedPDFs(providers: [NSItemProvider]) -> Bool {
        vm.dropEvent = true

        Task { @MainActor in
            defer {
                vm.dropEvent = false
                vm.appleIntelligenceDropTargeting = false
            }

            let pdfURLs = await AppleIntelligencePDFDropHandler.pdfURLs(from: providers)
            guard !pdfURLs.isEmpty else {
                pdfSummaryState.showError("Drop a PDF file on the Apple Intelligence tile to summarize it.")
                vm.open()
                return
            }

            let title = pdfSummaryTitle(for: pdfURLs)
            pdfSummaryState.start(title: title)
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
                pdfSummaryState.show(summary: result.summary, title: title, documentText: result.documentText)
            } catch {
                print("Failed to summarize dropped PDF: \(error.localizedDescription)")
                pdfSummaryState.showError(error.localizedDescription)
            }
        }

        return true
    }

    private func pdfSummaryTitle(for urls: [URL]) -> String {
        guard let first = urls.first else { return "Apple Intelligence" }
        if urls.count == 1 {
            return first.deletingPathExtension().lastPathComponent
        }
        return "\(urls.count) PDFs summarized"
    }

    private func updateQuickLookSelection() {
        guard quickLookService.isQuickLookOpen && !selection.selectedIDs.isEmpty else { return }
        
        let selectedItems = selection.selectedItems(in: tvm.items)
        let urls: [URL] = selectedItems.compactMap { item in
            if let fileURL = item.fileURL {
                return fileURL
            }
            if case .link(let url) = item.kind {
                return url
            }
            return nil
        }
        
        if !urls.isEmpty {
            quickLookService.updateSelection(urls: urls)
        }
    }

    var panel: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(
                vm.storageDropTargeting
                    ? Color.accentColor.opacity(0.9)
                    : Color.white.opacity(0.1),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10])
            )
            .overlay {
                content
                    .padding()
            }
            .transaction { transaction in
                transaction.animation = vm.animation
            }
            .contentShape(Rectangle())
            .onTapGesture { selection.clear() }
            .contextMenu {
                if !tvm.isEmpty {
                    Button("Clear All", role: .destructive) {
                        tvm.clearAll()
                    }
                }
            }
    }

    var content: some View {
        Group {
            if tvm.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray.and.arrow.down")
                        .symbolVariant(.fill)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white, .gray)
                        .imageScale(.large)
                    
                    Text("Drop files here")
                        .foregroundStyle(.gray)
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.medium)
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: spacing) {
                        ForEach(tvm.items) { item in
                            ShelfItemView(item: item)
                                .environmentObject(quickLookService)
                        }
                    }
                }
                .padding(-spacing)
                .scrollIndicators(.never)
            }
        }
        .onAppear {
            ShelfStateViewModel.shared.cleanupInvalidItems()
        }
    }
}

private struct ShelfDropRoutingDelegate: DropDelegate {
    let acceptedDropTypes: [UTType]
    let tileSpacing: CGFloat
    let tileSide: CGFloat
    let vm: BoringViewModel
    let storeProviders: ([NSItemProvider]) -> Bool
    let summarizeProviders: ([NSItemProvider]) -> Bool

    func dropEntered(info: DropInfo) {
        updateTargeting(for: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateTargeting(for: info)
        return route(for: info) == .share ? nil : DropProposal(operation: .copy)
    }

    func dropExited(info _: DropInfo) {
        vm.storageDropTargeting = false
        vm.appleIntelligenceDropTargeting = false
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: acceptedDropTypes)
        vm.storageDropTargeting = false
        vm.appleIntelligenceDropTargeting = false

        switch route(for: info) {
        case .share:
            return false
        case .appleIntelligence:
            return summarizeProviders(providers)
        case .storage:
            return storeProviders(providers)
        }
    }

    private func updateTargeting(for info: DropInfo) {
        switch route(for: info) {
        case .share:
            vm.storageDropTargeting = false
            vm.appleIntelligenceDropTargeting = false
        case .appleIntelligence:
            vm.dropEvent = true
            vm.storageDropTargeting = false
            vm.appleIntelligenceDropTargeting = true
        case .storage:
            vm.dropEvent = true
            vm.storageDropTargeting = true
            vm.appleIntelligenceDropTargeting = false
        }
    }

    private func route(for info: DropInfo) -> DropRoute {
        let shareMaxX = tileSide
        let appleMinX = shareMaxX + tileSpacing
        let appleMaxX = appleMinX + tileSide

        if info.location.x <= shareMaxX {
            return .share
        }
        if info.location.x >= appleMinX && info.location.x <= appleMaxX {
            return .appleIntelligence
        }
        return .storage
    }

    private enum DropRoute {
        case share
        case appleIntelligence
        case storage
    }
}
