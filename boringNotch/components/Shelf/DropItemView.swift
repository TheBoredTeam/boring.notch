//
//  TrayDrop+DropItemView.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/8.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct DropItemView: View {
    let item: TrayDrop.DropItem
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @StateObject var tvm = TrayDrop.shared

    @State var hover = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.clear)
                    .background {
                        Image(nsImage: item.workspacePreviewImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                
                Text(item.fileName)
                    .multilineTextAlignment(.center)
                    .font(.footnote)
                    .foregroundStyle(hover ? .white : .gray)
                    .lineLimit(2)
                    .allowsTightening(true)
            }
            .contentShape(Rectangle())
            .onDrag {
                handleOnDrag(for: item)
            }
            .frame(width: 64, height: 64)
            
            if hover {
                Circle()
                    .fill(.white)
                    .overlay(Image(systemName: "xmark").foregroundStyle(.black).font(.system(size: 7)).fontWeight(.semibold))
                    .frame(width: spacing, height: spacing)
                    .opacity(hover ? 1 : 0) // TODO: Use option key pressed to show delete
                    .scaleEffect(coordinator.optionKeyPressed ? 1 : 0.5)
                    .transition(.blurReplace.combined(with: .scale))
                    .offset(x: spacing / 2, y: -spacing / 2)
                    .onTapGesture { tvm.delete(item.id) }
                    .shadow(color: .black, radius: 3)
            }
        }
        .onHover { hovering in
            withAnimation(.smooth) {
                if hovering {
                    hover.toggle()
                } else {
                    hover.toggle()
                }
            }
        }
    }

    private func handleOnDrag(for item: TrayDrop.DropItem) -> NSItemProvider {
        guard let itemProvider = NSItemProvider(contentsOf: item.storageURL) else {
            return NSItemProvider()
        }
        
        let nameWithoutExtension = (item.fileName as NSString).deletingPathExtension
        itemProvider.suggestedName = nameWithoutExtension
        
        return itemProvider
    }
}
