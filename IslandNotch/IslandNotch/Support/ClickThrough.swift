//  ClickThrough.swift
//  IslandNotch
//
//  Purpose: Enables first-click interaction on non-activating NSPanels (DynamicNotchKit).
//           Without acceptsFirstMouse, macOS swallows the first click on inactive windows.
//  Layer: Support

import AppKit
import SwiftUI

/// Backdrop NSView that accepts first mouse so clicks reach SwiftUI controls immediately.
private final class ClickThroughView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct ClickThroughBackdrop<Content: View>: NSViewRepresentable {
    let content: Content

    func makeNSView(context: Context) -> NSView {
        let backdrop = ClickThroughView()
        backdrop.addSubview(context.coordinator.hostingView)
        context.coordinator.hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            context.coordinator.hostingView.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor),
            context.coordinator.hostingView.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),
            context.coordinator.hostingView.topAnchor.constraint(equalTo: backdrop.topAnchor),
            context.coordinator.hostingView.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor),
        ])
        return backdrop
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.hostingView.rootView = content
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(content: content)
    }

    final class Coordinator {
        let hostingView: NSHostingView<Content>

        init(content: Content) {
            hostingView = NSHostingView(rootView: content)
        }
    }
}

extension View {
    /// Wraps the view so it receives first-click events on non-activating panels.
    func acceptClickThrough() -> some View {
        ClickThroughBackdrop(content: self)
    }
}
