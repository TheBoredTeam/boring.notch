//
//  RecordingLiveActivity.swift
//  boringNotchApp
//
// Created by Hariharan Mudaliar on 20/11/2025
//
//  Created for screen recording live activity
//

import SwiftUI
import Defaults

struct RecordingLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var recordingManager = ScreenRecordingManager.shared
    @State private var isHovering: Bool = false
    @State private var gestureProgress: CGFloat = 0
    @State private var isExpanded: Bool = false
    
    var body: some View {
        HStack(spacing: 0) {
            // Left - Red circle with animation
            Color.clear
                .background {
                    if isExpanded {
                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.red.opacity(0.15))
                                
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 10, height: 10)
                                    .modifier(PulsingModifier())
                            }
                            .frame(width: vm.effectiveClosedNotchHeight - 12, height: vm.effectiveClosedNotchHeight - 12)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                }
                .frame(width: isExpanded ? max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12) + gestureProgress / 2) : 0, height: vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12))
            
            // Center - Black fill
            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + (isHovering ? 8 : 0))
            
            // Right - Empty for symmetry with animation
            Color.clear
                .frame(width: isExpanded ? max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12) + gestureProgress / 2) : 0, height: vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12))
        }
        .frame(height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0))
        .onAppear {
            withAnimation(.smooth(duration: 0.4)) {
                isExpanded = true
            }
        }
        .onChange(of: recordingManager.isRecording) { _, newValue in
            if !newValue {
                withAnimation(.smooth(duration: 0.4)) {
                    isExpanded = false
                }
            } else {
                withAnimation(.smooth(duration: 0.4)) {
                    isExpanded = true
                }
            }
        }
    }
}

// Pulsing animation modifier for recording indicator
// Note: Also used by PrivacyLiveActivity
struct PulsingModifier: ViewModifier {
    @State private var isPulsing = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.2 : 1.0)
            .opacity(isPulsing ? 0.7 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}
