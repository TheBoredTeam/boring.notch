import SwiftUI
import Defaults

struct BoringBluetoothBatteryView: View {
    @State var batteryWidth: CGFloat = 26
    
    @State private var showPopupMenu: Bool = false
    @State private var isHoveringButton: Bool = false
    @State private var isHoveringPopover: Bool = false
    @State private var hideTask: Task<Void, Never>? = nil

    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var bluetoothManager = BluetoothManager.shared

    var body: some View {
        if let snapshot = bluetoothManager.audioDeviceSnapshot, snapshot.isConnected, let battery = snapshot.batteryPercentage {
            Button(action: {
                withAnimation {
                    showPopupMenu.toggle()
                }
            }) {
                HStack {
                    if Defaults[.showBatteryPercentage] {
                        Text("\(battery)%")
                            .font(.callout)
                            .foregroundStyle(.white)
                    }
                    Image(systemName: BluetoothDeviceIconResolver.sfSymbolName(for: snapshot, customMappings: Defaults[.bluetoothDeviceIconMappings]))
                        .resizable()
                        .fontWeight(.thin)
                        .aspectRatio(contentMode: .fit)
                        .foregroundColor(.white)
                        .frame(width: batteryWidth + 1)
                }
            }
            .buttonStyle(ScaleButtonStyle())
            .popover(
                isPresented: $showPopupMenu,
                arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label(snapshot.name, systemImage: BluetoothDeviceIconResolver.sfSymbolName(for: snapshot, customMappings: Defaults[.bluetoothDeviceIconMappings]))
                            .font(.headline)
                            .fontWeight(.semibold)
                        Spacer()
                        Text("\(battery)%")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    
                    Divider().background(Color.white)
                    
                    Button(action: openBluetoothPreferences) {
                        Label("Bluetooth Settings", systemImage: "gearshape")
                            .fontWeight(.regular)
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.plain)
                    .padding(.vertical, 8)
                }
                .padding()
                .frame(width: 280)
                .foregroundColor(.white)
                .onHover { hovering in
                    isHoveringPopover = hovering
                    if hovering {
                        hideTask?.cancel()
                        hideTask = nil
                    } else {
                        scheduleHideIfNeeded()
                    }
                }
            }
            .onChange(of: showPopupMenu) {
                vm.isBatteryPopoverActive = showPopupMenu
            }
            .onDisappear {
                hideTask?.cancel()
                hideTask = nil
            }
        }
    }

    private func scheduleHideIfNeeded() {
        if isHoveringButton || isHoveringPopover { return }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await MainActor.run { withAnimation { showPopupMenu = false } }
        }
    }
    
    private func openBluetoothPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.bluetooth") {
            NSWorkspace.shared.open(url)
            showPopupMenu = false
        }
    }
}
