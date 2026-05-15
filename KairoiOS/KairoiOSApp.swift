//
//  KairoiOSApp.swift
//  KairoiOS — companion app entry point
//
//  The companion app is intentionally minimal — it acts as a paired
//  presence indicator for Kairo on the user's Mac, surfaces recent
//  assistant interactions, and (most importantly) hosts the Live
//  Activity so the Dynamic Island can show Kairo's state on the
//  user's phone.
//

import SwiftUI

@main
struct KairoiOSApp: App {
    var body: some Scene {
        WindowGroup {
            CompanionRootView()
                .preferredColorScheme(.dark)
        }
    }
}
