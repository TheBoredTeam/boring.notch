// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

import SwiftUI

/// The sole owner of collapsed-activity geometry. Activities supply their two
/// content regions without spacers for the camera cutout or notch padding.
///
/// Each region is measured at its ideal width, allocated an equal share of the
/// available window width, and clipped independently. Content can fade or
/// resize without ever crossing the center safe area. The equal allocations
/// also keep the physical cutout centered for one-sided activities.
struct NotchActivityHost<Leading: View, Trailing: View>: View {
    let contentID: AnyHashable
    let safeAreaWidth: CGFloat
    let height: CGFloat
    let maximumWidth: CGFloat
    let clearance: CGFloat
    let onWidthChange: (CGFloat) -> Void
    private let leading: Leading
    private let trailing: Trailing

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var idealWidths = ActivitySideWidths()

    init(
        contentID: AnyHashable,
        safeAreaWidth: CGFloat,
        height: CGFloat,
        maximumWidth: CGFloat,
        clearance: CGFloat = 8,
        onWidthChange: @escaping (CGFloat) -> Void = { _ in },
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.contentID = contentID
        self.safeAreaWidth = safeAreaWidth
        self.height = height
        self.maximumWidth = maximumWidth
        self.clearance = clearance
        self.onWidthChange = onWidthChange
        self.leading = leading()
        self.trailing = trailing()
    }

    private var metrics: NotchActivityLayoutMetrics {
        NotchActivityLayoutMetrics(
            safeAreaWidth: safeAreaWidth,
            height: height,
            maximumWidth: maximumWidth,
            clearance: clearance,
            leadingWidth: idealWidths.leading,
            trailingWidth: idealWidths.trailing
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            region(.leading, alignment: .leading, content: leading)

            Color.clear
                .frame(width: metrics.protectedWidth, height: metrics.height)
                .accessibilityHidden(true)
                .allowsHitTesting(false)

            region(.trailing, alignment: .trailing, content: trailing)
        }
        .fixedSize()
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: ActivityHostWidthKey.self,
                    value: geometry.size.width
                )
            }
        }
        .onPreferenceChange(ActivityIdealWidthsKey.self) { measurements in
            // An outgoing view remains alive during its transition. Only the
            // selected activity may update the current layout measurement.
            guard let leading = measurements[ActivityRegionKey(id: contentID, side: .leading)],
                  let trailing = measurements[ActivityRegionKey(id: contentID, side: .trailing)]
            else { return }
            let next = ActivitySideWidths(leading: leading, trailing: trailing)
            if next != idealWidths { idealWidths = next }
        }
        .onPreferenceChange(ActivityHostWidthKey.self, perform: onWidthChange)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: metrics.sideWidth)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: contentID)
        .transaction { transaction in
            // An ancestor may animate its selection or layout too. Removing
            // that inherited transaction is necessary for Reduce Motion.
            if reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func region<Content: View>(
        _ side: ActivitySide,
        alignment: Alignment,
        content: Content
    ) -> some View {
        ZStack(alignment: alignment) {
            // The inner stack supplies a measurable zero-width region even
            // for EmptyView, without rendering a hidden duplicate provider.
            ZStack { content }
                .fixedSize(horizontal: true, vertical: false)
                .frame(height: metrics.height)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ActivityIdealWidthsKey.self,
                            value: [ActivityRegionKey(id: contentID, side: side): geometry.size.width]
                        )
                    }
                }
                .id(contentID)
                .transition(.opacity)
        }
        .frame(width: metrics.sideWidth, height: metrics.height, alignment: alignment)
        .clipped()
        .contentShape(Rectangle())
    }
}

private struct ActivitySideWidths: Equatable {
    var leading: CGFloat = 0
    var trailing: CGFloat = 0
}

private enum ActivitySide: Hashable {
    case leading
    case trailing
}

private struct ActivityRegionKey: Hashable {
    let id: AnyHashable
    let side: ActivitySide
}

private struct ActivityIdealWidthsKey: PreferenceKey {
    static var defaultValue: [ActivityRegionKey: CGFloat] { [:] }

    static func reduce(value: inout [ActivityRegionKey: CGFloat], nextValue: () -> [ActivityRegionKey: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: max)
    }
}

private struct ActivityHostWidthKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
