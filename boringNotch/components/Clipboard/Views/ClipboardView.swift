import SwiftUI
import Defaults

struct ClipboardView: View {
    @ObservedObject private var viewModel: ClipboardStateViewModel = .shared
    @Default(.clipboardGroupByApp) private var groupByApp: Bool
    
    var body: some View {
        Group {
            if viewModel.items.isEmpty {
                ClipboardEmptyState()
            } else {
                if groupByApp {
                    groupedView
                } else {
                    chipGridView
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
    }
    
    @ViewBuilder
    private var chipGridView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(stride(from: 0, to: viewModel.sortedItems().count, by: 2)), id: \.self) { index in
                    VStack(spacing: 8) {
                        // First row of the column
                        ClipboardItemChip(
                            item: viewModel.sortedItems()[index],
                            onTap: { viewModel.copyToClipboard(viewModel.sortedItems()[index]) },
                            onPin: { viewModel.togglePin(viewModel.sortedItems()[index]) },
                            onDelete: { viewModel.remove(viewModel.sortedItems()[index]) }
                        )
                        
                        // Second row of the column (if exists)
                        if index + 1 < viewModel.sortedItems().count {
                            ClipboardItemChip(
                                item: viewModel.sortedItems()[index + 1],
                                onTap: { viewModel.copyToClipboard(viewModel.sortedItems()[index + 1]) },
                                onPin: { viewModel.togglePin(viewModel.sortedItems()[index + 1]) },
                                onDelete: { viewModel.remove(viewModel.sortedItems()[index + 1]) }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }
    
    @ViewBuilder
    private var groupedView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(viewModel.groupedByApp().enumerated()), id: \.element.app) { index, group in
                    ClipboardGroupCard(
                        appName: group.app,
                        bundleId: group.items.first?.sourceApp ?? "",
                        items: group.items,
                        onTap: { item in viewModel.copyToClipboard(item) },
                        onPin: { item in viewModel.togglePin(item) },
                        onDelete: { item in viewModel.remove(item) }
                    )
                    
                    // Vertical divider between groups (not after the last one)
                    if index < viewModel.groupedByApp().count - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.15))
                            .frame(width: 1)
                            .padding(.vertical, 8)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
    }
}
