import SwiftUI

struct IdleNotchFaceView: View {
    let displayClosedNotchHeight: CGFloat

    var body: some View {
        let faceScale = min(1, displayClosedNotchHeight / 30)

        MinimalFaceFeatures(
            height: 24 * faceScale,
            width: 30 * faceScale
        )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.leading, 20)
    }
}
