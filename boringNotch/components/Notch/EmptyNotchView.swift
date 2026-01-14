//
//  EmptyNotchView.swift
//  boringNotch
//
//  Created by sleepy on 2026. 01. 14
//

import SwiftUI

struct EmptyNotchView: View {
    @State private var id = UUID()
    
    var body: some View {
        VStack(spacing: 8) {
            HelloAnimation(onFinish: {
                // Restart animation when finished
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    id = UUID()
                }
            })
            .id(id) // Force recreation to restart
            .frame(width: 120, height: 60)
            .scaleEffect(0.6) // Scale down to fit nicely
            
            VStack(spacing: 2) {
                Text("So boring...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text("Enable some extensions")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    EmptyNotchView()
        .preferredColorScheme(.dark)
        .frame(width: 300, height: 150)
}
