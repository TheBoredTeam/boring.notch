//
//  boringNotchApp.swift
//  boringNotchApp
//
//  Created by Harsh Vardhan  Goswami  on 02/08/24.
//

import SwiftUI

@main
struct boringNotchApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(width: NSScreen.main?.frame.width, height: 60)
                .background(Color.clear)
                .edgesIgnoringSafeArea(.all)
        }
        .windowStyle(HiddenTitleBarWindowStyle())
    }
}
