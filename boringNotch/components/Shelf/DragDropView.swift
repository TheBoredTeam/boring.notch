//
//  DragDropView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 2024. 10. 19..
//

import SwiftUI
import AppKit

class DragDropView: NSView {
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

struct DragDropViewRepresentable: NSViewRepresentable {
    @Binding var isTargeted: Bool
    var onDrop: () -> Void
    
    func makeNSView(context: Context) -> DragDropView {
        let view = DragDropView()
        view.onDragEntered = { isTargeted = true }
        view.onDragExited = { isTargeted = false }
        view.onDrop = onDrop
        
        view.autoresizingMask = [.width, .height]
        
        return view
    }
    
    func updateNSView(_ nsView: DragDropView, context: Context) {}
}
