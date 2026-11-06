//
//  LiquidGlassAvailability.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//
//  Everything Liquid Glass needs from the private CoreAnimation API is probed
//  here, once, so the rest of the app only ever asks a Bool.
//

import AppKit
import Foundation

enum LiquidGlassAvailability {
    /// True when the host can render the refraction backdrop: macOS 26 or newer
    /// and every private CoreAnimation symbol the backdrop is built from.
    static let isSupported: Bool = {
        guard #available(macOS 26.0, *) else { return false }

        guard NSClassFromString("CABackdropLayer") != nil,
              NSClassFromString("CASDFLayer") != nil,
              NSClassFromString("CASDFElementLayer") != nil,
              NSClassFromString("CASDFOutputEffect") != nil
        else { return false }

        // `CAFilter` itself is loadable on older systems too, so the filter type
        // is what proves the glass pipeline is actually there.
        guard let filterClass = NSClassFromString("CAFilter") as AnyObject as? NSObjectProtocol,
              filterClass.perform(NSSelectorFromString("filterWithType:"), with: "glassBackground") != nil
        else { return false }

        return true
    }()
}
