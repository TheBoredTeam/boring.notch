//
//  VolumeView.swift
//  boringNotch
//
//  Created by JeanLouis on 22/08/2025.
//

import SwiftUI

struct VolumeView: View {
    @EnvironmentObject var vm: BoringViewModel
    @StateObject private var volume = VolumeManager.shared

    var body: some View {
    let v = volume.isMuted ? 0 : volume.animatedVolume
        HStack(spacing: 10) {
            Image(systemName: volume.isMuted ? "speaker.slash.fill" : iconName)
                .font(.system(size: 16, weight: .bold))
                .frame(width: 28, height: 28)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                    Capsule()
                        .fill(.white)
                        .frame(width: geo.size.width * CGFloat(max(0,min(1,v))))
                        .animation(.easeOut(duration: 0.18), value: v)
                }
            }
            .frame(height: 10)
            Text(label)
                .font(.system(.caption, design: .rounded))
                .monospacedDigit()
                .frame(width: 46, alignment: .trailing)
        }
        .padding(6)
        .frame(width: vm.notchSize.width , height: 28) 
        .background(Color.black)
        .clipShape(.rect(bottomLeadingRadius: 8, bottomTrailingRadius: 8))
        .opacity((volume.shouldShowOverlay) ? 1 : 0)
    }

    private var label: String {
        if volume.isMuted { return "Muet" }
        return "\(Int(volume.animatedVolume * 100))%" }

    private var iconName: String {
        let v = volume.animatedVolume
        if v < 0.01 { return "speaker.slash.fill" }
        if v < 0.33 { return "speaker.wave.1.fill" }
        if v < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill" }
}


#Preview {
    VolumeView()
        .padding()
        .frame(width: 200, alignment: .center, )
        .background(.white)
        .preferredColorScheme(.dark)
        .environmentObject(BoringViewModel())
}
