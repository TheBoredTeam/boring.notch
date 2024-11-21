
import SwiftUI

struct NotchShelfView: View {
    @EnvironmentObject var vm: BoringViewModel
    @StateObject var tvm = TrayDrop.shared

    var body: some View {
        HStack {
            AirDropView()
            panel
                .onDrop(of: [.data], isTargeted: $vm.dropZoneTargeting) { providers in
                    vm.dropEvent = true
                    DispatchQueue.global().async {
                        tvm.load(providers)
                    }
                    return true
                }
        }
    }

    var panel: some View {
        RoundedRectangle(cornerRadius: 16)
            .strokeBorder(style: StrokeStyle(lineWidth: 4, dash: [10]))
            .foregroundStyle(.white.opacity(0.1))
            .overlay {
                content
                    .padding()
            }
            .animation(vm.animation, value: tvm.items)
            .animation(vm.animation, value: tvm.isLoading)
    }

    var content: some View {
        Group {
            if tvm.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray.and.arrow.down")
                        .symbolVariant(.fill)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white, .gray)
                        .imageScale(.large)
                    
                    Text("Drop files here")
                        .foregroundStyle(.gray)
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.medium)
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: spacing) {
                        ForEach(tvm.items) { item in
                            DropItemView(item: item)
                        }
                    }
                    .padding(spacing)
                }
                .padding(-spacing)
                .scrollIndicators(.never)
            }
        }
    }
}

