import SwiftUI

struct LoftTabButton: View {
    let label: String
    let icon: String
    let selected: Bool
    let onClick: () -> Void
    
    var body: some View {
        Button(action: onClick) {
            Image(systemName: icon)
                .padding(.horizontal, 15)
                .contentShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    LoftTabButton(label: "Home", icon: "tray.fill", selected: true) {
        print("Tapped")
    }
}
