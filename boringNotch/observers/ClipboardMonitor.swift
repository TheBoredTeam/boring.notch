//
//  ClipboardMonitor.swift
//  boringNotch
//
//  Created by Alessandro Gravagno on 28/04/25.
//

// TODO: fix duplicate, se copio una stringa di un app mentre mi trovo in un altra app viene creato un duplicato

import SwiftUI
import AppKit

class ClipboardMonitor: ObservableObject{
    @Published var data: Array<ClipboardData> = []

    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount

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
            lastChangeCount = pasteboard.changeCount

            if let copiedText = pasteboard.string(forType: .string),
               let activeApp = NSWorkspace.shared.frontmostApplication {
                
                let bundleID = activeApp.bundleIdentifier ?? "sconosciuto"
                
                DispatchQueue.main.async {
                    self.addToClipboard(element: ClipboardData(text: copiedText, bundleID: bundleID))
                }
            }
        }
    }
    
    private func addToClipboard(element: ClipboardData){
        if self.data.contains(element){
            self.data.removeAll(where: {$0 == element})
        }
        self.data.append(element)
    }
    
    deinit {
        timer?.invalidate()
    }
}

struct ClipboardData: Hashable {
    var text: String
    var bundleID: String
}
