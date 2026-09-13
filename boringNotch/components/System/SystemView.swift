import SwiftUI

struct SystemView: View {
    @State private var segment: String = "Memory"
    @Namespace private var segAnim
    private let segments: [(name: String, icon: String)] = [
        ("Memory", "memorychip.fill"),
        ("Ports", "network")
    ]

    var body: some View {
        HStack(spacing: 0) {
            // Left sidebar: animated segment picker.
            VStack(spacing: 6) {
                ForEach(segments, id: \.name) { seg in
                    segButton(seg.name, icon: seg.icon)
                }
                Spacer()
            }
            .frame(width: 78)
            .padding(.vertical, 10)

            Divider().frame(maxHeight: .infinity).opacity(0.12)

            // Main content
            Group {
                if segment == "Memory" { MemoryView() }
                else if segment == "Ports" { PortsView() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func segButton(_ name: String, icon: String) -> some View {
        let active = segment == name
        return Button {
            withAnimation(.snappy(duration: 0.25)) { segment = name }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(name)
                    .font(.system(size: 10, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundColor(active ? .black : .white.opacity(0.6))
            .padding(.horizontal, 10)
            .frame(width: 70, height: 26)
            .background(
                ZStack {
                    if active {
                        Capsule().fill(Color.white.opacity(0.9))
                            .matchedGeometryEffect(id: "segpill", in: segAnim)
                    } else {
                        Capsule().fill(Color.white.opacity(0.08))
                    }
                }
            )
        }
        .buttonStyle(SystemSegPress())
    }
}

private struct SystemSegPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}
