//
//  AgentPromptGlyph.swift
//  boringCode
//
//  Ícone ">_" do módulo de agentes, sem caixa em volta — desenhado em vetor
//  para ficar nítido e com peso visual parecido com os SF Symbols das outras abas.
//

import SwiftUI

struct AgentPromptGlyph: View {
    /// Nome usado no lugar de um SF Symbol em `TabModel.icon`.
    static let iconName = "boringcode.prompt"

    var lineWidth: CGFloat = 2.2

    var body: some View {
        PromptShape()
            .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .aspectRatio(1.25, contentMode: .fit)
            .accessibilityHidden(true)
    }

    private struct PromptShape: Shape {
        func path(in rect: CGRect) -> Path {
            let w = rect.width, h = rect.height
            var path = Path()
            // ">"
            path.move(to: CGPoint(x: rect.minX + w * 0.08, y: rect.minY + h * 0.18))
            path.addLine(to: CGPoint(x: rect.minX + w * 0.40, y: rect.minY + h * 0.50))
            path.addLine(to: CGPoint(x: rect.minX + w * 0.08, y: rect.minY + h * 0.82))
            // "_"
            path.move(to: CGPoint(x: rect.minX + w * 0.52, y: rect.minY + h * 0.82))
            path.addLine(to: CGPoint(x: rect.minX + w * 0.94, y: rect.minY + h * 0.82))
            return path
        }
    }
}
