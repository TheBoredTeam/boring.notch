//
//  ClipboardMonitor.swift
//  boringNotch
//
//  Updated by Mustafa Ramadan on 28/6/2025 & Created by Alessandro Gravagno on 28/04/25.
//

import SwiftUI
import AppKit
import Defaults

class ClipboardMonitor: ObservableObject{
    @Published var data: Array<ClipboardData> = []

    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private static var isInternalCopy = false

    init() {
        if Defaults[.showClipboard] {
            startMonitoring()
        }
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
            
            if ClipboardMonitor.isInternalCopy {
                ClipboardMonitor.isInternalCopy = false
                return
            }

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
        if self.data.contains(element) {
            self.data.removeAll(where: { $0 == element })
        }
        self.data.append(element)
        
        // Keep only the latest 48 clipboard items to avoid memory bloat
        if self.data.count > 48 {
            self.data.removeFirst()
        }
    }
    
    static func CopyFromApp(_ text: String){
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        isInternalCopy = true
        pasteboard.setString(text, forType: .string)
    }
    
    func toggleMonitoring(_ enabled: Bool) {
        if enabled {
            startMonitoring()
        } else {
            timer?.invalidate()
            timer = nil
            data.removeAll()
        }
    }
    
    deinit {
        timer?.invalidate()
    }
}

struct ClipboardData: Hashable {
    var text: String
    var bundleID: String
}
