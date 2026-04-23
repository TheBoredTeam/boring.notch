//
//  ClipboardHistoryManager.swift
//  boringNotch
//
//  Created on 2026-04-13.
//

import AppKit
import Combine
import Foundation

class ClipboardHistoryManager: ObservableObject {
    static let shared = ClipboardHistoryManager()

    @Published var items: [ClipboardItem] = []

    private let maxItems = 5
    private let pollInterval: TimeInterval = 0.5
    private var lastChangeCount: Int
    private var timer: Timer?
    private var skipNextChange: Bool = false

    private init() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func startMonitoring() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.checkForChanges()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func checkForChanges() {
        let currentChangeCount = NSPasteboard.general.changeCount
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount

        if skipNextChange {
            skipNextChange = false
            return
        }

        captureClipboard()
    }

    private func captureClipboard() {
        let pasteboard = NSPasteboard.general

        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let url = fileURLs.first {
            addItem(.fileURL(url))
            return
        }

        if let image = NSImage(pasteboard: pasteboard) {
            addItem(.image(image))
            return
        }

        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            addItem(.text(string))
            return
        }
    }

    private func addItem(_ kind: ClipboardItemKind) {
        let item = ClipboardItem(kind: kind, timestamp: Date())

        // Remove duplicate if same content already exists
        items.removeAll { existing in
            existing.kind == item.kind
        }

        items.insert(item, at: 0)

        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
    }

    func copyToClipboard(_ item: ClipboardItem) {
        skipNextChange = true
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.kind {
        case .text(let string):
            pasteboard.setString(string, forType: .string)
        case .image(let image):
            if let tiffData = image.tiffRepresentation {
                pasteboard.setData(tiffData, forType: .tiff)
            }
        case .fileURL(let url):
            pasteboard.writeObjects([url as NSURL])
        }
    }

    func copyAndPaste(_ item: ClipboardItem) {
        copyToClipboard(item)

        // Small delay to let the pasteboard update, then simulate Cmd+V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.simulatePaste()
        }
    }

    private func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)  // 0x09 = 'V'
        keyDown?.flags = .maskCommand

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    func clearHistory() {
        items.removeAll()
    }
}
