    //
    //  ProgressIndicator.swift
    //  boringNotch
    //
    //  Created by Harsh Vardhan  Goswami  on 11/08/24.
    //

import Foundation
import SwiftUI

struct CircularProgressView: View {
    let progress: Double
    let color: Color
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    Color.white.opacity(0.2),
                    lineWidth: 6
                )
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    color,
                    // 1
                    style: StrokeStyle(
                        lineWidth: 6,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
        }
    }
}

enum ProgressIndicatorType {
    case circle
    case text
}


    // based on type .circle or .text
struct ProgressIndicator: View {
    var type: ProgressIndicatorType
    var progress: Double
    var color: Color
    
    var body: some View {
        switch type {
            case .circle:
                CircularProgressView(progress: progress, color: color).frame(
                width: 20, height: 20)
            case .text:
                Text("\(Int(progress * 100))%")
        }
    }
}

#Preview {
    ProgressIndicator(type: .circle, progress: 0.8, color: Color.blue).padding()
        .frame(width: 200, height: 200)
}
