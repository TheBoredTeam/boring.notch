//
//  HUDShape.swift
//  boringNotch
//
//  Created by Alessandro Gravagno on 25/03/25.
//

import SwiftUI

struct HUDShape: Shape {
    var topCornerRadius: CGFloat {
        if bottomCornerRadius > 15 {
            bottomCornerRadius - 5
        } else {
            5
        }
    }
    
    var bottomCornerRadius: CGFloat
    
    init(cornerRadius: CGFloat? = nil) {
        if cornerRadius == nil {
            self.bottomCornerRadius = 10
        } else {
            self.bottomCornerRadius = cornerRadius!
        }
    }
    
    var animatableData: CGFloat {
        get { bottomCornerRadius }
        set { bottomCornerRadius = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
            var path = Path()
            
            
            
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            
            
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            
            
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomCornerRadius))
            
            
            path.addArc(
                center: CGPoint(x: rect.maxX - bottomCornerRadius, y: rect.maxY - bottomCornerRadius),
                radius: bottomCornerRadius,
                startAngle: .zero,
                endAngle: .degrees(90),
                clockwise: false
            )
            
            
            path.addLine(to: CGPoint(x: rect.minX + bottomCornerRadius, y: rect.maxY))
            
            
            path.addArc(
                center: CGPoint(x: rect.minX + bottomCornerRadius, y: rect.maxY - bottomCornerRadius),
                radius: bottomCornerRadius,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false
            )
            
            
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            
            
            path.closeSubpath()
            
            return path
        }
}


#Preview {
    HUDShape()
        .frame(width: 200, height: 32)
        .padding(10)
}
