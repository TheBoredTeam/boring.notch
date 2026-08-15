//
//  LiveActivityStack.swift
//  boringNotch
//
//  A browsable stack of closed-notch live activities, in the spirit of the
//  Dynamic Island / Lock Screen activity stack: the newest activity takes
//  the front, older ones sit behind it, and the user can swipe between them.
//
//  Transient activities (a notification) auto-expire and reveal whatever was
//  underneath (music), so an incoming message interrupts the now-playing
//  display for a beat and then hands it back on its own.
//

import Defaults
import SwiftUI

/// One entry in the closed-notch stack.
///
/// Deliberately excludes the momentary HUDs — volume/brightness OSD and the
/// battery pill. Those are interrupts, not activities: they take over for
/// ~1.5s and aren't something you'd want to swipe back to, which is also how
/// iOS separates them from live activities.
enum LiveActivityItem: Identifiable, Equatable {
    case notification(SystemNotification)
    case music

    var id: String {
        switch self {
        case .notification(let notification): "notification-\(notification.id)"
        case .music: "music"
        }
    }
}

/// Renders the selected activity with the others hinted behind it, and
/// handles swiping between them.
///
/// Takes its content via a closure so callers keep ownership of how each
/// activity draws — `MusicLiveActivity` depends on ContentView's namespace
/// and gesture state, and dragging it out here would be a much larger,
/// riskier change than this feature needs.
struct LiveActivityStack<Content: View>: View {
    let items: [LiveActivityItem]
    @Binding var index: Int
    @ViewBuilder let content: (LiveActivityItem) -> Content

    @State private var dragOffset: CGFloat = 0
    @State private var haptics: Bool = false

    private var clampedIndex: Int { min(max(index, 0), max(items.count - 1, 0)) }

    var body: some View {
        ZStack {
            // No "card behind the card" depth cue here. A full-width shape
            // drawn behind the content is bisected by the black rectangle
            // that masks the physical notch cutout, so it renders as two
            // disembodied lines flanking the notch rather than as a stack.
            // The closed pill has no room for a page-dot row either, so the
            // stack stays discoverable by swiping rather than by ornament.
            if let item = items[safe: clampedIndex] {
                content(item)
                    .id(item.id)
                    .offset(x: dragOffset)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .animation(.smooth(duration: 0.3), value: clampedIndex)
        .animation(.smooth(duration: 0.3), value: items.count)
        .contentShape(Rectangle())
        // minimumDistance keeps taps (open the notch) and the notch's own
        // vertical pan gestures working — this only claims deliberate
        // horizontal drags.
        .gesture(
            DragGesture(minimumDistance: 14)
                .onChanged { value in
                    guard items.count > 1, abs(value.translation.width) > abs(value.translation.height) else { return }
                    dragOffset = value.translation.width * 0.3
                }
                .onEnded { value in
                    dragOffset = 0
                    guard items.count > 1,
                          abs(value.translation.width) > abs(value.translation.height),
                          abs(value.translation.width) > 24
                    else { return }
                    move(by: value.translation.width < 0 ? 1 : -1)
                }
        )
        .sensoryFeedback(.alignment, trigger: haptics)
    }

    private func move(by delta: Int) {
        let next = clampedIndex + delta
        guard items.indices.contains(next) else { return }
        withAnimation(.smooth(duration: 0.3)) { index = next }
        if Defaults[.enableHaptics] { haptics.toggle() }
    }
}

private extension Array {
    /// The stack's contents change out from under the selection (a
    /// notification expires, music stops), so every read is bounds-checked
    /// rather than trusting an index that was valid a frame ago.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
