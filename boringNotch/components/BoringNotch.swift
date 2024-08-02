//
//  BoringNotch.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 02/08/24.
//

import SwiftUI

struct BoringNotch: View {
    let onHover: () -> Void
    @State private var isExpanded = false
    @StateObject private var musicManager = MusicManager()
    
    var body: some View {
        ZStack {
            BottomRoundedRectangle(
                radius: 12)
            .fill(Color.black)
            .frame(width: isExpanded ? 500 : 290, height: isExpanded ? 200: 40)
            .animation(.spring(), value: isExpanded)
            
            HStack {
                Image(systemName: musicManager.albumArt)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundColor(.white)
                
                if isExpanded {
                    VStack(alignment: .leading) {
                        Text(musicManager.songTitle)
                            .font(.caption)
                            .foregroundColor(.white)
                        Text(musicManager.artistName)
                            .font(.caption2)
                            .foregroundColor(.gray)
                        HStack(spacing: 15) {
                            Button(action: {
                                musicManager.previousTrack()
                            }) {
                                Image(systemName: "backward.fill")
                                    .foregroundColor(.white)
                            }
                            Button(action: {
                                musicManager.togglePlayPause()
                            }) {
                                Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                                    .foregroundColor(.white)
                            }
                            Button(action: {
                                musicManager.nextTrack()
                            }) {
                                Image(systemName: "forward.fill")
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .transition(.opacity)
                }
                
                Spacer()
                
                MusicVisualizer()
                    .frame(width: 30)
            }.frame(width: isExpanded ? 480 : 280)
                .padding(.horizontal, 10)
        }
        .onHover { hovering in
            withAnimation(.spring()) {
                isExpanded = hovering
                onHover()
            }
        }
    }
}
