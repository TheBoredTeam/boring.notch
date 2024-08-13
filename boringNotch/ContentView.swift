import SwiftUI
import AVFoundation
import Combine

struct ContentView: View {
    let onHover: () -> Void
    @EnvironmentObject var vm: BoringViewModel
    @StateObject var batteryModel: BatteryStatusViewModel
    var body: some View {
        BoringNotch(vm: vm, batteryModel: batteryModel, onHover: onHover)
            .frame(maxWidth: .infinity, maxHeight: Sizes().size.opened.height! + 20, alignment: .top)
            .edgesIgnoringSafeArea(.top)
            .transition(.slide.animation(vm.animation))
            .onAppear(perform: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: {
                    withAnimation(vm.animation){
                        if vm.firstLaunch {
                            vm.open()
                        }
                    }
                })
            })
            .shadow(color: vm.notchState == .open ? .black : .clear, radius: 10)
            .animation(.smooth().delay(0.3), value: vm.firstLaunch)
            .contextMenu {
                Button("Edit") {
                    let dn = DynamicNotch(content: EditPanelView())
                    dn.toggle()
                }
                .disabled(true)
                .keyboardShortcut("E", modifiers: .command)
            }
    }
    
}
