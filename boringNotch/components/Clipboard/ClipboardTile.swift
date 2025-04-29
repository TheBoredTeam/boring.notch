//
//  ClipboardElement.swift
//  boringNotch
//
//  Created by Alessandro Gravagno on 24/04/25.
//
import SwiftUI
import AppKit


struct ClipboardTile: View {
    var text: String
    var bundleID: String
    @State private var isCopied: Bool = false
    
    init(text: String, bundleID: String) {
        self.text = text
        self.bundleID = bundleID
    }
    
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.4))
            .opacity(0.2)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                clipboardLabel
                    .frame(maxWidth: .infinity, alignment: .leading)
            )
            .frame(width: 140, height: 120)
            .contentShape(Rectangle())
            .onTapGesture {
                let clipboard = NSPasteboard.general
                clipboard.clearContents()
                clipboard.setString(text, forType: .string)
                isCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isCopied = false
                    }
                }
            }
    }
    
    private var clipboardLabel: some View {
        VStack(alignment: .leading, spacing: 12){
            Text(text)
                .foregroundStyle(.white)
                .padding(.top, 10)
                .padding(.horizontal, 5)
                .lineLimit(3)
                .padding(.leading, 5)
            Spacer()
            HStack(alignment: .center) {
                ZStack{
                    //clipboardIconBackground
                    AppIcon(for: bundleID)
                        .opacity(0.5)
                }
                .padding(.bottom, 10)
                .padding(.leading, 8)
                Spacer()
                if isCopied {
                    Text("Copied!")
                        .padding(.trailing)
                        .padding(.bottom, 5)
                        .foregroundStyle(.white.opacity(0.5))
                }
                
                
            }
        }
        //.foregroundStyle(.gray)
        .font(.system(.headline, design: .rounded))
        .contentShape(Rectangle())
    }
    
    private var clipboardIconBackground: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .background(
                AppIcon(for: bundleID)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            )
            .clipped()
            .scaleEffect(x: 1.3, y: 1.4)
            .rotationEffect(.degrees(92))
            .blur(radius: 35)
    }
}

#Preview {
    HStack{
        ClipboardTile(text: "Copia 1", bundleID: "com.apple.Notes")
        ClipboardTile(text: "Copia 2", bundleID: "com.spotify.client")
    }
    
}
