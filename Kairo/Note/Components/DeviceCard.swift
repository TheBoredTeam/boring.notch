import SwiftUI

struct DeviceCard: View {
    let name: String; let value: String; let icon: String; let on: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).font(.system(size: 20))
                .foregroundColor(on ? Kairo.Palette.accent : Kairo.Palette.textDim)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 12, weight: .semibold))
                Text(value).font(.system(size: 11)).foregroundColor(Kairo.Palette.textDim)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Kairo.Radius.md, style: .continuous)
                .fill(Kairo.Palette.surface)
        )
    }
}
