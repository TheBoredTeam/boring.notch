import SwiftUI
import AVFoundation
import Combine

struct ContentView: View {
    let onHover: () -> Void
    @StateObject var vm: BoringViewModel
    @StateObject var batteryModel: BatteryStatusViewModel
    var body: some View {
        BoringNotch(vm: vm, onHover: onHover, batteryModel: batteryModel)
            .frame(maxWidth: .infinity, maxHeight: 250)
            .background(Color.clear)
            .edgesIgnoringSafeArea(.top)
    }
}
