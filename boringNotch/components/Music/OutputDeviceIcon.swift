import SwiftUI

struct OutputDeviceIcon: View {
    let outputDevice: String
    let namespace: Namespace.ID

    var iconName: String {
        let lower = outputDevice.lowercased()

        // 1. AirPods Models
        if lower.contains("airpods") && lower.contains("pro") {
            return "airpodspro"
        } else if lower.contains("airpods") && lower.contains("max") {
            return "airpodsmax"
        } else if lower.contains("airpods") {
            return "airpods"
        }

        // 2. Built-In Speakers on Apple Devices
        if lower.contains("macbook") && lower.contains("speaker") {
            return "laptopcomputer"
        } else if lower.contains("imac") && lower.contains("speaker") {
            return "desktopcomputer"
        } else if lower.contains("studio display") || lower.contains("apple studio") {
            return "display"
        } else if lower.contains("built-in") && lower.contains("speaker") {
            return "speaker.fill"
        }

        // 3. External Audio Devices
        if lower.contains("headphones") {
            return "headphones"
        } else if lower.contains("speaker") {
            return "speaker.wave.3.fill"
        } else if lower.contains("display") || lower.contains("hdmi") || lower.contains("tv") {
            return "display"
        }

        // 4. Catch-All / Default
        return "hifispeaker.fill"
    }

    var isBuiltIn: Bool {
//        outputDevice.lowercased().contains("built-in")
        return false
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .resizable()
                .scaledToFit()
                .frame(width: 33, height: 33)
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

#Preview{
    @Namespace var ns

    Grid() {
                  OutputDeviceIcon(outputDevice: "Harsh’s AirPods Max", namespace: ns)
                  OutputDeviceIcon(outputDevice: "My AirPods Pro", namespace: ns)
                  
                  OutputDeviceIcon(outputDevice: "My AirPods", namespace: ns)
                  OutputDeviceIcon(outputDevice: "MacBook Pro Speakers", namespace: ns)
                  OutputDeviceIcon(outputDevice: "iMac Built-In Speakers", namespace: ns)
                  OutputDeviceIcon(outputDevice: "Studio Display", namespace: ns)
                  OutputDeviceIcon(outputDevice: "JBL External Speaker", namespace: ns)
                  OutputDeviceIcon(outputDevice: "Sony Headphones", namespace: ns)
                  OutputDeviceIcon(outputDevice: "HDMI Output", namespace: ns)
                  OutputDeviceIcon(outputDevice: "Unknown Output", namespace: ns)
              }
              .padding()
          }
