//
//  AnimatedFace.swift
//
// Created by Harsh Vardhan  Goswami  on  04/08/24.
//
import SwiftUI

struct MinimalFaceFeatures: View {
    @State private var isBlinking = false
    @State private var mouseLocation: CGPoint = .zero
    @State private var timer: Timer?
    @State private var isSleeping = false
    @State private var lastMouseMoveTime = Date()
    @State private var yawnTimer: Timer?
    @State var height: CGFloat = 20
    @State var width: CGFloat = 32
    
    var body: some View {
        ZStack {
            VStack(spacing: 3) {
                HStack(spacing: 8) {
                    MouseFollowingEye(mouseLocation: mouseLocation, isBlinking: $isBlinking, isSleeping: $isSleeping)
                    MouseFollowingEye(mouseLocation: mouseLocation, isBlinking: $isBlinking, isSleeping: $isSleeping)
                }
                
                if !isSleeping {
                    VStack(spacing: 1) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.white)
                            .frame(width: 2, height: 3)
                        
                        Path { path in
                            let width: CGFloat = 12
                            let height: CGFloat = 6
                            path.move(to: CGPoint(x: 0, y: height / 2))
                            path.addQuadCurve(to: CGPoint(x: width, y: height / 2), control: CGPoint(x: width / 2, y: height))
                        }
                        .stroke(Color.white, lineWidth: 1.5)
                        .frame(width: 12, height: 6)
                    }
                }
            }
            
            if isSleeping {
                SleepingZZZ()
                    .offset(x: 12, y: -8)
            }
        }
        .frame(width: self.width, height: self.height)
        .onAppear {
            startBlinking()
            startMouseTracking()
            startSleepTracking()
        }
        .onDisappear {
            stopMouseTracking()
            stopSleepTracking()
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
    
    func startMouseTracking() {
        timer = Timer.scheduledTimer(withTimeInterval: 1/60.0, repeats: true) { _ in
            let screenMouseLocation = NSEvent.mouseLocation
            if screenMouseLocation != mouseLocation {
                lastMouseMoveTime = Date()
            }
            mouseLocation = screenMouseLocation
        }
    }
    
    func stopMouseTracking() {
        timer?.invalidate()
        timer = nil
    }
    
    func startSleepTracking() {
        yawnTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let timeSinceLastMove = Date().timeIntervalSince(lastMouseMoveTime)
            if timeSinceLastMove >= 10 && !isSleeping {
                withAnimation(.easeInOut(duration: 0.5)) {
                    isSleeping = true
                }
            } else if timeSinceLastMove < 10 && isSleeping {
                withAnimation(.easeInOut(duration: 0.5)) {
                    isSleeping = false
                }
            }
        }
    }
    
    func stopSleepTracking() {
        yawnTimer?.invalidate()
        yawnTimer = nil
    }
}

struct MouseFollowingEye: View {
    let mouseLocation: CGPoint
    @Binding var isBlinking: Bool
    @Binding var isSleeping: Bool
    
    private let eyeSize: CGFloat = 12
    private let pupilSize: CGFloat = 4
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: eyeSize, height: eyeSize)
                .offset(y: isSleeping ? eyeSize * 0.5 : 0)
                .overlay(
                    Circle()
                        .offset(y: isSleeping ? eyeSize * 0.5 : 0)
                        .stroke(Color.gray, lineWidth: 1)
                )
            
            if !isBlinking {
                Circle()
                    .fill(Color.black)
                    .frame(width: pupilSize, height: pupilSize)
                    .offset(pupilOffset())
                    .animation(.easeOut(duration: 0.1), value: mouseLocation)
            }
        }
        .frame(width: eyeSize, height: eyeSize)
        .scaleEffect(isBlinking ? CGSize(width: 1, height: 0.1) : CGSize(width: 1, height: 1))
        .mask(
            Rectangle()
                .offset(y: isSleeping ? eyeSize * 0.5 : 0)
                .frame(width: eyeSize, height: isSleeping ? eyeSize * 0.5 : eyeSize)
        )
        .animation(.easeInOut(duration: 0.1), value: isBlinking)
        .animation(.easeInOut(duration: 0.5), value: isSleeping)
    }
    
    private func pupilOffset() -> CGSize {
        let maxOffsetX = (eyeSize - pupilSize) / 2 - 1
        let maxOffsetY = (eyeSize - pupilSize) / 2 - 1
        
        if isSleeping {
            return CGSize(width: -2, height: eyeSize * 0.5 + 2)
        }
        
        let screenWidth = NSScreen.main?.frame.width ?? 1920
        let screenHeight = NSScreen.main?.frame.height ?? 1080
        let screenCenter = CGPoint(x: screenWidth / 2, y: screenHeight / 2)
        
        let dx = mouseLocation.x - screenCenter.x
        let dy = mouseLocation.y - screenCenter.y
        let distance = sqrt(dx * dx + dy * dy)
        
        let veryCloseDistance = min(screenWidth, screenHeight) * 0.15
        if distance < veryCloseDistance {
            let crossIntensity = 1.0 - (distance / veryCloseDistance)
            let crossOffset = maxOffsetX * 0.7 * crossIntensity
            return CGSize(width: dx > 0 ? -crossOffset : crossOffset, height: maxOffsetY * 0.4)
        }
        
        let normalizedX = max(-1.0, min(1.0, dx / (screenWidth * 0.4)))
        let pupilX = normalizedX * maxOffsetX
        
        let notchY = screenHeight - 50
        
        let pupilY: CGFloat
        if mouseLocation.y > notchY {
            let normalizedY = max(-1.0, min(0.01, -dy / (screenHeight * 0.1)))
            pupilY = normalizedY * maxOffsetY + maxOffsetY * 0.6
        } else {
            pupilY = maxOffsetY * 0.8
        }
        
        return CGSize(width: pupilX, height: pupilY)
    }
}

struct Eye: View {
    @Binding var isBlinking: Bool
    
    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.white)
            .frame(width: 4, height: isBlinking ? 1 : 4)
            .frame(maxWidth: 15, maxHeight: 15)
            .animation(.easeInOut(duration: 0.1), value: isBlinking)
    }
}

struct SleepingZZZ: View {
    @State private var animationOffset1: CGFloat = 0
    @State private var animationOffset2: CGFloat = 0
    @State private var animationOffset3: CGFloat = 0
    @State private var opacity1: Double = 1
    @State private var opacity2: Double = 1
    @State private var opacity3: Double = 1
    
    var body: some View {
        ZStack {
            Text("z")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white)
                .offset(x: -2, y: animationOffset1)
                .opacity(opacity1)
            
            Text("z")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .offset(x: 2, y: animationOffset2)
                .opacity(opacity2)
            
            Text("Z")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .offset(x: 6, y: animationOffset3)
                .opacity(opacity3)
        }
        .onAppear {
            startZZZAnimation()
        }
    }
    
    private func startZZZAnimation() {
        let duration = 3.0
        
        Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            animationOffset1 = 0
            opacity1 = 1
            withAnimation(.linear(duration: duration)) {
                animationOffset1 = -25
                opacity1 = 0
            }
        }
        
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            animationOffset2 = 0
            opacity2 = 1
            withAnimation(.linear(duration: duration)) {
                animationOffset2 = -28
                opacity2 = 0
            }
        }
        
        Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { _ in
            animationOffset3 = 0
            opacity3 = 1
            withAnimation(.linear(duration: duration)) {
                animationOffset3 = -30
                opacity3 = 0
            }
        }
    }
}

struct MinimalFaceFeatures_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            MinimalFaceFeatures()
        }
        .previewLayout(.fixed(width: 60, height: 60))
    }
}
