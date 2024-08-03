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
    @State var showEmptyState = false
    @StateObject private var musicManager = MusicManager()
    var boringAnimations =  BoringAnimations()
    
    var body: some View {
        ZStack {
            NotchShape(cornerRadius: isExpanded ? 30: 10)
                .fill(Color.black)
                .frame(width: isExpanded ? 500 : 290, height: isExpanded ? 250: 40)
                .animation(.spring(), value: isExpanded)
                .shadow(color: .black.opacity(0.5), radius: 10)
            
            VStack {
                if isExpanded {
                    Spacer()
                    
                }
                
                
                HStack(spacing: 4) {
                    
                    if musicManager.isPlaying  || musicManager.lastUpdated.timeIntervalSinceNow > -10  {
                        
                        Image(nsImage: musicManager.albumArt).frame(width: isExpanded ? 80: 20, height:isExpanded ?80: 20).cornerRadius(isExpanded ?16:4).aspectRatio(contentMode: .fit)
                        // Fit the image within the frame
                    }
                    
                    
                    
                    if isExpanded {
                        if musicManager.isPlaying == true || musicManager.lastUpdated.timeIntervalSinceNow > -10 {
                            VStack(alignment: .leading, spacing: 8) {
                                VStack(alignment: .leading){
                                    Text(musicManager.songTitle)
                                        .font(.caption)
                                        .foregroundColor(.white)
                                    Text(musicManager.artistName)
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                                HStack(spacing: 15) {
                                    Button(action: {
                                        musicManager.previousTrack()
                                    }) {
                                        Image(systemName: "backward.fill")
                                            .foregroundColor(.white).font(.title2)
                                    }.buttonStyle(PlainButtonStyle())
                                    Button(action: {
                                        musicManager.togglePlayPause()
                                    }) {
                                        Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                                            .foregroundColor(.white).font(.title)
                                    }.buttonStyle(PlainButtonStyle())
                                    Button(action: {
                                        musicManager.nextTrack()
                                    }) {
                                        Image(systemName: "forward.fill")
                                            .foregroundColor(.white).font(.title2)
                                    }.buttonStyle(PlainButtonStyle())
                                }
                            }.transition(.blurReplace.animation(.spring(.bouncy(duration: 0.3))))
                        }
                        
                        if musicManager.isPlaying == false && musicManager.lastUpdated.timeIntervalSinceNow < -10 {
                            EmptyStateView(message: "Play some jams, ladies, and watch me shine! New features coming soon! 🎶 🚀")
                        }
                        
                    }
                    
                    Spacer()
                    
                    if musicManager.isPlaying == false && isExpanded == false {
                        
                        MinimalFaceFeatures().transition(.blurReplace.animation(.spring(.bouncy(duration: 0.3))))
                        
                    }
                    
                    if musicManager.isPlaying {
                        
                        MusicVisualizer()
                            .frame(width: 30).padding(.horizontal, isExpanded ? 8 : 2)
                        
                    }
                    
                    
                    
                }.frame(width: isExpanded ? 440 : 270)
                    .padding(.horizontal, 10).padding(.vertical, isExpanded ? 10: 20)
                
                
                //                if isExpanded {
                //                    HStack {
                //                        BuyMeCoffee().transition(.blurReplace.animation(.spring(.bouncy(duration: 0.3))))
                //
                //                    }
                //                }
            }
        }
        .onHover { hovering in
            withAnimation(boringAnimations.animation) {
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
