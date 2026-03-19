//
//  DockItemView.swift
//  boringNotch
//
//  Created by Nahel-b on 19/03/2026.


import Kingfisher
import SwiftUI
struct DockItemCell: View {
    let item: DockItem
    let itemSize: CGFloat
    let showDockLabels: Bool

    @State private var isHover = false

    var body: some View {
        HStack {
            if item.imageURL == nil  || item.imageURL == URL(string: "") {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.clear )
                    .frame(width: itemSize, height: itemSize)
                    
                    .overlay(content: {
                        Image(systemName: "app.dashed")
                            .resizable()
                            .scaledToFill()
                            .frame(width: itemSize*0.95, height: itemSize*0.95)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .opacity(0.5)
                    })
            } else {
                
                KFImage(item.imageURL)
                    .placeholder {
                        ProgressView()
                    }
                    .onFailure { error in
                        print("Image failed:", error)
                    }
                    .resizable()
                    .scaledToFill()
                    .frame(width: itemSize, height: itemSize)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .scaleEffect(isHover ? 1.2 : 1)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHover)
                    .onHover { hover in
                        isHover = hover
                    }
            }
            if showDockLabels {
                Text(item.name)
                    .font(.system(size: 10, weight: .medium))
            }
        }
    }
}


