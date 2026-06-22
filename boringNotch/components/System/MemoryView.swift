import SwiftUI

struct MemoryView: View {
    @ObservedObject private var memory = MemoryManager.shared

    private var phaseColor: Color { memory.pressureLevel.color }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top row: big number + pressure pill
            HStack(alignment: .firstTextBaseline) {
                Text(usedTotalLabel)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                pressurePill
            }

            // Sparkline
            sparkline
                .frame(height: 44)

            // Stacked bar
            stackedBar
                .frame(height: 8)

            // Legend
            legend
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Used / Total label

    private var usedTotalLabel: String {
        let used = memory.wiredBytes + memory.activeBytes + memory.compressedBytes
        return "\(bytesToGB(used)) / \(bytesToGB(memory.totalBytes)) GB"
    }

    private func bytesToGB(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        return String(format: "%.1f", gb)
    }

    // MARK: - Pressure pill

    private var pressurePill: some View {
        let icon: String
        switch memory.pressureLevel {
        case .normal:   icon = "circle.fill"
        case .warning:  icon = "exclamationmark.triangle.fill"
        case .critical: icon = "xmark.circle.fill"
        }
        return Label(memory.pressureLevel.label, systemImage: icon)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(phaseColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(phaseColor.opacity(0.18)))
    }

    // MARK: - Sparkline

    private var sparkline: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let pts = memory.history
            guard pts.count >= 2 else {
                return AnyView(Color.clear)
            }

            let xStep = w / CGFloat(pts.count - 1)

            var linePath = Path()
            var fillPath = Path()

            for (i, val) in pts.enumerated() {
                let x = CGFloat(i) * xStep
                let y = h - CGFloat(val) * h
                if i == 0 {
                    linePath.move(to: CGPoint(x: x, y: y))
                    fillPath.move(to: CGPoint(x: x, y: h))
                    fillPath.addLine(to: CGPoint(x: x, y: y))
                } else {
                    linePath.addLine(to: CGPoint(x: x, y: y))
                    fillPath.addLine(to: CGPoint(x: x, y: y))
                }
            }

            // Close fill path at bottom
            let lastX = CGFloat(pts.count - 1) * xStep
            fillPath.addLine(to: CGPoint(x: lastX, y: h))
            fillPath.closeSubpath()

            return AnyView(
                ZStack {
                    fillPath
                        .fill(
                            LinearGradient(
                                colors: [phaseColor.opacity(0.25), phaseColor.opacity(0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    linePath
                        .stroke(phaseColor.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                }
            )
        }
    }

    // MARK: - Stacked bar

    private var stackedBar: some View {
        GeometryReader { geo in
            let total = Double(memory.totalBytes)
            guard total > 0 else { return AnyView(Color.clear) }

            let wiredFrac  = Double(memory.wiredBytes)      / total
            let activeFrac = Double(memory.activeBytes)     / total
            let compFrac   = Double(memory.compressedBytes) / total
            let freeFrac   = Double(memory.freeBytes)       / total

            let w = geo.size.width
            var x: CGFloat = 0

            func segW(_ frac: Double) -> CGFloat { CGFloat(frac) * w }

            return AnyView(
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.08))

                    HStack(spacing: 0) {
                        Rectangle().fill(Color.orange)
                            .frame(width: segW(wiredFrac))
                        Rectangle().fill(Color.blue)
                            .frame(width: segW(activeFrac))
                        Rectangle().fill(Color.purple)
                            .frame(width: segW(compFrac))
                        Rectangle().fill(Color.white.opacity(0.15))
                            .frame(width: segW(freeFrac))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .frame(width: w)
                }
                .frame(width: w)
                .onAppear { _ = x } // suppress unused warning
            )
        }
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 10) {
            legendItem(color: .orange,               label: "Wired")
            legendItem(color: .blue,                 label: "Active")
            legendItem(color: .purple,               label: "Compressed")
            legendItem(color: .white.opacity(0.35),  label: "Free")
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundColor(.white.opacity(0.55))
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
        }
    }
}
