import SwiftUI

struct LoftEmptyStateView: View {
    var message: String
    @State private var isVisible = true
    
    var body: some View {
        HStack {
            LoftMinimalFaceFeatures(height: 70, width: 80)
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.gray)
        }
        .transition(.blurReplace.animation(.spring(.bouncy(duration: 0.3))))
    }
}

#Preview {
    LoftEmptyStateView(message: "Play some music, friends 🎶")
}
