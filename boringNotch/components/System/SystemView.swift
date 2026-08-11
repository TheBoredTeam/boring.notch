import SwiftUI

struct SystemView: View {
    @State private var segment: String = "Memory"
    @Namespace private var segAnim
    private let segments: [(name: String, icon: String)] = [
        ("Memory", "memorychip.fill"),
        ("Ports", "network")
    ]

    var body: some View {
        // Same envelope as the other tabs (Projects/Launcher/Note): header row +
        // content within a shared 14 / 10 / 8 padding, top-aligned, no divider —
        // so the System tab occupies the exact same content rectangle.
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(segments, id: \.name) { seg in
                    segButton(seg.name, icon: seg.icon)
                }
                Spacer()
            }

            Group {
                if segment == "Memory" { MemoryView() }
                else if segment == "Ports" { PortsView() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundColor(active ? .black : .white.opacity(0.6))
            .padding(.horizontal, 12)
            .frame(height: 26)
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
