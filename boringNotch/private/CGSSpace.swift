//
//  CGSSpace.swift
//  boringNotch
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Original source: https://github.com/avaidyam/Parrot/
// Modified by Alexander on 2024-10-27

import AppKit

/// Small Spaces API wrapper.
public final class CGSSpace {
    private let identifier: CGSSpaceID

    public var windows: Set<NSWindow> = [] {
        didSet {
            let remove = oldValue.subtracting(self.windows)
            let add = self.windows.subtracting(oldValue)

            CGSRemoveWindowsFromSpaces(_CGSDefaultConnection(),
                                       remove.map { $0.windowNumber } as NSArray,
                                       [self.identifier])
            CGSAddWindowsToSpaces(_CGSDefaultConnection(),
                                  add.map { $0.windowNumber } as NSArray,
                                  [self.identifier])
        }
    }

    /// Initialized `CGSSpace`s *MUST* be de-initialized upon app exit!
    public init(level: Int = 0) {
        let flag = 0x1 // this value MUST be 1, otherwise, Finder decides to draw desktop icons
        self.identifier = CGSSpaceCreate(_CGSDefaultConnection(), flag, nil)
        CGSSpaceSetAbsoluteLevel(_CGSDefaultConnection(), self.identifier, level)
        CGSShowSpaces(_CGSDefaultConnection(), [self.identifier])
    }

    deinit {
        CGSHideSpaces(_CGSDefaultConnection(), [self.identifier])
        CGSSpaceDestroy(_CGSDefaultConnection(), self.identifier)
    }
}

// CGSSpace stuff:
private typealias CGSConnectionID = UInt
private typealias CGSSpaceID = UInt64
@_silgen_name("_CGSDefaultConnection")
private func _CGSDefaultConnection() -> CGSConnectionID
@_silgen_name("CGSSpaceCreate")
private func CGSSpaceCreate(_ cid: CGSConnectionID, _ unknown: Int, _ options: NSDictionary?) -> CGSSpaceID
@_silgen_name("CGSSpaceDestroy")
private func CGSSpaceDestroy(_ cid: CGSConnectionID, _ space: CGSSpaceID)
@_silgen_name("CGSSpaceSetAbsoluteLevel")
private func CGSSpaceSetAbsoluteLevel(_ cid: CGSConnectionID, _ space: CGSSpaceID, _ level: Int)
@_silgen_name("CGSAddWindowsToSpaces")
private func CGSAddWindowsToSpaces(_ cid: CGSConnectionID, _ windows: NSArray, _ spaces: NSArray)
@_silgen_name("CGSRemoveWindowsFromSpaces")
private func CGSRemoveWindowsFromSpaces(_ cid: CGSConnectionID, _ windows: NSArray, _ spaces: NSArray)
@_silgen_name("CGSHideSpaces")
private func CGSHideSpaces(_ cid: CGSConnectionID, _ spaces: NSArray)
@_silgen_name("CGSShowSpaces")
private func CGSShowSpaces(_ cid: CGSConnectionID, _ spaces: NSArray)
