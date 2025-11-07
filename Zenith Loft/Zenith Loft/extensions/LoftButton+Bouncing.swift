import SwiftUI
import Defaults

struct LoftBouncingButtonStyle: ButtonStyle {
    let vm: LoftViewModel
    @State private var isPressed = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: Defaults[.cornerRadiusScaling] ? 10 : LoftMusicPlayerImageSizes.cornerRadiusInset.closed)
                    .fill(Color(red: 20/255, green: 20/255, blue: 20/255))
                    .strokeBorder(.white.opacity(0.04), lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.9 : 1.0)
            .onChange(of: configuration.isPressed) { _, _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.3, blendDuration: 0.3)) {
                    isPressed.toggle()
                }
            }
    }
}

extension Button {
    func loftBouncingStyle(vm: LoftViewModel) -> some View {
        self.buttonStyle(LoftBouncingButtonStyle(vm: vm))
    }
}
