//
//  LottieAnimationView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 2024. 10. 29..
//

import SwiftUI
import Lottie
import LottieUI
import Defaults

struct LottieAnimationView: View {
    let state1 = LUStateData(type: .loadedFrom(URL(string: "https://assets9.lottiefiles.com/packages/lf20_mniampqn.json")!), speed: 1.0, loopMode: .loop)
    @Default(.selectedVisualizer) var selectedVisualizer
    var body: some View {
        if selectedVisualizer == nil {
            LottieView(state: state1)
        } else {
            LottieView(
                state: LUStateData(
                    type: .loadedFrom(selectedVisualizer!.url),
                    speed: selectedVisualizer!.speed,
                    loopMode: .loop
                )
            )
        }
    }
}

#Preview {
    LottieAnimationView()
}
