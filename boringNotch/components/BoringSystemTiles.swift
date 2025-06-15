//
//  BoringSystemTiles.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 16/08/24.
//

import Foundation
import SwiftUI
import Defaults

struct SystemItemButton: View {
    @EnvironmentObject var vm: BoringViewModel
    @State var icon: String = "gear"
    var onTap: () -> Void
    @State var label: String?
    @State var showEmojis: Bool = true
    @State var emoji: String = "🔧"

    var body: some View {
        Button(action: onTap) {
            if Defaults[.tileShowLabels] {
                HStack {
                    if !showEmojis {
                        Image(systemName: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 10)
                            .foregroundStyle(.gray)
                    }

                    Text((showEmojis ? "\(emoji) " : "") + label!)
                        .font(.caption2)
                        .fontWeight(.regular)
                        .foregroundStyle(.gray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .allowsTightening(true)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
            } else {
                Color.clear
                    .overlay {
                        Image(systemName: icon)
                            .foregroundStyle(.gray)
                    }
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .buttonStyle(BouncingButtonStyle(vm: vm))
    }
}

func logout() {
    DispatchQueue.global(qos: .background).async {
        let appleScript = """
        tell application "System Events" to log out
        """

        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: appleScript) {
            scriptObject.executeAndReturnError(&error)
            if let error = error {
                print("Error: \(error)")
            }
        }
    }
}

struct BoringSystemTiles: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var coordinator = BoringViewCoordinator.shared

    struct ItemButton {
        var icon: String
        var onTap: () -> Void
    }

    var body: some View {
        Grid {
            GridRow {
//                SystemItemButton(icon: "clipboard", onTap: {
//                    vm.openClipboard()
//                }, label: "Clipboard History", showEmojis: Defaults[.showEmojis], emoji: "✨")
                //                SystemItemButton(icon: "keyboard", onTap: {
                //                    vm?.close()
                //                    vm?.togglesneakPeek(status: true, type: .backlight, value: 1)
                //                }, label: "💡 Keyboard Backlight")
            }
            GridRow {
                SystemItemButton(icon: coordinator.currentMicStatus ? "mic" : "mic.slash", onTap: {
                    coordinator.toggleMic()
                    vm.close()
                }, label: "Toggle Microphone", showEmojis: Defaults[.showEmojis], emoji: coordinator.currentMicStatus ? "😀" : "🤫")
                //                SystemItemButton(icon: "lock", onTap: {
                //                    logout()
                //                }, label: "🔒 Lock My Device")
            }
        }
    }
}

#Preview {
    BoringSystemTiles().padding()
}
