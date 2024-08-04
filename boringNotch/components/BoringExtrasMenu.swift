//
//  BoringExtrasMenu.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import SwiftUI

struct BoringLargeButtons: View {
    var action: () -> Void
    var icon: Image
    var title: String
    var body: some View {
        Button (
            action:action,
            label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 12.0).fill(.black).frame(width: 80, height: 80)
                    VStack(spacing: 8) {
                        icon.resizable()
                            .aspectRatio(contentMode: .fit).frame(width:20)
                        Text(title).font(.body)
                    }
                }
            }).buttonStyle(PlainButtonStyle()).shadow(color: .black.opacity(0.5), radius: 10)
    }
}

struct BoringExtrasMenu : View {
    @ObservedObject var vm: BoringViewModel
    
    var body: some View {
        VStack{
            HStack(spacing: 20)  {
                github
                donate
                close
                clear
            }
//            Text(vm.releaseName).padding(.top, 4).padding(.bottom, 2)
        }
    }
    
    var github: some View {
        BoringLargeButtons(
            action: {
                NSWorkspace.shared.open(productPage)
            },
            icon: Image(.github),
            title: "Checkout"
        )
    }
    
    var donate: some View {
        BoringLargeButtons(
            action: {
                NSWorkspace.shared.open(sponsorPage)
            },
            icon: Image(systemName: "heart.fill"),
            title: "Love Us"
        )
    }
    
    var close: some View {
        BoringLargeButtons(
            action: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    vm.openMusic()
                }
            },
            icon: Image(systemName: "xmark"),
            title: "Close"
        )
    }
    
    var clear: some View {
        BoringLargeButtons(
            action: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        NSApp.terminate(nil)
                    }
                }
            },
            icon: Image(systemName: "trash"),
            title: "Exit"
        )
    }
}


#Preview {
    BoringExtrasMenu(vm: .init())
}
