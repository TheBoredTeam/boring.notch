// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

import SwiftUI

/// The locked window has no route to ContentView, its expanded workspace, or
/// desktop providers. A publisher must opt into this surface for each activity.
@MainActor
struct LockedLiveActivityView: View {
    @ObservedObject var center: LiveActivityCenter
    let displayID: String
    let safeAreaWidth: CGFloat
    let height: CGFloat
    let maximumWidth: CGFloat
    let showsEmptyShape: Bool

    private let outerInset: CGFloat = 12
    private let cameraClearance: CGFloat = 8

    private var protectedWidth: CGFloat { safeAreaWidth + 2 * cameraClearance }
    private var hostMaximumWidth: CGFloat { max(0, maximumWidth - 2 * outerInset) }

    private var selectedActivity: AnyNotchLiveActivity? {
        let context = LiveActivityContext(displayID: displayID, surface: .lockScreen)
        return center.service.snapshot(in: context).selectedID.flatMap { center.activity(for: $0) }
    }

    var body: some View {
        Group {
            if center.session.canPresentOnLockScreen {
                if let activity = selectedActivity {
                    let context = LiveActivityViewContext(
                        displayID: displayID, height: height,
                        maximumSideWidth: max(0, (hostMaximumWidth - protectedWidth) / 2),
                        surface: .lockScreen
                    )
                    NotchActivityHost(contentID: activity.descriptor.id,
                                      safeAreaWidth: safeAreaWidth, height: height,
                                      maximumWidth: hostMaximumWidth, clearance: cameraClearance) {
                        activity.leading(context: context)
                    } trailing: {
                        activity.trailing(context: context)
                    }
                    // The surface owns outer breathing room as well as the
                    // host's camera clearance; providers never add either.
                    .padding(.horizontal, outerInset)
                    .background(.black, in: shape)
                } else if showsEmptyShape {
                    shape.fill(.black).frame(width: protectedWidth + 2 * outerInset, height: height)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 12,
                               bottomTrailingRadius: 12, topTrailingRadius: 0)
    }
}
