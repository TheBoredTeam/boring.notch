//
//  NotificationPanelDetection.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation

public enum NotificationPanelDetection {
    public static let panelWindowSubroles: Set<String> = ["AXNotificationCenterPanel"]
    public static let panelListIdentifier = "AXNotificationListItems"
    public static let panelStackingPrefix = "stack-"
    public static let bannerSubroles: Set<String> = ["AXNotificationCenterBanner", "AXNotificationCenterAlert"]
    private static let subroleAttribute = "AXSubrole"
    private static let identifierAttribute = "AXIdentifier"
    private static let stackingIdentifierAttribute = "AXStackingIdentifier"

    public struct Attributes {
        public let subrole: (String) -> String?
        public let identifier: (String) -> String?
        public let children: () -> [Self]

        public init(
            subrole: @escaping (String) -> String?,
            identifier: @escaping (String) -> String?,
            children: @escaping () -> [Self]
        ) {
            self.subrole = subrole
            self.identifier = identifier
            self.children = children
        }
    }

    public static func isPanelWindow(_ window: Attributes) -> Bool {
        if let subrole = window.subrole(subroleAttribute),
           panelWindowSubroles.contains(subrole) {
            return true
        }
        return containsPanelList(window)
    }

    public static func containsPanelList(_ element: Attributes, depth: Int = 0) -> Bool {
        guard depth < 14 else { return false }
        if element.identifier(identifierAttribute) == panelListIdentifier {
            return true
        }
        if let subrole = element.subrole(subroleAttribute),
           subrole == "AXButton",
           let stackingIdentifier = element.identifier(stackingIdentifierAttribute),
           stackingIdentifier.hasPrefix(panelStackingPrefix) {
            return true
        }
        return element.children().contains { containsPanelList($0, depth: depth + 1) }
    }
}
