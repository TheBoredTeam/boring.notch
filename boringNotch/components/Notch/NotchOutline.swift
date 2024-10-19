//
//  NotchOutline.swift
//  boringNotch
//
//  Created by Richard Kunkli on 2024. 10. 19..
//

import SwiftUI

struct NotchOutline: Shape {
    var topCornerRadius: CGFloat = 5
    
    var bottomCornerRadius: CGFloat
    
    init(cornerRadius: CGFloat? = nil) {
        if cornerRadius == nil {
            self.bottomCornerRadius = 10
        } else {
            self.bottomCornerRadius = cornerRadius!
        }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Start from the top left corner
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        
        // Top left inner curve
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius, y: topCornerRadius),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY)
        )
        
        // Left vertical line
        path.addLine(to: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY - bottomCornerRadius))
        
        // Bottom left corner
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius + bottomCornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY)
        )
        
        // Bottom edge
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius - bottomCornerRadius, y: rect.maxY))
        
        // Bottom right corner
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY - bottomCornerRadius),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY)
        )
        
        // Right vertical line
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius, y: topCornerRadius))
        
        // Top right inner curve
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY)
        )
        
        return path
    }
}
