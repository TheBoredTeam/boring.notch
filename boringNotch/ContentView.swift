import SwiftUI
import AVFoundation
import Combine

struct ContentView: View {
    let onHover: () -> Void
    @EnvironmentObject var vm: BoringViewModel
    @StateObject var batteryModel: BatteryStatusViewModel
    var body: some View {
        
        BoringNotch(vm: vm, batteryModel: batteryModel, onHover: onHover)
            .frame(maxWidth: .infinity, maxHeight: Sizes().size.opened.height!, alignment: .top)
            .background(Color.clear)
            .edgesIgnoringSafeArea(.top).transition(.slide.animation(vm.animation)).onAppear(perform: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: {
                    withAnimation(vm.animation){
                        if vm.firstLaunch {
                            vm.open()
                        }
                    }
                })
            })
            .animation(.smooth().delay(0.3), value: vm.firstLaunch)
            .contextMenu {
                Button("Edit") {
                    let dn = DynamicNotch(content: EditPanelView())
                    dn.toggle()
                }
                .keyboardShortcut("E", modifiers: .command)
            }
            .onAppear {
                print(NSWorkspace.shared.desktopImageURL(for: NSScreen.main!)!)
            }
    }
    
}
