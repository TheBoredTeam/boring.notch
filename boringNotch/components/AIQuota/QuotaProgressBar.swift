//
//  QuotaProgressBar.swift
//  boringNotch
//

import SwiftUI

struct QuotaProgressBar: View {
    let utilization: Double

    private var progress: CGFloat {
        CGFloat(min(max(utilization, 0), 100) / 100)
    }

    private var progressColor: Color {
        switch utilization {
        case ..<50:
            return .green
        case ..<80:
            return .yellow
        default:
            return .red
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(progressColor)
                    .frame(width: geometry.size.width * progress)
            }
        }
        .frame(height: 6)
    }
}
