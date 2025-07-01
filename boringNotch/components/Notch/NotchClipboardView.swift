//
//  NotchClipboardView.swift
//  boringNotch
//
//  Updated by Mustafa Ramadan on 28/6/2025 & Created by Alessandro Gravagno on 23/04/25.
//

import SwiftUI

struct NotchClipboardView : View {
    
    @ObservedObject var clipboardMonitor: ClipboardMonitor
    
    init(clipboardMonitor: ClipboardMonitor) {
        self.clipboardMonitor = clipboardMonitor
    }

    private let gridRows = [
        GridItem(.adaptive(minimum: 200)),
    ]
    
    var body: some View {
        if clipboardMonitor.data.isEmpty {
            Text("Clipboard is empty")
                .foregroundStyle(.white.opacity(0.4))
                .frame(maxWidth: .infinity, maxHeight: 148)
                .font(.system(.title3, design: .rounded))
                
        } else {
            ScrollView{
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 11) {
                    ForEach(clipboardMonitor.data.reversed(), id: \.self) { item in
                        ClipboardTile(text: item.text, bundleID: item.bundleID)
                    }
                }.padding(.horizontal, 12)
            }.scrollIndicators(.never)
        }
    }
}

#Preview {
    NotchClipboardView(clipboardMonitor: ClipboardMonitor())
}
