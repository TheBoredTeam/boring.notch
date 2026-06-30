import AppKit
import CoreText
import SwiftUI

enum MinitapBrand {
    static let appName = "minitap"
    static let settingsWindowTitle = "minitap Settings"
    static let settingsWindowIdentifier = "MinitapSettingsWindow"
    static let bundleIdentifier = "ai.minitap.minitap"
    static let helperBundleIdentifier = "ai.minitap.minitap.MinitapXPCHelper"
    static let urlScheme = "minitap"
    static let spotifyRedirectURI = "minitap://spotify-auth/callback"
    static let keychainSpotifyService = "ai.minitap.minitap.spotify-ad-dampener"
    static let websiteURL = URL(string: "https://www.minitap.ai")!
    static let sparkleFeedURL = "https://www.minitap.ai/appcast.xml"

    enum Colors {
        static let primary = Color(red: 18 / 255, green: 16 / 255, blue: 93 / 255)
        static let secondary = Color(red: 217 / 255, green: 214 / 255, blue: 234 / 255)
        static let accent = Color(red: 106 / 255, green: 90 / 255, blue: 224 / 255)
        static let background = Color(red: 249 / 255, green: 249 / 255, blue: 255 / 255)
        static let textPrimary = Color(red: 75 / 255, green: 75 / 255, blue: 77 / 255)
        static let border = Color(red: 231 / 255, green: 230 / 255, blue: 242 / 255)

        static let nsAccent = NSColor(
            calibratedRed: 106 / 255,
            green: 90 / 255,
            blue: 224 / 255,
            alpha: 1
        )
    }

    enum Fonts {
        static let headingName = "ClashDisplay-Variable"
        static let bodyName = "Archivo"
        static let monoName = "GeistMono-Regular"

        static func registerBundledFonts(bundle: Bundle = .main) {
            [
                "Archivo.ttf",
                "GeistMono.ttf",
                "ClashDisplay-Variable.ttf"
            ].forEach { fileName in
                guard let url = bundle.url(forResource: fileName, withExtension: nil) else { return }
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }

        static func heading(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
            Font.custom(headingName, size: size).weight(weight)
        }

        static func body(size: CGFloat = 11, weight: Font.Weight = .regular) -> Font {
            Font.custom(bodyName, size: size).weight(weight)
        }

        static func mono(size: CGFloat = 11, weight: Font.Weight = .regular) -> Font {
            Font.custom(monoName, size: size).weight(weight)
        }
    }
}
