import SwiftUI

struct OutputDeviceIcon: View {
    let outputDevice: String
    let namespace: Namespace.ID

    var iconName: String {
        let lower = outputDevice.lowercased()
        if lower.contains("airpods") {
            return "airpodspro"
        } else if lower.contains("speaker") {
            return "speaker.wave.3.fill"
        } else if lower.contains("headphones") {
            return "headphones"
        } else if lower.contains("display") || lower.contains("hdmi") {
            return "display"
        } else {
            return "hifispeaker.fill"
        }
    }

    var isBuiltIn: Bool {
        outputDevice.lowercased().contains("built-in")
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
                .padding(.leading, 10)
                .foregroundStyle(.primary)
                .matchedGeometryEffect(id: "icon", in: namespace)

            if !isBuiltIn {
                Text(outputDevice)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.secondary)
                    .matchedGeometryEffect(id: "label", in: namespace)
            }
        }
        .padding(.vertical, 6)
        .padding(.trailing, 12)
        .background(
            isBuiltIn
                ? AnyShapeStyle(Color.clear)
                : AnyShapeStyle(.ultraThinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
