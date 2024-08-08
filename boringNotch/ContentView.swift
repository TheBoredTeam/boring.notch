import SwiftUI
import AVFoundation
import Combine

struct ContentView: View {
    let onHover: () -> Void
    @EnvironmentObject var vm: BoringViewModel
    @StateObject var batteryModel: BatteryStatusViewModel
    var body: some View {
        BoringNotch(vm: vm, onHover: onHover, batteryModel: batteryModel)
            .frame(maxWidth: .infinity, maxHeight: Sizes().size.opened.height)
            .background(Color.clear)
            .edgesIgnoringSafeArea(.top).transition(.slide.animation(vm.animation))
    }
}
