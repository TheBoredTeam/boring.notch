import SwiftUI

struct LoftCircularProgressView: View {
    let progress: Double
    let color: Color
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 6)
            
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    color,
                    style: StrokeStyle(
                        lineWidth: 6,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
        }
        .animation(.easeInOut(duration: 0.3), value: progress)
    }
}

enum LoftProgressIndicatorType {
    case circle
    case text
}

struct LoftProgressIndicator: View {
    var type: LoftProgressIndicatorType
    var progress: Double
    var color: Color
    
    var body: some View {
        switch type {
        case .circle:
            LoftCircularProgressView(progress: progress, color: color)
                .frame(width: 20, height: 20)
        case .text:
            Text("\(Int(progress * 100))%")
                .font(.caption)
                .foregroundStyle(color)
        }
    }
}

#Preview {
    LoftProgressIndicator(type: .circle, progress: 0.8, color: .blue)
        .padding()
        .frame(width: 200, height: 200)
}
