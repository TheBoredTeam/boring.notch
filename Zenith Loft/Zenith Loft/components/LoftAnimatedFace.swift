import SwiftUI

struct LoftMinimalFaceFeatures: View {
    @State private var isBlinking = false
    @State var height: CGFloat = 20
    @State var width: CGFloat = 30
    
    var body: some View {
        VStack(spacing: 4) {
            // Eyes
            HStack(spacing: 4) {
                LoftEye(isBlinking: $isBlinking)
                LoftEye(isBlinking: $isBlinking)
            }
            
            // Nose and mouth combined
            VStack(spacing: 2) {
                // Nose
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white)
                    .frame(width: 3, height: 4)
                
                // Mouth (happy)
                GeometryReader { geometry in
                    Path { path in
                        let width = geometry.size.width
                        let height = geometry.size.height
                        path.move(to: CGPoint(x: 0, y: height / 2))
                        path.addQuadCurve(
                            to: CGPoint(x: width, y: height / 2),
                            control: CGPoint(x: width / 2, y: height)
                        )
                    }
                    .stroke(Color.white, lineWidth: 2)
                }
                .frame(width: 14, height: 10)
            }
        }
        .frame(width: self.width, height: self.height)
        .onAppear { startBlinking() }
    }
    
    private func startBlinking() {
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            withAnimation(.spring(duration: 0.2)) {
                isBlinking = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(duration: 0.2)) {
                    isBlinking = false
                }
            }
        }
    }
}

struct LoftEye: View {
    @Binding var isBlinking: Bool
    
    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.white)
            .frame(width: 4, height: isBlinking ? 1 : 4)
            .frame(maxWidth: 15, maxHeight: 15)
            .animation(.easeInOut(duration: 0.1), value: isBlinking)
    }
}

#Preview {
    ZStack {
        Color.black
        LoftMinimalFaceFeatures()
    }
    .previewLayout(.fixed(width: 60, height: 60))
}
