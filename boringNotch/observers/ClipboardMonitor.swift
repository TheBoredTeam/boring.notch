//
//  ClipboardMonitor.swift
//  boringNotch
//
//  Created by Alessandro Gravagno on 28/04/25.
//

// TODO: fix duplicate when copy clipboard's elements
// TODO: fix "Copied!" string behaviour
// TODO: change UI

import SwiftUI
import AppKit

class ClipboardMonitor: ObservableObject{
    @Published var lastCopiedText: String = ""
    @Published var lastCopiedApp: String = ""
    @Published var data: Array<ClipboardData> = []

    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var elementID: Int = 0

    init() {
        startMonitoring()
    }

    private func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }
    
    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        if pasteboard.changeCount != lastChangeCount {
            self.elementID += 1
            lastChangeCount = pasteboard.changeCount

            if let copiedText = pasteboard.string(forType: .string),
               let activeApp = NSWorkspace.shared.frontmostApplication {
                
                let bundleID = activeApp.bundleIdentifier ?? "sconosciuto"
                
                DispatchQueue.main.async {
                    self.lastCopiedText = copiedText
                    self.lastCopiedApp = bundleID
                    self.data.append(ClipboardData(text: copiedText, bundleID: bundleID, id: self.elementID))
                    
                }
            }
        }
    }
    
    deinit {
        timer?.invalidate()
    }
}

struct ClipboardData: Hashable {
    var text: String
    var bundleID: String
    var id: Int
}
