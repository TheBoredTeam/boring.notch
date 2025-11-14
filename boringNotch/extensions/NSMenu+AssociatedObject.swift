//
//  NSMenu+AssociatedObject.swift
//  boringNotch
//
//  Created by Alexander on 2025-10-05.
//

import AppKit

private final class MenuActionBox: NSObject {
    let target: AnyObject
    init(target: AnyObject) { self.target = target }
}

extension NSMenu {
    // Each NSMenu instance can store one retained target
    private static let retainedAction = AssociatedObject<MenuActionBox>()

    func retainActionTarget(_ target: AnyObject) {
        NSMenu.retainedAction[self] = MenuActionBox(target: target)
    }
}
