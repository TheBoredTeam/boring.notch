//
//  ListItemPopover.swift
//  boringNotch
//
//  Created by Richard Kunkli on 15/09/2024.
//

import SwiftUI

struct ListItemPopover<Content: View>: View {
    let content: () -> Content
    
    @State private var isPresented: Bool = false
    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .controlSize(.regular)
        .popover(isPresented: $isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing, content: {
            content()
                .padding()
        })
    }
}

