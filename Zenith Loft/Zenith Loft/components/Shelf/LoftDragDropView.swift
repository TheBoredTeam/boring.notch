import SwiftUI
import AppKit

class LoftDragDropView: NSView {
    var onDragEntered: () -> Void = {}
    var onDragExited: () -> Void = {}
    var onDrop: () -> Void = {}
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragEntered()
        return .copy
    }
    
    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragExited()
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDrop()
        return true
    }
}

struct LoftDragDropViewRepresentable: NSViewRepresentable {
    @Binding var isTargeted: Bool
    var onDrop: () -> Void
    
    func makeNSView(context: Context) -> LoftDragDropView {
        let view = LoftDragDropView()
        view.onDragEntered = { isTargeted = true }
        view.onDragExited  = { isTargeted = false }
        view.onDrop        = onDrop
        view.autoresizingMask = [.width, .height]
        return view
    }
    
    func updateNSView(_ nsView: LoftDragDropView, context: Context) {}
}
