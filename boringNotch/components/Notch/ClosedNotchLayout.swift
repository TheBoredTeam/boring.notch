import SwiftUI

struct ClosedNotchLayout<Leading: View, Trailing: View>: View {
    let metrics: ClosedNotchLayoutMetrics

    private let leading: Leading
    private let trailing: Trailing

    init(
        metrics: ClosedNotchLayoutMetrics,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.metrics = metrics
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(
                    width: metrics.leadingWidth,
                    height: metrics.height,
                    alignment: .trailing
                )

            Color.clear
                .frame(
                    width: metrics.leadingExclusionMargin
                        + metrics.exclusionWidth
                        + metrics.trailingExclusionMargin,
                    height: metrics.height
                )

            trailing
                .frame(
                    width: metrics.trailingWidth,
                    height: metrics.height,
                    alignment: .leading
                )
        }
        .frame(width: metrics.totalWidth, height: metrics.height)
    }
}
