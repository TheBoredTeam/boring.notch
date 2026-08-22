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
    let dropInteraction: DropInteractionState
    let animation: Animation?
    @StateObject var tvm = ShelfStateViewModel.shared

    private let spacing: CGFloat = 8

    private var displayedItems: [ShelfItem] {
        Defaults[.reverseShelfOrdering] ? Array(tvm.items.reversed()) : tvm.items
    }

    var body: some View {
        @Bindable var interaction = dropInteraction

        ShelfQuickLookHost { quickLookService in
            HStack(spacing: 12) {
                FileShareView(dropInteraction: dropInteraction)
                    .aspectRatio(1, contentMode: .fit)
                panel(quickLookService: quickLookService)
                    .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $interaction.dragDetectorTargeting) { providers in
                        handleDrop(providers: providers)
                    }
            }
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !ShelfSelectionModel.shared.isDragging else { return false }
        dropInteraction.dropEvent = true
        tvm.load(providers)
        return true
    }
    
    private func panel(quickLookService: QuickLookService) -> some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(
                dropInteraction.dragDetectorTargeting
                    ? Color.accentColor.opacity(0.9)
                    : Color.white.opacity(0.1),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10])
            )
            // Keep background deselection below item content. Shelf items use
            // AppKit mouse handling and must own clicks within their bounds.
            .contentShape(Rectangle())
            .onTapGesture { ShelfSelectionModel.shared.clear() }
            .overlay {
                content(quickLookService: quickLookService)
                    .padding()
            }
            .transaction { transaction in
                transaction.animation = animation
            }
    }

    private func content(quickLookService: QuickLookService) -> some View {
        @Bindable var interaction = dropInteraction

        return Group {
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
                        ForEach(displayedItems) { item in
                            ShelfItemView(
                                item: item,
                                quickLookService: quickLookService,
                                dropInteraction: dropInteraction
                            )
                        }
                    }
                }
                .padding(-spacing)
                .scrollIndicators(.never)
                .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $interaction.dragDetectorTargeting) { providers in
                    handleDrop(providers: providers)
                }
            }
        }
        .onAppear {
            tvm.cleanupInvalidItems()
        }
    }
}

private struct ShelfQuickLookHost<Content: View>: View {
    @State private var service = QuickLookService()
    @ViewBuilder let content: (QuickLookService) -> Content

    var body: some View {
        content(service)
            .quickLookPresenter(using: service)
    }
}
