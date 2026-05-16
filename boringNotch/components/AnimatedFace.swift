//
//  AnimatedFace.swift
//
// Created by Harsh Vardhan  Goswami  on  04/08/24.
//

import SwiftUI

struct MinimalFaceFeatures: View {
    @State private var isBlinking = false
    @State private var blinkTask: Task<Void, Never>? = nil
    var height: CGFloat = 24
    var width: CGFloat = 30

    private var eyeSpacing: CGFloat { 4 * (height / 24.0) }
    private var eyeSize: CGSize { CGSize(width: 4 * (height / 24.0), height: 4 * (height / 24.0)) }
    private var blinkHeight: CGFloat { 1 * (height / 24.0) }
    private var noseSize: CGSize { CGSize(width: 3 * (height / 24.0), height: 4 * (height / 24.0)) }
    private var mouthSize: CGSize { CGSize(width: 14 * (height / 24.0), height: 10 * (height / 24.0)) }

    var body: some View {
        VStack(spacing: eyeSpacing) {
            HStack(spacing: eyeSpacing) {
                Eye(isBlinking: isBlinking, size: eyeSize, blinkHeight: blinkHeight)
                Eye(isBlinking: isBlinking, size: eyeSize, blinkHeight: blinkHeight)
            }
            VStack(spacing: 2 * (height / 24.0)) {
                RoundedRectangle(cornerRadius: 2 * (height / 24.0))
                    .fill(Color.white)
                    .frame(width: noseSize.width, height: noseSize.height)
                Mouth(size: mouthSize)
            }
        }
        .frame(width: width, height: height)
        .onAppear(perform: startBlinking)
        .onDisappear(perform: stopBlinking)
    }
    
    func startBlinking() {
        guard blinkTask == nil else { return }
        blinkTask = Task {
            while !(Task.isCancelled) {
                try? await Task.sleep(for: .seconds(3))
                if Task.isCancelled { break }
                await MainActor.run {
                    isBlinking = true
                }
                try? await Task.sleep(for: .milliseconds(100))
                if Task.isCancelled { break }
                await MainActor.run {
                    isBlinking = false
                }
            }
            await MainActor.run { blinkTask = nil }
        }
    }

    func stopBlinking() {
        blinkTask?.cancel()
        blinkTask = nil
    }
}

struct Eye: View {
    let isBlinking: Bool
    let size: CGSize
    let blinkHeight: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size.height / 2)
            .fill(Color.white)
            .frame(width: size.width, height: isBlinking ? blinkHeight : size.height)
            .frame(maxWidth: 15 * (size.height / 4.0), maxHeight: 15 * (size.height / 4.0))
    }
}

struct Mouth: View {
    let size: CGSize
    var body: some View {
        Canvas { context, _ in
            let width = size.width
            let height = size.height
            var path = Path()
            path.move(to: CGPoint(x: 0, y: height / 2))
            path.addQuadCurve(to: CGPoint(x: width, y: height / 2), control: CGPoint(x: width / 2, y: height))
            context.stroke(path, with: .color(.white), lineWidth: max(1, 2 * (size.height / 10.0)))
        }
        .frame(width: size.width, height: size.height)
    }
}

struct MinimalFaceFeatures_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            MinimalFaceFeatures(height: 24, width: 30)
        }
        .previewLayout(.fixed(width: 60, height: 60)) // Adjusted preview size for better visibility
    }
}
