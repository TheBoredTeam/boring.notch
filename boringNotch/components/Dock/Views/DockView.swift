//
//  ShelfItemView.swift
//  boringNotch
//
//  Created by Nahel-b on 19/03/2026.

import SwiftUI
import AppKit
import Kingfisher
import Defaults


struct DockView: View {
    @EnvironmentObject var vm: BoringViewModel
    
    @Default(.dockItems) var dockItems
    @Default(.showDockLabels) var showDockLabels
    @Default(.maxItemsPerColumn) var maxItemsPerColumn
    
    let spacing: CGFloat = 6
    
    var itemSize: CGFloat {
        let totalSpacing = spacing * CGFloat(maxItemsPerColumn - 1)
        return round((150 - totalSpacing) / CGFloat(maxItemsPerColumn))
    }
    
    var columns: [[DockItem]] {
        let items = Defaults[.dockItems]
        var result: [[DockItem]] = []
        var currentIndex = 0
        
        while currentIndex < items.count {
            let endIndex = min(currentIndex + maxItemsPerColumn, items.count)
            let column = Array(items[currentIndex..<endIndex])
            result.append(column)
            currentIndex += maxItemsPerColumn
        }
        print("Computed columns: \(result.count), with items: \(result.map { $0.count })")
        return result
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(0..<columns.count, id: \.self) { columnIndex in
                VStack(alignment: .leading, spacing: spacing) {
                    ForEach(columns[columnIndex], id: \.id) { item in
                        DockItemCell(
                            item: item,
                            itemSize: itemSize,
                            showDockLabels: showDockLabels
                        )
                        .onTapGesture {
                            NSWorkspace.shared.open(item.url)
                        }
                    }
                }
                if dockItems.isEmpty {
                    Text("No items in Dock")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}
