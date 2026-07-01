//
//  TeleprompterFont.swift
//  boringNotch
//
//  Registers the bundled Inter font and vends the two weights the teleprompter
//  uses. Inter isn't a system face, so we register the .otf files (shipped in
//  this folder) with Core Text before referencing them by PostScript name.
//

import SwiftUI
import CoreText

enum TeleprompterFont {
    /// PostScript names of the bundled faces.
    private static let bodyName = "Inter-Medium"
    private static let emphasisName = "Inter-Bold"

    private static var didRegister = false

    /// Register the bundled Inter faces once. Safe to call repeatedly.
    static func registerIfNeeded() {
        guard !didRegister else { return }
        didRegister = true
        for file in ["Inter-Medium", "Inter-Bold"] {
            if let url = Bundle.main.url(forResource: file, withExtension: "otf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    static func body(size: CGFloat) -> Font {
        .custom(bodyName, size: size)
    }

    static func emphasis(size: CGFloat) -> Font {
        .custom(emphasisName, size: size)
    }
}
