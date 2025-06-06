//
//  PanGesture.swift
//  boringNotch
//
//  Created by Richard Kunkli on 21/08/2024.
//

import SwiftUI
import AppKit

extension View {
    func panGesture(direction: PanDirection, action: @escaping (CGFloat, NSEvent.Phase) -> Bool?) -> some View {
        background(
            PanGestureView(direction: direction, action: action)
                .frame(maxWidth: 0, maxHeight: 0)
        )
    }
}

struct PanGestureView: NSViewRepresentable {
    let direction: PanDirection
    let action: (CGFloat, NSEvent.Phase) -> Bool?

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
        let action: (CGFloat, NSEvent.Phase) -> Bool?
        
        var accumulatedScrollDeltaX: CGFloat = 0
        var accumulatedScrollDeltaY: CGFloat = 0
        
        init(direction: PanDirection, action: @escaping (CGFloat, NSEvent.Phase) -> Bool?) {
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

                /// If the action returns with `true`, resset accumulatedScrolDeltas
                func handle() {
                    if direction == .left || direction == .right {
                        if action(abs(accumulatedScrollDeltaX), event.phase) ?? false == true {
                            accumulatedScrollDeltaX = 0
                            accumulatedScrollDeltaY = 0
                        }
                    } else {
                        if action(abs(accumulatedScrollDeltaY), event.phase) ?? false == true {
                            accumulatedScrollDeltaX = 0
                            accumulatedScrollDeltaY = 0
                        }
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
