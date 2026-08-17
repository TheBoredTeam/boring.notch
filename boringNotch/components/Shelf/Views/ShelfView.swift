//
//  ShelfItemView.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-24.
//

import SwiftUI
import AppKit
import Defaults

struct ShelfView: View {
    @EnvironmentObject var vm: BoringViewModel
    @StateObject var tvm = ShelfStateViewModel.shared
    @StateObject var selection = ShelfSelectionModel.shared
    @StateObject private var quickLookService = QuickLookService()
    private let spacing: CGFloat = 8
    @State private var isHoveringPanel = false

    var body: some View {
        HStack(spacing: 12) {
            FileShareView()
                .aspectRatio(1, contentMode: .fit)
                .environmentObject(vm)
            panel
                .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
                    handleDrop(providers: providers)
                }
        }
        // Bind Quick Look to shelf selection
        .onChange(of: selection.selectedIDs) {
            updateQuickLookSelection()
        }
        .quickLookPresenter(using: quickLookService)
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !selection.isDragging else { return false }
        vm.dropEvent = true
        ShelfStateViewModel.shared.load(providers)
        return true
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
                vm.dragDetectorTargeting
                    ? Color.accentColor.opacity(0.9)
                    : Color.white.opacity(0.1),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10])
            )
            .overlay {
                content
                    .padding()
            }
            .overlay(alignment: .topTrailing) {
                removalButton
                    .padding(6)
                    .opacity(showRemovalButton ? 1 : 0)
                    .animation(.easeInOut(duration: 0.12), value: showRemovalButton)
            }
            .transaction { transaction in
                transaction.animation = vm.animation
            }
            .contentShape(Rectangle())
            .onTapGesture { selection.clear() }
            .onHover { hovering in
                isHoveringPanel = hovering
            }
    }

    private var selectionCount: Int {
        selection.selectedItems(in: tvm.items).count
    }

    /// Stays visible whenever there is a selection, since the button is then the only way to
    /// remove exactly those items. With no selection it keeps out of the way until hover: the
    /// panel is only as wide as the open notch, so a permanent control here would sit over
    /// the last item's tile.
    private var showRemovalButton: Bool {
        !tvm.isEmpty && (isHoveringPanel || selectionCount > 0)
    }

    /// Scoped to the selection when there is one, and to the whole shelf otherwise, so the
    /// visible control never removes more than the user just asked for.
    private var removalButton: some View {
        let count = selectionCount
        let isSelectionScoped = count > 0
        let title = isSelectionScoped ? "Remove Selected (\(count))" : "Clear All"

        return Button {
            if isSelectionScoped {
                let selected = selection.selectedItems(in: tvm.items)
                selection.clear()
                tvm.remove(selected)
            } else {
                selection.clear()
                tvm.removeAll()
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "trash")
                Text(title)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.black.opacity(0.65)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(Text(title))
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
                    LazyHStack(spacing: spacing) {
                        ForEach(Defaults[.reverseShelfOrdering] ? tvm.items.reversed() : tvm.items) { item in
                            ShelfItemView(item: item)
                                .environmentObject(quickLookService)
                        }
                    }
                }
                .padding(-spacing)
                .scrollIndicators(.never)
                .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
                    handleDrop(providers: providers)
                }
            }
        }
        .onAppear {
            ShelfStateViewModel.shared.cleanupInvalidItems()
        }
    }
}
