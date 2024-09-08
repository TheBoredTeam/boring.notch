//
//  PanGesture.swift
//  boringNotch
//
//  Created by Richard Kunkli on 21/08/2024.
//

import SwiftUI
import AppKit

extension View {
    func panGesture(direction: PanDirection, action: @escaping (CGFloat, NSEvent.Phase) -> Void) -> some View {
        background(
            PanGestureView(direction: direction, action: action)
                .frame(maxWidth: 0, maxHeight: 0)
        )
    }
}

struct PanGestureView: NSViewRepresentable {
    let direction: PanDirection
    let action: (CGFloat, NSEvent.Phase) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { event in
            if event.window == view.window {
                context.coordinator.handleEvent(event)
            }
            return event
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(direction: direction, action: action)
    }
    
    class Coordinator: NSObject {
        let direction: PanDirection
        let action: (CGFloat, NSEvent.Phase) -> Void
        
        var accumulatedScrollDeltaX: CGFloat = 0
        var accumulatedScrollDeltaY: CGFloat = 0
        
        init(direction: PanDirection, action: @escaping (CGFloat, NSEvent.Phase) -> Void) {
            self.direction = direction
            self.action = action
        }
        
        @objc func handleEvent(_ event: NSEvent) {
            if event.type == .scrollWheel {
                accumulatedScrollDeltaX += event.scrollingDeltaX
                accumulatedScrollDeltaY += event.scrollingDeltaY
                
                switch direction {
                    case .down:
                        if accumulatedScrollDeltaY > 0 {
                            handle()
                        }
                    case .up:
                        if accumulatedScrollDeltaY < 0 {
                            handle()
                        }
                    case .left:
                        if accumulatedScrollDeltaX < 0 {
                            handle()
                        }
                    case .right:
                        if accumulatedScrollDeltaX > 0 {
                            handle()
                        }
                }
                
                func handle() {
                    if (direction == .left || direction == .right) {
                        action(abs(accumulatedScrollDeltaX), event.phase)
                    } else {
                        action(abs(accumulatedScrollDeltaY), event.phase)
                    }
                }
                
                if event.phase == .ended {
                    accumulatedScrollDeltaY = 0
                    accumulatedScrollDeltaX = 0
                }
            }
        }
    }
}

enum PanDirection {
    case left
    case right
    case up
    case down
}
