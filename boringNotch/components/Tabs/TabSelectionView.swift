//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import SwiftUI

struct NotchDestinationDescriptor: Identifiable {
    var id: NotchViews { destination }

    let destination: NotchViews
    let label: String
    let icon: String
    let order: Int
    let isAvailable: Bool
}

extension NotchDestinationDescriptor {
    static let builtIn: [Self] = [
        .init(
            destination: .home,
            label: "Home",
            icon: "house.fill",
            order: 0,
            isAvailable: true
        ),
        .init(
            destination: .shelf,
            label: "Shelf",
            icon: "tray.fill",
            order: 1,
            isAvailable: true
        )
    ]

    static let availableBuiltIn: [Self] = {
        builtIn
            .filter(\.isAvailable)
            .sorted { $0.order < $1.order }
    }()
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Namespace var animation
    var body: some View {
        HStack(spacing: 0) {
            ForEach(NotchDestinationDescriptor.availableBuiltIn) { destination in
                let isSelected = coordinator.currentView == destination.destination

                TabButton(label: destination.label, icon: destination.icon) {
                    withAnimation(.smooth) {
                        coordinator.currentView = destination.destination
                    }
                }
                .frame(height: 26)
                .foregroundStyle(isSelected ? .white : .gray)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color(nsColor: .secondarySystemFill))
                            .matchedGeometryEffect(id: "capsule", in: animation)
                    } else {
                        Capsule()
                            .fill(Color.clear)
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
    BoringHeader().environmentObject(BoringViewModel())
}
