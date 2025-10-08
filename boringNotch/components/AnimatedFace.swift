//
//  AnimatedFace.swift
//
// Created by Harsh Vardhan  Goswami  on  04/08/24.
//

import SwiftUI
import Defaults

struct MinimalFaceFeatures: View {
    @State private var isBlinking = false
    @State var height:CGFloat = 20;
    @State var width:CGFloat = 30;
    @Default(.selectedMood) private var selectedMood
    // Brief pulse value to accentuate mouth curvature when mood changes
    @State private var mouthAnimation: CGFloat = 0
    
    var body: some View {
        VStack(spacing: 4) { // Adjusted spacing to fit within 30x30
            // Eyes
            HStack(spacing: 4) { // Adjusted spacing to fit within 30x30
                Eye(isBlinking: $isBlinking, isWinking: selectedMood == .wink)
                Eye(isBlinking: $isBlinking)
            }
            
            // Nose and mouth combined
            VStack(spacing: 2) { // Adjusted spacing to fit within 30x30
                // Nose
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white)
                    .frame(width: 3, height: 4)
                
                // Mouth based on mood
                GeometryReader { geometry in
                    Path { path in
                        let w = geometry.size.width
                        let h = geometry.size.height
                        switch selectedMood {
                        case .happy, .wink:
                            path.move(to: CGPoint(x: 0, y: h / 2))
                            path.addQuadCurve(to: CGPoint(x: w, y: h / 2), control: CGPoint(x: w / 2, y: h + mouthAnimation * 2))
                        case .neutral:
                            path.move(to: CGPoint(x: 0, y: h / 2))
                            path.addLine(to: CGPoint(x: w, y: h / 2))
                        case .sad:
                            path.move(to: CGPoint(x: 0, y: h / 2))
                            path.addQuadCurve(to: CGPoint(x: w, y: h / 2), control: CGPoint(x: w / 2, y: 0 - mouthAnimation * 2))
                        case .surprised:
                            let radius = min(w, h) / 3
                            path.addEllipse(in: CGRect(x: (w - radius) / 2, y: (h - radius) / 2, width: radius, height: radius))
                        }
                    }
                    .stroke(Color.white, lineWidth: 2)
                }
                .frame(width: 14, height: 10)
            }
        }
        .frame(width: self.width, height: self.height) // Maximum size of face
        .onAppear {
            startBlinking()
            print("[BoringNotch] Current mood on appear: \(selectedMood.rawValue)")
        }
        .onChange(of: selectedMood) { _, newMood in
            print("[BoringNotch] Mood changed to: \(newMood.rawValue)")
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                mouthAnimation = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.easeOut(duration: 0.2)) {
                    mouthAnimation = 0
                }
            }
        }
    }
    
    func startBlinking() {
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

struct Eye: View {
    @Binding var isBlinking: Bool
    var isWinking: Bool = false
    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.white)
            .frame(width: 4, height: (isBlinking || isWinking) ? 1 : 4)
            .frame(maxWidth: 15, maxHeight: 15)
            .animation(.easeInOut(duration: 0.1), value: isBlinking)
    }
}

struct MinimalFaceFeatures_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            MinimalFaceFeatures()
        }
        .previewLayout(.fixed(width: 60, height: 60)) // Adjusted preview size for better visibility
    }
}
