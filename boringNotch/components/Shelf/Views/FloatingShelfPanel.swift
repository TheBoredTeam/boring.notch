//
//  FloatingShelfPanel.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class FloatingShelfDropModel: ObservableObject {
    @Published var isTargeted = false
    @Published var acceptedCount: Int?
}

@MainActor
final class FloatingShelfPanel: NSPanel {
    let dropModel = FloatingShelfDropModel()
    private let dropView = FloatingShelfDropView(frame: .zero)

    var onPerformDrop: ((NSPasteboard) -> Bool)?

    init() {
        let size = FloatingShelfPlacement.panelSize
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configureWindow()
        installContent()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func resetAppearance() {
        dropModel.isTargeted = false
        dropModel.acceptedCount = nil
    }

    private func configureWindow() {
        isFloatingPanel = true
        isOpaque = false
        hasShadow = true
        backgroundColor = .clear
        isMovable = false
        hidesOnDeactivate = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
    }

    private func installContent() {
        let container = NSView(frame: NSRect(origin: .zero, size: FloatingShelfPlacement.panelSize))
        let chrome = NSHostingView(rootView: FloatingShelfChrome(model: dropModel))
        chrome.translatesAutoresizingMaskIntoConstraints = false
        dropView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(chrome)
        container.addSubview(dropView)
        pin(chrome, to: container)
        pin(dropView, to: container)
        contentView = container

        dropView.model = dropModel
        dropView.onDrop = { [weak self] pasteboard in
            self?.onPerformDrop?(pasteboard) ?? false
        }
    }

    private func pin(_ view: NSView, to container: NSView) {
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
    }
}

private struct FloatingShelfChrome: View {
    @ObservedObject var model: FloatingShelfDropModel

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.black.opacity(0.78))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        model.isTargeted ? Color.accentColor.opacity(0.9) : Color.white.opacity(0.28),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [8])
                    )
            )
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: model.acceptedCount == nil ? "tray.and.arrow.down" : "checkmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.title2)
                    Text(label)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.medium)
                }
                .foregroundStyle(.white)
            }
            .padding(4)
    }

    private var label: String {
        if model.acceptedCount != nil {
            return "Added to shelf"
        }
        return "Drop files here"
    }
}

private final class FloatingShelfDropView: NSView {
    weak var model: FloatingShelfDropModel?
    var onDrop: ((NSPasteboard) -> Bool)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([
            .fileURL,
            .URL,
            .string,
            NSPasteboard.PasteboardType(UTType.plainText.identifier),
            NSPasteboard.PasteboardType(UTType.data.identifier)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        model?.isTargeted = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        model?.isTargeted = false
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        model?.isTargeted = false
        return onDrop?(sender.draggingPasteboard) ?? false
    }
}
