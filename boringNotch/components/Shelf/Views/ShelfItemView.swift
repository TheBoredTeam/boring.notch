//
//  ShelfItemView.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-24.
//

import SwiftUI

struct ShelfItemView: View {
    let item: ShelfItem
    let quickLookService: QuickLookService
    let dropInteraction: DropInteractionState
    @StateObject private var viewModel: ShelfItemViewModel
    @State private var selectionState: ShelfItemSelectionState
    @State private var debouncedDropTarget = false

    private var isSelected: Bool { selectionState.isSelected }

    private var highlight: HighlightPresentation {
        if debouncedDropTarget {
            HighlightPresentation(
                fill: Color.accentColor.opacity(0.25),
                stroke: Color.accentColor.opacity(0.9),
                lineWidth: 3
            )
        } else if isSelected {
            HighlightPresentation(
                fill: Color.accentColor.opacity(0.15),
                stroke: Color.accentColor.opacity(0.8),
                lineWidth: 2
            )
        } else {
            HighlightPresentation(fill: .clear, stroke: .clear, lineWidth: 1)
        }
    }
    
    init(
        item: ShelfItem,
        quickLookService: QuickLookService,
        dropInteraction: DropInteractionState
    ) {
        self.item = item
        self.quickLookService = quickLookService
        self.dropInteraction = dropInteraction
        _viewModel = StateObject(wrappedValue: ShelfItemViewModel(item: item))
        _selectionState = State(initialValue: ShelfSelectionModel.shared.state(for: item.id))
    }

    var body: some View {
        itemContent
        .onChange(of: viewModel.isDropTargeted) { _, targeted in
            dropInteraction.dragDetectorTargeting = targeted
        }
        .task(id: viewModel.isDropTargeted) {
            let targeted = viewModel.isDropTargeted
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            debouncedDropTarget = targeted
        }
        .task(id: item.id) {
            await viewModel.loadThumbnail()
        }
        .onAppear {
            viewModel.onQuickLookRequest = { urls in
                quickLookService.show(urls: urls, selectFirst: true)
            }
        }
    }

    // MARK: - View Components

    private var itemContent: some View {
        VStack(alignment: .center, spacing: 2) {
            iconView
            textView
        }
        .frame(width: 105)
        .padding(.vertical, 10)
        .padding(.horizontal, 5)
        .background(backgroundView)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.1), value: debouncedDropTarget)
        .animation(.easeInOut(duration: 0.1), value: isSelected)
        .overlay {
            ShelfItemInteractionView(
                item: item,
                viewModel: viewModel,
                dragPreview: {
                    DragPreviewView(
                        thumbnail: viewModel.thumbnail ?? item.icon,
                        displayName: item.displayName
                    )
                },
                onPrimaryClick: viewModel.handleClick,
                onContextClick: viewModel.handleRightClick
            )
        }
    }

    private var iconView: some View {
        Image(nsImage: viewModel.thumbnail ?? item.icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)
    }

    private var textView: some View {
        Text(item.displayName)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
            .lineLimit(2)
            .truncationMode(.middle)
            .multilineTextAlignment(.center)
            .frame(height: 30, alignment: .top)
    }

    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(highlight.fill)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        highlight.stroke,
                        lineWidth: highlight.lineWidth
                    )
            )
    }

    private struct HighlightPresentation {
        let fill: Color
        let stroke: Color
        let lineWidth: CGFloat
    }
}
