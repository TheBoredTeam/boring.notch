import SwiftUI

struct CameraWallView: View {
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: Kairo.Radius.md, style: .continuous)
                        .fill(Kairo.Palette.surfaceHi)
                        .aspectRatio(16/9, contentMode: .fit)
                        .overlay(Text("Cam \(i+1)").font(.caption).foregroundColor(Kairo.Palette.textDim))
                }
            }.padding(16)
        }
    }
}
