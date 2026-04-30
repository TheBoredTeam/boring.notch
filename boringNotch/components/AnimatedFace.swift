//
//  AnimatedFace.swift
//
// Created by Harsh Vardhan  Goswami  on  04/08/24.
// Extended with multiple face types by Claw on 2026-04-29.
//

import SwiftUI
import Defaults

// MARK: - Animated Face View (Main Container)
struct AnimatedFaceView: View {
    @State private var currentFaceType: FaceType = .minimal
    @State private var animationPhase: Int = 0
    @State private var isBlinking = false
    @State private var blinkTimer: Timer?
    @State private var phaseTimer: Timer?
    @State private var randomTimer: Timer?
    
    private let blinkInterval: TimeInterval = 3.0
    private let phaseInterval: TimeInterval = 8.0
    
    var body: some View {
        FaceView(type: currentFaceType, isBlinking: isBlinking, animationPhase: animationPhase)
            .onAppear {
                startAnimating()
            }
            .onDisappear {
                stopAnimating()
            }
            .onChange(of: Defaults[.faceSelectionMode]) { _, _ in
                updateFaceType()
                updateRandomTimer()
            }
            .onChange(of: Defaults[.faceAnimationType]) { _, newValue in
                withAnimation(.easeInOut(duration: 0.3)) {
                    currentFaceType = newValue
                }
            }
    }
    
    private func stopAnimating() {
        blinkTimer?.invalidate()
        phaseTimer?.invalidate()
        randomTimer?.invalidate()
    }
    
    private func startAnimating() {
        updateFaceType()
        
        // Start blinking timer
        blinkTimer = Timer.scheduledTimer(withTimeInterval: blinkInterval, repeats: true) { _ in
            withAnimation(.spring(duration: 0.15)) {
                isBlinking = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(duration: 0.15)) {
                    isBlinking = false
                }
            }
        }
        
        // Start animation phase cycle (change expression periodically)
        phaseTimer = Timer.scheduledTimer(withTimeInterval: phaseInterval, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                animationPhase = (animationPhase + 1) % 3
            }
        }
        
        // Start random face cycle if in random mode
        updateRandomTimer()
    }
    
    private func updateFaceType() {
        let mode = Defaults[.faceSelectionMode]
        if mode == .random {
            currentFaceType = randomFaceType()
        } else {
            currentFaceType = Defaults[.faceAnimationType]
        }
    }
    
    private func randomFaceType() -> FaceType {
        let faces = FaceType.allCases
        return faces.randomElement() ?? .minimal
    }
    
    private func updateRandomTimer() {
        randomTimer?.invalidate()
        
        let mode = Defaults[.faceSelectionMode]
        if mode == .random {
            let interval = TimeInterval(Defaults[.faceRandomInterval])
            randomTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.3)) {
                    currentFaceType = randomFaceType()
                }
            }
        } else {
            // When switching to fixed mode, immediately set the selected face
            withAnimation(.easeInOut(duration: 0.3)) {
                currentFaceType = Defaults[.faceAnimationType]
            }
        }
    }
}

// MARK: - Face View (Renders based on type)
struct FaceView: View {
    let type: FaceType
    let isBlinking: Bool
    let animationPhase: Int
    
    var body: some View {
        Group {
            switch type {
            case .minimal:
                MinimalFaceFeatures(isBlinking: isBlinking)
            case .cool:
                CoolFaceFeatures(isBlinking: isBlinking, animationPhase: animationPhase)
            case .surprised:
                SurprisedFaceFeatures(isBlinking: isBlinking)
            case .sleepy:
                SleepyFaceFeatures(isBlinking: isBlinking)
            case .wink:
                WinkFaceFeatures(isBlinking: isBlinking, animationPhase: animationPhase)
            case .happy:
                HappyFaceFeatures(isBlinking: isBlinking, animationPhase: animationPhase)
            case .angry:
                AngryFaceFeatures(isBlinking: isBlinking, animationPhase: animationPhase)
            case .love:
                LoveFaceFeatures(isBlinking: isBlinking, animationPhase: animationPhase)
            }
        }
    }
}

// MARK: - Original Minimal Face
struct MinimalFaceFeatures: View {
    let isBlinking: Bool
    @State var height: CGFloat = 20
    @State var width: CGFloat = 30
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Eye(isBlinking: isBlinking)
                Eye(isBlinking: isBlinking)
            }
            VStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white)
                    .frame(width: 3, height: 4)
                
                GeometryReader { geometry in
                    Path { path in
                        let w = geometry.size.width
                        let h = geometry.size.height
                        path.move(to: CGPoint(x: 0, y: h / 2))
                        path.addQuadCurve(to: CGPoint(x: w, y: h / 2), control: CGPoint(x: w / 2, y: h))
                    }
                    .stroke(Color.white, lineWidth: 2)
                }
                .frame(width: 14, height: 10)
            }
        }
        .frame(width: width, height: height)
    }
}

// MARK: - Eye Component (for reusable blinking)
struct Eye: View {
    let isBlinking: Bool
    
    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.white)
            .frame(width: 4, height: isBlinking ? 1 : 4)
            .frame(maxWidth: 15, maxHeight: 15)
    }
}

// MARK: - Cool Face (With Sunglasses)
struct CoolFaceFeatures: View {
    let isBlinking: Bool
    let animationPhase: Int
    
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 12, height: 5)
                Rectangle()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: 4, height: 1)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 12, height: 5)
            }
            .frame(height: 8)
            
            GeometryReader { geometry in
                Path { path in
                    let w = geometry.size.width
                    let h = geometry.size.height
                    path.move(to: CGPoint(x: w * 0.2, y: h * 0.4))
                    path.addQuadCurve(to: CGPoint(x: w * 0.8, y: h * 0.4), control: CGPoint(x: w * 0.5, y: h * 0.8))
                }
                .stroke(Color.white, lineWidth: 1.5)
            }
            .frame(width: 18, height: 8)
        }
        .frame(width: 32, height: 28)
        .rotationEffect(.degrees(animationPhase == 1 ? -5 : (animationPhase == 2 ? 5 : 0)))
    }
}

// MARK: - Surprised Face
struct SurprisedFaceFeatures: View {
    let isBlinking: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 6, height: 6)
                Circle()
                    .fill(Color.white)
                    .frame(width: 6, height: 6)
            }
            
            Circle()
                .fill(Color.white)
                .frame(width: 8, height: 8)
        }
        .frame(width: 28, height: 26)
    }
}

// MARK: - Sleepy Face
struct SleepyFaceFeatures: View {
    let isBlinking: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Capsule()
                    .fill(Color.white)
                    .frame(width: 8, height: 2)
                Capsule()
                    .fill(Color.white)
                    .frame(width: 8, height: 2)
            }
            
            GeometryReader { geometry in
                Path { path in
                    let w = geometry.size.width
                    let h = geometry.size.height
                    path.move(to: CGPoint(x: 0, y: h * 0.5))
                    path.addQuadCurve(to: CGPoint(x: w, y: h * 0.5), control: CGPoint(x: w / 2, y: h * 0.8))
                }
                .stroke(Color.white, lineWidth: 1.5)
            }
            .frame(width: 12, height: 6)
        }
        .frame(width: 28, height: 22)
    }
}

// MARK: - Wink Face
struct WinkFaceFeatures: View {
    let isBlinking: Bool
    let animationPhase: Int
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 5, height: 5)
                
                Group {
                    if animationPhase == 1 {
                        Capsule()
                            .fill(Color.white)
                            .frame(width: 8, height: 2)
                    } else {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 5, height: 5)
                    }
                }
            }
            
            GeometryReader { geometry in
                Path { path in
                    let w = geometry.size.width
                    let h = geometry.size.height
                    path.move(to: CGPoint(x: 0, y: h * 0.3))
                    path.addQuadCurve(to: CGPoint(x: w, y: h * 0.5), control: CGPoint(x: w * 0.6, y: h * 0.9))
                }
                .stroke(Color.white, lineWidth: 1.5)
            }
            .frame(width: 14, height: 8)
        }
        .frame(width: 26, height: 24)
    }
}

// MARK: - Happy Face
struct HappyFaceFeatures: View {
    let isBlinking: Bool
    let animationPhase: Int
    
    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                Path { path in
                    let w: CGFloat = 6
                    let h: CGFloat = 4
                    path.move(to: CGPoint(x: 0, y: h))
                    path.addQuadCurve(to: CGPoint(x: w, y: h), control: CGPoint(x: w / 2, y: 0))
                }
                .stroke(Color.white, lineWidth: 1.5)
                .frame(width: 6, height: 4)
                
                Path { path in
                    let w: CGFloat = 6
                    let h: CGFloat = 4
                    path.move(to: CGPoint(x: 0, y: h))
                    path.addQuadCurve(to: CGPoint(x: w, y: h), control: CGPoint(x: w / 2, y: 0))
                }
                .stroke(Color.white, lineWidth: 1.5)
                .frame(width: 6, height: 4)
            }
            
            GeometryReader { geometry in
                Path { path in
                    let w = geometry.size.width
                    let h = geometry.size.height
                    path.move(to: CGPoint(x: 2, y: 0))
                    path.addQuadCurve(to: CGPoint(x: w - 2, y: 0), control: CGPoint(x: w / 2, y: h))
                }
                .stroke(Color.white, lineWidth: 2)
            }
            .frame(width: 16, height: 10)
        }
        .frame(width: 28, height: 24)
        .scaleEffect(animationPhase == 1 ? 1.05 : 1.0)
    }
}

// MARK: - Angry Face
struct AngryFaceFeatures: View {
    let isBlinking: Bool
    let animationPhase: Int
    
    var body: some View {
        VStack(spacing: 3) {
            // Angry eyebrows - left and right should slant toward center
            HStack(spacing: 6) {
                // Left eyebrow: \ (high on right, low on left)
                Path { path in
                    let w: CGFloat = 6
                    let h: CGFloat = 3
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: w, y: h))
                }
                .stroke(Color.white, lineWidth: 2)
                
                // Right eyebrow: / (high on left, low on right)
                Path { path in
                    let w: CGFloat = 6
                    let h: CGFloat = 3
                    path.move(to: CGPoint(x: 0, y: h))
                    path.addLine(to: CGPoint(x: w, y: 0))
                }
                .stroke(Color.white, lineWidth: 2)
            }
            
            // Eyes
            HStack(spacing: 8) {
                Eye(isBlinking: isBlinking)
                Eye(isBlinking: isBlinking)
            }
            
            // Frown mouth
            GeometryReader { geometry in
                Path { path in
                    let w = geometry.size.width
                    let h = geometry.size.height
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w / 2, y: h))
                }
                .stroke(Color.white, lineWidth: 2)
            }
            .frame(width: 12, height: 6)
        }
        .frame(width: 28, height: 24)
    }
}

// MARK: - Love Face
struct LoveFaceFeatures: View {
    let isBlinking: Bool
    let animationPhase: Int
    
    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .resizable()
                    .foregroundColor(.white)
                    .frame(width: 6, height: 5)
                Image(systemName: "heart.fill")
                    .resizable()
                    .foregroundColor(.white)
                    .frame(width: 6, height: 5)
            }
            
            GeometryReader { geometry in
                Path { path in
                    let w = geometry.size.width
                    let h = geometry.size.height
                    path.move(to: CGPoint(x: 0, y: 2))
                    path.addQuadCurve(to: CGPoint(x: w, y: 2), control: CGPoint(x: w / 2, y: h))
                }
                .stroke(Color.white, lineWidth: 1.5)
            }
            .frame(width: 12, height: 6)
        }
        .frame(width: 26, height: 20)
        .scaleEffect(animationPhase == 1 ? 1.08 : 1.0)
    }
}

// MARK: - Preview
struct AnimatedFaceView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            VStack(spacing: 20) {
                AnimatedFaceView()
                Text("Current Face")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
        }
        .previewLayout(.fixed(width: 80, height: 80))
    }
}

struct MinimalFaceFeatures_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            MinimalFaceFeatures(isBlinking: false)
        }
        .previewLayout(.fixed(width: 60, height: 60))
    }
}