import SwiftUI

struct SceneButton: View {
    let label: String; let icon: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 18))
            Text(label).font(.system(size: 11, weight: .semibold))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: Kairo.Radius.md, style: .continuous)
                .fill(Kairo.Palette.surface)
        )
        .foregroundColor(Kairo.Palette.text)
    }
}
