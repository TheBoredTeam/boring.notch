//
//  ClipboardTile.swift
//  boringNotch
//
//  Updated by Mustafa Ramadan on 28/6/2025 & Created by Alessandro Gravagno on 24/04/25.
//

import SwiftUI
import AppKit


struct ClipboardTile: View {
    var text: String
    var bundleID: String
    @State private var isCopied: Bool = false
    @State private var isHovering: Bool = false
    
    init(text: String, bundleID: String) {
        self.text = text
        self.bundleID = bundleID
    }
    
    var body: some View {
        Rectangle()
            .fill(.white.opacity(isHovering ? 0.5 : 0.4))
            .opacity(isHovering ? 0.3 : 0.2)
            .overlay(
                clipboardLabel
                    .frame(maxWidth: .infinity, alignment: .leading)
            )
            .frame(width: 170, height: 55)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isHovering = hovering
                    }
                }
            .onTapGesture {
                ClipboardMonitor.CopyFromApp(text)
                isCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    isCopied = false
                }
            }
    }
    
    private var clipboardLabel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
                .truncationMode(.tail)
                .font(.system(size: 10, weight: .regular, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 30, alignment: .top)
                .padding(.horizontal, 5)
                .padding(.top,3)

            Spacer(minLength: 2)

            HStack(alignment: .center) {
                ZStack {
                    clipboardIconBackground
                    AppIcon(for: bundleID)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                        .opacity(0.85)
                }
                .padding(.leading, 4)

                Spacer()

                Image(systemName: isCopied ? "checkmark" : "clipboard")
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.trailing, 6)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
            }
            .padding(.bottom, 2)
        }
        .contentShape(Rectangle())
        .frame(maxHeight: .infinity, alignment: .top)
    }
    
    private var clipboardIconBackground: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .background(
                AppIcon(for: bundleID)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            )
            .scaleEffect(x: 1.3, y: 3.4)
            .rotationEffect(.degrees(90))
            .blur(radius:40)
    }
}

#Preview {
    HStack{
        ClipboardTile(text: "Copia 1 Copia 1 Copia 1 Copia 1 .frame(height: 18)", bundleID: "com.apple.Notes")
        ClipboardTile(text: "Copia 2", bundleID: "com.spotify.client")
        ClipboardTile(text: "Copia 3", bundleID: "com.apple.music")
    }
    
}
