// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

import AppKit
import SwiftUI

/// Native views cross an Objective-C/AppKit boundary. The plugin may implement
/// them in SwiftUI, AppKit, or another language without linking the host module.
struct ExtensionNotchActivity: NotchLiveActivity {
    let value: ExtensionActivityDescriptor
    let runtime: ExtensionRuntime

    var descriptor: LiveActivityDescriptor { value.hostDescriptor(namespace: runtime.manifest.id) }

    func leading(context: LiveActivityViewContext) -> some View { region(0, context: context) }
    func trailing(context: LiveActivityViewContext) -> some View { region(1, context: context) }

    private func region(_ region: Int32, context: LiveActivityViewContext) -> some View {
        ExtensionActivityRegion(runtime: runtime, activityID: value.id, region: region, displayID: context.displayID)
            .id(ExtensionActivityRegionID(runtime: ObjectIdentifier(runtime), activity: value.id,
                                          region: region, display: context.displayID))
            .frame(maxWidth: context.maximumSideWidth, maxHeight: context.height)
            .accessibilityLabel(value.label)
    }
}

private struct ExtensionActivityRegionID: Hashable {
    let runtime: ObjectIdentifier
    let activity: String
    let region: Int32
    let display: String?
}

private struct ExtensionActivityRegion: NSViewControllerRepresentable {
    let runtime: ExtensionRuntime
    let activityID: String
    let region: Int32
    let displayID: String?

    func makeNSViewController(context: Context) -> NSViewController {
        if let controller = runtime.activityController(id: activityID, region: region, displayID: displayID) {
            return controller
        }
        let empty = NSViewController()
        empty.view = NSView(frame: .zero)
        return empty
    }

    func updateNSViewController(_ controller: NSViewController, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, nsViewController controller: NSViewController, context: Context) -> CGSize? {
        let preferred = controller.preferredContentSize
        let fitted = controller.view.fittingSize
        let width = preferred.width > 0 ? preferred.width : fitted.width
        let height = preferred.height > 0 ? preferred.height : fitted.height
        return CGSize(width: width.isFinite ? max(0, min(width, proposal.width ?? width)) : 0,
                      height: height.isFinite ? max(0, min(height, proposal.height ?? height)) : 0)
    }
}
