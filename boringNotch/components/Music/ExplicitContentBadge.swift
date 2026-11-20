//
//  ExplicitContentBadge.swift
//  boringNotch
//
//  Compact parental-advisory "E" badge for the media player,
//  matched to Apple Music / Dynamic Island styling.
//

import SwiftUI

struct ExplicitContentBadge: View {
    /// Overall badge side length.
    var size: CGFloat = 12

    var body: some View {
        Text("E")
            .font(.system(size: size * 0.78, weight: .bold, design: .rounded))
            .foregroundStyle(Color.black.opacity(0.85))
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                    .fill(Color(white: 0.62))
            )
            .accessibilityLabel(Text("Explicit"))
            .accessibilityAddTraits(.isStaticText)
    }
}

#Preview {
    HStack(spacing: 4) {
        Text("Miami")
            .font(.headline)
            .foregroundStyle(.white)
        ExplicitContentBadge()
    }
    .padding()
    .background(Color.black)
}
