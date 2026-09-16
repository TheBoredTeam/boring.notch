//
//  ShelfSelectionModel.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-26.
//

import Foundation
import Combine
import Observation

@MainActor
final class ShelfSelectionModel: ObservableObject {
    static let shared = ShelfSelectionModel()

    @Published private(set) var selectedIDs: Set<UUID> = []
    private var itemStates: [UUID: WeakSelectionState] = [:]

    // Anchor for shift-range selection
    private var lastAnchorID: UUID? = nil

    func isSelected(_ id: UUID) -> Bool { selectedIDs.contains(id) }

    func state(for id: UUID) -> ShelfItemSelectionState {
        pruneUnusedItemStates()
        if let state = itemStates[id]?.value {
            return state
        }

        let state = ShelfItemSelectionState(isSelected: selectedIDs.contains(id))
        itemStates[id] = WeakSelectionState(state)
        return state
    }

    var hasSelection: Bool { !selectedIDs.isEmpty }

    var firstSelectedItem: ShelfItem? {
        guard let firstID = selectedIDs.first else { return nil }
        return ShelfStateViewModel.shared.items.first(where: { $0.id == firstID })
    }

    func selectedItems(in allItems: [ShelfItem]) -> [ShelfItem] {
        allItems.filter { selectedIDs.contains($0.id) }
    }

    func selectSingle(_ item: ShelfItem) {
        updateSelection(to: [item.id])
        lastAnchorID = item.id
    }

    func toggle(_ item: ShelfItem) {
        var newSelection = selectedIDs
        if newSelection.contains(item.id) {
            newSelection.remove(item.id)
        } else {
            newSelection.insert(item.id)
        }
        updateSelection(to: newSelection)
        lastAnchorID = item.id
    }

    func shiftSelect(to item: ShelfItem, in allItems: [ShelfItem]) {
        // Determine anchor
        let anchorID = lastAnchorID ?? selectedIDs.first ?? item.id
        guard let startIndex = allItems.firstIndex(where: { $0.id == anchorID }),
              let endIndex = allItems.firstIndex(where: { $0.id == item.id }) else {
            // Fallback to single select if indices not found
            return selectSingle(item)
        }
        let lower = min(startIndex, endIndex)
        let upper = max(startIndex, endIndex)
        let rangeIDs = allItems[lower...upper].map { $0.id }
        updateSelection(to: Set(rangeIDs))
    }

    func clear() {
        updateSelection(to: [])
        lastAnchorID = nil
    }

    private func updateSelection(to newSelection: Set<UUID>) {
        guard newSelection != selectedIDs else { return }

        let changedIDs = selectedIDs.symmetricDifference(newSelection)
        selectedIDs = newSelection

        for id in changedIDs {
            itemStates[id]?.value?.isSelected = newSelection.contains(id)
        }
        pruneUnusedItemStates()
    }

    private func pruneUnusedItemStates() {
        itemStates = itemStates.filter { $0.value.value != nil }
    }

    // Keep anchor sane if items array changed drastically (optional helper)
    func ensureValidAnchor(in allItems: [ShelfItem]) {
        if let anchor = lastAnchorID, !allItems.contains(where: { $0.id == anchor }) {
            lastAnchorID = selectedIDs.first
        }
    }

    @Published private(set) var isDragging: Bool = false

    func beginDrag() {
        isDragging = true
    }

    func endDrag() {
        isDragging = false
    }
}

private final class WeakSelectionState {
    weak var value: ShelfItemSelectionState?

    init(_ value: ShelfItemSelectionState) {
        self.value = value
    }
}

@Observable
@MainActor
final class ShelfItemSelectionState {
    fileprivate(set) var isSelected: Bool

    init(isSelected: Bool) {
        self.isSelected = isSelected
    }
}
