//
//  KairoExtrasMenu.swift
//  Kairo
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import SwiftUI

struct KairoLargeButtons: View {
    var action: () -> Void
    var icon: Image
    var title: String
    var body: some View {
        Button (
            action:action,
            label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 12.0).fill(.black).frame(width: 70, height: 70)
                    VStack(spacing: 8) {
                        icon.resizable()
                            .aspectRatio(contentMode: .fit).frame(width:20)
                        Text(title).font(.body)
                    }
                }
            }).buttonStyle(PlainButtonStyle()).shadow(color: .black.opacity(0.5), radius: 10)
    }
}

struct KairoExtrasMenu : View {
    @ObservedObject var vm: KairoViewModel
    
    var body: some View {
        VStack{
            HStack(spacing: 20)  {
                hide
                settings
                close
            }
        }
    }
    
    var github: some View {
        KairoLargeButtons(
            action: {
                if let url = URL(string: "https://github.com/wizlox/kairo-notch") {
                    NSWorkspace.shared.open(url)
                }
            },
            icon: Image(.github),
            title: "Checkout"
        )
    }
    
    var settings: some View {
        Button(action: {
            DispatchQueue.main.async {
                SettingsWindowController.shared.showWindow()
            }
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 12.0).fill(.black).frame(width: 70, height: 70)
                VStack(spacing: 8) {
                    Image(systemName: "gear").resizable()
                        .aspectRatio(contentMode: .fit).frame(width:20)
                    Text("Settings").font(.body)
                }
            }
        }
        .buttonStyle(PlainButtonStyle()).shadow(color: .black.opacity(0.5), radius: 10)
    }
    
    var hide: some View {
        KairoLargeButtons(
            action: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    //vm.openMusic()
                }
            },
            icon: Image(systemName: "arrow.down.forward.and.arrow.up.backward"),
            title: "Hide"
        )
    }
    
    var close: some View {
        KairoLargeButtons(
            action: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        NSApp.terminate(nil)
                    }
                }
            },
            icon: Image(systemName: "xmark"),
            title: "Exit"
        )
    }
}


#Preview {
    KairoExtrasMenu(vm: .init())
}
