//
//  NotchClipboardView.swift
//  boringNotch
//
//  Created by Alessandro Gravagno on 23/04/25.
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
        ScrollView(.horizontal){
            LazyHGrid(rows: gridRows, spacing: 20)  {
                ForEach(clipboardMonitor.data.reversed(), id: \.self) { item in
                    ClipboardTile(text: item.text, bundleID: item.bundleID)
                }
            }
        }
    }
}

#Preview {
    NotchClipboardView(clipboardMonitor: ClipboardMonitor())
}
