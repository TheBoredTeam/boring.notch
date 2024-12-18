//
//  TipStore.swift
//  boringNotch
//
//  Created by Richard Kunkli on 15/09/2024.
//

import SwiftUI
import TipKit

struct HUDsTip: Tip {
    var title: Text {
        Text("tips.hud.title")
    }
    
    
    var message: Text? {
        Text("tips.hud.message")
    }
    
    
    var image: Image? {
        AppIcon(for: "theboringteam.boringNotch")
    }
    
    var actions: [Action] {
        Action {
            Text("common.more")
        }
    }
}

struct CBTip: Tip {
    var title: Text {
        Text("clipboard_mgr.title")
    }
    
    
    var message: Text? {
        Text("clipboard_mgr.message")
    }
    
    
    var image: Image? {
        AppIcon(for: "theboringteam.boringNotch")
    }
    
    var actions: [Action] {
        Action {
            Text("common.more")
        }
    }
}

struct TipsView: View {
    var hudTip = HUDsTip()
    var cbTip = CBTip()
    var body: some View {
        VStack {
            TipView(hudTip)
            TipView(cbTip)
        }
        .task {
            try? Tips.configure([
                .displayFrequency(.immediate),
                .datastoreLocation(.applicationDefault)
            ])
        }
    }
}

#Preview {
    TipsView()
}
