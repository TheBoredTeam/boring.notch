import AppKit

@main
struct ClipboardSelectionTests {
    static func main() {
        let ids = (0..<4).map { _ in UUID() }
        let frames = Dictionary(uniqueKeysWithValues: ids.enumerated().map { index, id in
            (id, CGRect(x: index * 110, y: 0, width: 100, height: 100))
        })
        var gesture = ClipboardSelectionGesture(start: CGPoint(x: 50, y: 50), itemID: ids[0], selectedIDs: [], additive: false)
        precondition(gesture.selectedIDs == [ids[0]])
        gesture.move(to: CGPoint(x: 52, y: 50), frames: frames)
        precondition(!gesture.hasMoved, "A shaky click must not start a drag")
        gesture.move(to: CGPoint(x: 380, y: 50), frames: frames)
        precondition(gesture.selectedIDs == Set(ids), "Fast movement selects every crossed tile")
        gesture.move(to: CGPoint(x: 380, y: 120), frames: frames)
        precondition(gesture.selectedIDs == Set(ids), "Leaving the grid retains all selected copies")

        var existing = ClipboardSelectionGesture(start: CGPoint(x: 50, y: 50), itemID: ids[0], selectedIDs: [ids[0], ids[2]], additive: false)
        existing.move(to: CGPoint(x: 380, y: 50), frames: frames)
        precondition(existing.startedOnSelection && existing.selectedIDs == [ids[0], ids[2]], "Dragging an existing selection must not collect other cards")
        let additive = ClipboardSelectionGesture(start: .zero, itemID: ids[1], selectedIDs: [ids[0]], additive: true)
        precondition(additive.selectedIDs == [ids[0], ids[1]], "Command/Shift-click adds a card")
        let toggle = ClipboardSelectionGesture(start: .zero, itemID: ids[0], selectedIDs: [ids[0], ids[1]], additive: true)
        precondition(toggle.selectedIDs == [ids[1]], "Command/Shift-click removes a selected card")
        let clear = ClipboardSelectionGesture(start: .zero, itemID: nil, selectedIDs: Set(ids), additive: false)
        precondition(clear.selectedIDs.isEmpty, "Clicking a gap clears selection")
        precondition(existing.originalIDs == [ids[0], ids[2]], "Cancellation can restore the original selection")

        let rectangle = CGRect(x: 20, y: 20, width: 20, height: 20)
        precondition(!ClipboardSelectionGesture.intersects(from: .zero, to: CGPoint(x: 50, y: 5), rectangle: rectangle))
        precondition(ClipboardSelectionGesture.intersects(from: .zero, to: CGPoint(x: 50, y: 50), rectangle: rectangle))
        precondition(ClipboardSelectionGesture.intersects(from: CGPoint(x: 50, y: 50), to: .zero, rectangle: rectangle))
        precondition(ClipboardSelectionGesture.intersects(from: CGPoint(x: 30, y: 0), to: CGPoint(x: 30, y: 80), rectangle: rectangle))
        precondition(!ClipboardSelectionGesture.intersects(from: CGPoint(x: 10, y: 0), to: CGPoint(x: 10, y: 80), rectangle: rectangle))
        print("Clipboard selection: 14 assertions passed.")
    }
}
