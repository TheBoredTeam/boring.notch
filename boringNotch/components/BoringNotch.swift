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
            
            VStack {
                if isExpanded {
                    Spacer()
                }
                HStack {
                    AsyncImage(url: URL(string: "https://i.scdn.co/image/ab67616d0000b2737d37ca425dc0d46cd4f79113")).frame(width: isExpanded ? 80: 20, height:isExpanded ?80: 20).scaledToFit().cornerRadius(4)
                    
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
                                }.tint(.clear)
                                Button(action: {
                                    musicManager.nextTrack()
                                }) {
                                    Image(systemName: "forward.fill")
                                        .foregroundColor(.white)
                                }.tint(.clear)
                            }
                        }
                        .transition(.opacity)
                    }
                    
                    Spacer()
                    
                    MusicVisualizer()
                        .frame(width: 30)
                }.frame(width: isExpanded ? 480 : 280)
                    .padding(.horizontal, 10).padding(.vertical, 20)
            }
        }
        .onHover { hovering in
            withAnimation(.spring()) {
                isExpanded = hovering
                onHover()
            }
        }
    }
}

func onHover(){}

#Preview {
    ContentView(onHover:onHover )
}
