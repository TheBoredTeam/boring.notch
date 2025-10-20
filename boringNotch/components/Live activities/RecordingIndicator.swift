//
//  RecordingIndicator.swift
//  boringNotchApp
//
// Created by Hariharan Mudaliar on 20/11/2025
//
//  Created for screen recording detection feature
//  Displays a red pulsing dot when screen recording is active

import SwiftUI

struct RecordingIndicator: View {
    @ObservedObject var recordingManager = ScreenRecordingManager.shared
    @State private var isPulsing = false
    
    // MARK: - Configuration
    private let indicatorSize: CGFloat = 6
    private let glowSize: CGFloat = 2
    private let animationDuration: Double = 0.8
    
    var body: some View {
        Group {
            if recordingManager.isRecording {
                ZStack {
                    // Glow effect
                    Circle()
                        .fill(Color.red.opacity(0.3))
                        .frame(width: indicatorSize + glowSize * 2, height: indicatorSize + glowSize * 2)
                        .blur(radius: glowSize)
                        .scaleEffect(isPulsing ? 1.2 : 1.0)
                    
                    // Main indicator dot
                    Circle()
                        .fill(Color.red)
                        .frame(width: indicatorSize, height: indicatorSize)
                        .opacity(isPulsing ? 1.0 : 0.6)
                }
                .onAppear {
                    startPulsingAnimation()
                }
                .onDisappear {
                    stopPulsingAnimation()
                }
                .transition(.asymmetric(
                    insertion: .scale.combined(with: .opacity),
                    removal: .scale.combined(with: .opacity)
                ))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: recordingManager.isRecording)
    }
    
    // MARK: - Private Methods
    
    private func startPulsingAnimation() {
        isPulsing = false
        withAnimation(.easeInOut(duration: animationDuration).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
    }
    
    private func stopPulsingAnimation() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isPulsing = false
        }
    }
}

// MARK: - Preview

struct RecordingIndicator_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Recording state preview
            VStack {
                Text("Recording Active")
                    .font(.caption)
                RecordingIndicator()
                    .onAppear {
                        ScreenRecordingManager.shared.isRecording = true
                    }
            }
            .padding()
            .background(Color.black)
            .previewDisplayName("Recording Active")
            
            // Non-recording state preview
            VStack {
                Text("Not Recording")
                    .font(.caption)
                RecordingIndicator()
                    .onAppear {
                        ScreenRecordingManager.shared.isRecording = false
                    }
            }
            .padding()
            .background(Color.black)
            .previewDisplayName("Not Recording")
        }
    }
}

// MARK: - Alternative Indicator Styles

struct RecordingIndicatorLarge: View {
    @ObservedObject var recordingManager = ScreenRecordingManager.shared
    @State private var isPulsing = false
    
    private let indicatorSize: CGFloat = 10
    private let glowSize: CGFloat = 3
    
    var body: some View {
        Group {
            if recordingManager.isRecording {
                ZStack {
                    // Outer glow
                    Circle()
                        .fill(Color.red.opacity(0.2))
                        .frame(width: indicatorSize + glowSize * 4, height: indicatorSize + glowSize * 4)
                        .blur(radius: glowSize)
                        .scaleEffect(isPulsing ? 1.3 : 1.0)
                    
                    // Inner glow
                    Circle()
                        .fill(Color.red.opacity(0.4))
                        .frame(width: indicatorSize + glowSize * 2, height: indicatorSize + glowSize * 2)
                        .blur(radius: glowSize / 2)
                        .scaleEffect(isPulsing ? 1.1 : 1.0)
                    
                    // Main indicator
                    Circle()
                        .fill(Color.red)
                        .frame(width: indicatorSize, height: indicatorSize)
                        .opacity(isPulsing ? 1.0 : 0.7)
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        isPulsing = true
                    }
                }
                .transition(.asymmetric(
                    insertion: .scale.combined(with: .opacity),
                    removal: .scale.combined(with: .opacity)
                ))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: recordingManager.isRecording)
    }
}

// MARK: - Subtle Indicator for Closed State

struct RecordingIndicatorSubtle: View {
    @ObservedObject var recordingManager = ScreenRecordingManager.shared
    @State private var opacity: Double = 0.5
    
    var body: some View {
        Group {
            if recordingManager.isRecording {
                Circle()
                    .fill(Color.red)
                    .frame(width: 4, height: 4)
                    .opacity(opacity)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                            opacity = 1.0
                        }
                    }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: recordingManager.isRecording)
    }
}