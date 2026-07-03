import SwiftUI

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
    let homeTab:HomeTabs
}

struct TabSelectionView: View {
    var tabs:[TabModel] {
        if(coordinator.currentView == .shelf){
            return [
                TabModel(label: "Home", icon: "house.fill", view: .home, homeTab: .none),
                TabModel(label: "Shelf", icon: "tray.fill", view: .shelf, homeTab: .none)
            ]
        }else{
            return [
                TabModel(label: "Clock", icon: "clock.fill", view: .home, homeTab: .clock),
                TabModel(label: "Player", icon: "music.note", view: .home, homeTab: .player),
                TabModel(label: "Shelf", icon: "tray.fill", view: .shelf, homeTab: .none)
            ]
        }
    }

    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Namespace var animation
    
    var body: some View {
        ZStack(alignment: .leading) {

            GeometryReader { proxy in
                let grouped = tabs.enumerated().filter { $0.element.homeTab != .none }

                if let first = grouped.first,
                   let last = grouped.last {

                    let count = tabs.count
                    let itemWidth = proxy.size.width / CGFloat(count)

                    let x = CGFloat(first.offset) * itemWidth
                    let width = CGFloat(Double(last.offset - first.offset)+0.47) * itemWidth

                    Capsule()
                        .fill(Color.secondary.opacity(0.20))
                        .frame(width: width, height: 26)
                        .offset(x: x, y: 0)
                }
            }
            .frame(height: 26)

            HStack(spacing: 0) {
                ForEach(tabs) { tab in
                    let selected=tab.homeTab != .none
                    ? (coordinator.currentTab == tab.homeTab)
                    : (coordinator.currentView == tab.view)
                    TabButton(
                        label: tab.label,
                        icon: tab.icon,
                        selected: selected
                    ) {
                        withAnimation(.smooth) {
                            coordinator.currentView = tab.view
                            if(tab.homeTab != .none){
                                coordinator.currentTab = tab.homeTab
                            }
                        }
                    }
                    .frame(height: 26)
                    .foregroundStyle(selected ? .white : .gray)
                    .background {
                        
                        if (selected) {

                            Capsule()
                                .fill(Color(nsColor: .secondarySystemFill))
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        } else {
                            Capsule()
                                .fill(Color.clear)
                                .hidden()
                        }
                    }
                }
            }
        }
    }
}
