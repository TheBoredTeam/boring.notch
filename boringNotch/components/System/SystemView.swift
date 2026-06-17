import SwiftUI

struct SystemView: View {
    @State private var segment: String = "Memory"
    private let segments = ["Memory", "Ports"]

    var body: some View {
        HStack(spacing: 0) {
            // Left sidebar: segment picker (vertical pill buttons)
            VStack(spacing: 6) {
                ForEach(segments, id: \.self) { seg in
                    Button(seg) { segment = seg }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(segment == seg ? .black : .white.opacity(0.6))
                        .frame(width: 64, height: 26)
                        .background(Capsule().fill(segment == seg ? Color.white.opacity(0.9) : Color.white.opacity(0.08)))
                        .buttonStyle(.plain)
                }
                Spacer()
            }
            .frame(width: 72)
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
}
