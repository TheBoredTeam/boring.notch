import SwiftUI

struct LoftTabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: LoftViews
}

let loftTabs = [
    LoftTabModel(label: "Home", icon: "house.fill", view: .home),
    LoftTabModel(label: "Shelf", icon: "tray.fill", view: .shelf)
]

struct LoftTabSelectionView: View {
    @ObservedObject var coordinator = LoftViewCoordinator.shared
    @Namespace var animation
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(loftTabs) { tab in
                LoftTabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view) {
                    withAnimation(.smooth) {
                        coordinator.currentView = tab.view
                    }
                }
                .frame(height: 26)
                .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                .background {
                    if tab.view == coordinator.currentView {
                        Capsule()
                            .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                            .matchedGeometryEffect(id: "capsule", in: animation)
                    } else {
                        Capsule()
                            .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                            .matchedGeometryEffect(id: "capsule", in: animation)
                            .hidden()
                    }
                }
            }
        }
        .clipShape(Capsule())
    }
}

#Preview {
    LoftHeader().environmentObject(LoftViewModel())
}
