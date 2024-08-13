import SwiftUI

var notchAnimation = Animation.spring(response: 0.7, dampingFraction: 0.8, blendDuration: 0.8)

struct BoringNotch: View {
    @StateObject var vm: BoringViewModel
    let onHover: () -> Void
    @State private var isExpanded = false
    @State var showEmptyState = false
    @StateObject private var musicManager: MusicManager
    @StateObject var batteryModel: BatteryStatusViewModel
    @State private var haptics: Bool = false
    
    @State private var hoverStartTime: Date?
    @State private var hoverTimer: Timer?
    
    init(vm: BoringViewModel, batteryModel: BatteryStatusViewModel, onHover: @escaping () -> Void) {
        _vm = StateObject(wrappedValue: vm)
        _musicManager = StateObject(wrappedValue: MusicManager(vm: vm))
        _batteryModel = StateObject(wrappedValue: batteryModel)
        self.onHover = onHover
    }
    
    func calculateNotchWidth() -> CGFloat {
        let isFaceVisible = (vm.nothumanface && musicManager.isPlayerIdle) || musicManager.isPlaying
        let baseWidth = vm.sizes.size.closed.width ?? 0
        
        let notchWidth: CGFloat = vm.notchState == .open
        ? vm.sizes.size.opened.width!
        : batteryModel.showChargingInfo
        ? baseWidth + 180
        : CGFloat(vm.firstLaunch ? 50 : 0) + baseWidth + (isFaceVisible ? 75 : 0)
        
        return notchWidth
    }
    
    var body: some View {
        Color.black
            .mask(NotchShape(cornerRadius: vm.notchState == .open ? vm.sizes.corderRadius.opened.inset : vm.sizes.corderRadius.closed.inset))
            .frame(width: calculateNotchWidth(), height: vm.notchState == .open ? (vm.sizes.size.opened.height!) : vm.sizes.size.closed.height)
            .animation(notchAnimation, value: batteryModel.showChargingInfo)
            .animation(notchAnimation, value: musicManager.isPlaying)
            .animation(notchAnimation, value: musicManager.lastUpdated)
            .animation(notchAnimation, value: musicManager.isPlayerIdle)
            .animation(.smooth, value: vm.firstLaunch)
            .overlay {
                NotchContentView()
                    .environmentObject(vm)
                    .environmentObject(musicManager)
                    .environmentObject(batteryModel)
            }
            .clipped()
            .onHover { hovering in
                if hovering {
                    if ((vm.notchState == .closed) && vm.enableHaptics) {
                        haptics.toggle()
                    }
                    startHoverTimer()
                } else {
                    cancelHoverTimer()
                    if vm.notchState == .open {
                        withAnimation(vm.animation) {
                            vm.close()
                            vm.openMusic()
                        }
                    }
                }
            }
            .sensoryFeedback(.levelChange, trigger: haptics)
            .onChange(of: batteryModel.isPluggedIn, { oldValue, newValue in
                withAnimation(.spring(response: 1, dampingFraction: 0.8, blendDuration: 0.7)) {
                    if newValue {
                        batteryModel.showChargingInfo = true
                    } else {
                        batteryModel.showChargingInfo = false
                    }
                }
            })
            .environmentObject(vm)
    }
    
    
    private func startHoverTimer() {
        hoverStartTime = Date()
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            checkHoverDuration()
        }
    }
    
    private func checkHoverDuration() {
        guard let startTime = hoverStartTime else { return }
        let hoverDuration = Date().timeIntervalSince(startTime)
        if hoverDuration >= vm.minimumHoverDuration {
            withAnimation(vm.animation) {
                vm.open()
            }
            cancelHoverTimer()
        }
    }
    
    private func cancelHoverTimer() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        hoverStartTime = nil
    }
}

func onHover(){}

#Preview {
    BoringNotch(vm: BoringViewModel(), batteryModel: BatteryStatusViewModel(vm: .init()), onHover: onHover)
}
