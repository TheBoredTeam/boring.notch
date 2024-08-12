//
//  EditPanelView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 12/08/2024.
//

import SwiftUI

struct EditPanelView: View {
    @State var wallpaperPath: URL?
    var body: some View {
        VStack {
            HStack {
                Text("Edit layout")
                    .font(.system(.largeTitle, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Button {
                    exit(0)
                } label: {
                    Label("Close", systemImage: "xmark")
                }
                .controlSize(.extraLarge)
                .buttonStyle(AccessoryBarButtonStyle())
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            ZStack {
                if let wallpaper = NSWorkspace.shared.desktopImageURL(for: NSScreen.main!) {
                    if let wallpaperImage = NSImage(contentsOf: wallpaper) {
                        Image(nsImage: wallpaperImage)
                            .resizable()
                            .scaledToFill()
                            .blur(radius: 30, opaque: true)
                            .clipped()
                    }
                }
                
                Rectangle()
                    .fill(.black.opacity(0.2))
            }
        }
    }
}

#Preview {
    EditPanelView()
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context _: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = NSVisualEffectView.State.active
        visualEffectView.isEmphasized = true
        return visualEffectView
    }
    
    func updateNSView(_ visualEffectView: NSVisualEffectView, context _: Context) {
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
    }
}
