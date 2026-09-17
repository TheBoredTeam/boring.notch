//
//  CalendarDayScrollView.swift
//  boringNotch
//

import AppKit
import SwiftUI

/// A frozen day gutter beside a shared two-axis timeline viewport.
struct CalendarDayScrollView<Labels: View, Content: View>: NSViewRepresentable {
    let days: [CalendarDayStackGeometry.Day]
    let visibleRanges: [DateInterval]
    let targetDay: Date
    let targetTime: Date
    let focusCurrentTime: Bool
    let resetID: Int
    var pointsPerHour = CalendarDayStackGeometry.pointsPerHour
    let onScroll: (CalendarDayStackGeometry.Position, Bool) -> Void
    let onPositionApplied: (Int) -> Void
    @ViewBuilder let labels: () -> Labels
    @ViewBuilder let content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> CalendarDayScrollContainer {
        let container = CalendarDayScrollContainer()
        let coordinator = context.coordinator
        let hosting = NSHostingView(rootView: content())
        let labelHosting = NSHostingView(rootView: labels())
        hosting.isFlipped = true
        labelHosting.isFlipped = true
        hosting.sizingOptions = []
        labelHosting.sizingOptions = []
        container.scrollView.documentView = hosting
        container.gutter.documentView = labelHosting
        coordinator.hosting = hosting
        coordinator.labelHosting = labelHosting
        container.scrollView.contentView.postsBoundsChangedNotifications = true
        coordinator.observer = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: container.scrollView.contentView, queue: .main
        ) { [weak container, weak coordinator] _ in
            guard let container, let coordinator else { return }
            let origin = container.scrollView.contentView.bounds.origin
            container.gutter.scroll(to: NSPoint(x: 0, y: origin.y))
            let vertical = abs(origin.y - coordinator.lastOrigin.y) > 0.1
            let moved = vertical || abs(origin.x - coordinator.lastOrigin.x) > 0.1
            coordinator.lastOrigin = origin
            guard moved, !coordinator.updating, !container.scrollView.applyingPendingPosition,
                  let position = CalendarDayStackGeometry.position(at: origin.y, in: coordinator.days) else { return }
            coordinator.onScroll?(position, vertical)
        }
        return container
    }

    func updateNSView(_ container: CalendarDayScrollContainer, context: Context) {
        let coordinator = context.coordinator
        let origin = container.scrollView.requestedOrigin
        let previousPosition = CalendarDayStackGeometry.position(at: origin.y, in: coordinator.days)
        let oldRange = previousPosition.flatMap { coordinator.ranges[$0.day] }
        let changedScale = coordinator.pointsPerHour != pointsPerHour
        let anchorOffset = changedScale ? container.scrollView.contentView.bounds.width / 2 : 0
        let previousTime = oldRange.map {
            min($0.end, $0.start.addingTimeInterval((origin.x + anchorOffset) / coordinator.pointsPerHour * 3600))
        }
        let ranges = Dictionary(uniqueKeysWithValues: zip(days, visibleRanges).map { ($0.0.id, $0.1) })
        let changedWindow = coordinator.days.first?.id != days.first?.id
        let changedRanges = coordinator.ranges != ranges
        let shouldReset = coordinator.resetID != resetID
        if shouldReset { coordinator.pendingResetID = resetID }
        coordinator.updating = true
        coordinator.days = days
        coordinator.ranges = ranges
        coordinator.pointsPerHour = pointsPerHour
        coordinator.resetID = resetID
        coordinator.onScroll = onScroll
        coordinator.onPositionApplied = onPositionApplied
        let width = (visibleRanges.map(\.duration).max() ?? 12 * 3600) / 3600 * pointsPerHour
        let height = CalendarDayStackGeometry.documentHeight(for: days)
        coordinator.hosting?.rootView = content()
        coordinator.hosting?.frame = NSRect(x: 0, y: 0, width: width, height: height)
        coordinator.labelHosting?.rootView = labels()
        coordinator.labelHosting?.frame = NSRect(x: 0, y: 0, width: 68, height: height)
        if changedWindow || changedRanges || changedScale || shouldReset {
            let position = shouldReset ? CalendarDayStackGeometry.Position(day: targetDay, intraDayOffset: 0)
                : previousPosition ?? .init(day: targetDay, intraDayOffset: 0)
            let time = shouldReset ? targetTime : previousTime ?? targetTime
            let range = ranges[position.day] ?? visibleRanges.first
            let x = (range.map { CalendarTimelineGeometry.position(of: time, in: $0, pointsPerHour: pointsPerHour) } ?? 0)
                - (shouldReset ? (focusCurrentTime ? pointsPerHour : 0) : anchorOffset)
            let beforeHours = shouldReset && time >= position.day && range.map { time < $0.start } == true
            let y = CalendarDayStackGeometry.offset(of: position, in: days) - (beforeHours ? CalendarDayStackGeometry.rowSpacing : 0)
            let appliedID = coordinator.pendingResetID
            container.scrollView.move(to: NSPoint(x: x, y: y)) {
                guard let appliedID else { return }
                DispatchQueue.main.async { [weak coordinator] in
                    guard let coordinator, coordinator.pendingResetID == appliedID, coordinator.resetID == appliedID else { return }
                    coordinator.pendingResetID = nil
                    coordinator.onPositionApplied?(appliedID)
                }
            }
        }
        let updatedOrigin = container.scrollView.contentView.bounds.origin
        container.gutter.scroll(to: NSPoint(x: 0, y: updatedOrigin.y))
        coordinator.lastOrigin = updatedOrigin
        coordinator.updating = false
    }

    static func dismantleNSView(_ container: CalendarDayScrollContainer, coordinator: Coordinator) {
        if let observer = coordinator.observer { NotificationCenter.default.removeObserver(observer) }
        coordinator.observer = nil
        coordinator.onScroll = nil
        coordinator.onPositionApplied = nil
        container.scrollView.documentView = nil
        container.gutter.documentView = nil
    }

    final class Coordinator {
        var hosting: NSHostingView<Content>?
        var labelHosting: NSHostingView<Labels>?
        var days: [CalendarDayStackGeometry.Day] = []
        var ranges: [Date: DateInterval] = [:]
        var pointsPerHour = CalendarDayStackGeometry.pointsPerHour
        var resetID: Int?
        var pendingResetID: Int?
        var observer: NSObjectProtocol?
        var updating = false
        var lastOrigin = NSPoint.zero
        var onScroll: ((CalendarDayStackGeometry.Position, Bool) -> Void)?
        var onPositionApplied: ((Int) -> Void)?
    }
}

final class CalendarDayScrollContainer: NSView {
    let scrollView = CalendarDayNativeScrollView()
    let gutter = NSClipView()
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller?.controlSize = .small
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none
        gutter.drawsBackground = false
        addSubview(gutter)
        addSubview(scrollView)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        gutter.frame = NSRect(x: 0, y: 0, width: 68, height: bounds.height)
        scrollView.frame = NSRect(x: 76, y: 0, width: max(0, bounds.width - 76), height: bounds.height)
        scrollView.needsLayout = true
        scrollView.layoutSubtreeIfNeeded()
    }

    override func scrollWheel(with event: NSEvent) { scrollView.scrollWheel(with: event) }
}

final class CalendarDayNativeScrollView: NSScrollView {
    private var pendingPosition: NSPoint?
    private var pendingCompletion: (() -> Void)?
    private(set) var applyingPendingPosition = false
    var requestedOrigin: NSPoint { pendingPosition ?? contentView.bounds.origin }

    override func layout() {
        super.layout()
        if let point = pendingPosition, contentView.bounds.width > 0, contentView.bounds.height > 0 {
            applyingPendingPosition = true
            move(to: point, onApplied: pendingCompletion)
            applyingPendingPosition = false
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
        // Each axis keeps its job: days travel vertically, hours horizontally.
        move(to: NSPoint(x: contentView.bounds.minX - event.scrollingDeltaX * scale,
                         y: contentView.bounds.minY - event.scrollingDeltaY * scale))
    }

    func move(to point: NSPoint, onApplied: (() -> Void)? = nil) {
        guard contentView.bounds.width > 0, contentView.bounds.height > 0 else {
            pendingPosition = point
            pendingCompletion = onApplied
            return
        }
        pendingPosition = nil
        pendingCompletion = nil
        let size = documentView?.frame.size ?? .zero
        let maximumX = max(0, size.width - contentView.bounds.width)
        let maximumY = max(0, size.height - contentView.bounds.height)
        contentView.scroll(to: NSPoint(x: min(max(0, point.x), maximumX), y: min(max(0, point.y), maximumY)))
        reflectScrolledClipView(contentView)
        onApplied?()
    }
}
