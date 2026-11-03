import AppKit
import SwiftUI
import SwiftMath

@MainActor
enum CodexMathImage {
    /// Rasterize local glyphs only; TeX is never passed to a shell or web view.
    static func render(_ equation: CodexMathEquation) -> Image? {
        // SwiftMath typesets the contents; the enclosing equation frame is native.
        let boxed = boxedContents(equation.latex)
        let label = MTMathUILabel()
        label.fontSize = equation.isDisplay ? 13 : 11
        label.labelMode = equation.isDisplay ? .display : .text
        label.textColor = NSColor.white.withAlphaComponent(0.94)
        label.displayErrorInline = false
        label.latex = boxed ?? equation.latex
        guard label.error == nil else { return nil }
        let natural = label.intrinsicContentSize
        let labelSize = CGSize(width: ceil(natural.width) + 2, height: ceil(natural.height) + 4)
        let inset: CGFloat = boxed == nil ? 0 : 6
        let size = CGSize(width: labelSize.width + inset * 2, height: labelSize.height + inset * 2)
        // Bound bitmap allocation for pathological or incomplete generated expressions.
        guard size.width > 2, size.height > 4, size.width <= 4096, size.height <= 1024 else { return nil }
        label.frame = CGRect(origin: .zero, size: labelSize)
        label.layoutSubtreeIfNeeded()
        return rasterize(size: size, label: equation.latex) { bounds in
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            context.saveGState()
            context.translateBy(x: inset, y: inset)
            label.draw(CGRect(origin: .zero, size: labelSize))
            context.restoreGState()
            if boxed != nil {
                context.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
                context.setLineWidth(0.7)
                context.stroke(bounds.insetBy(dx: 0.5, dy: 0.5))
            }
        }
    }

    /// Recognize a whole-expression \boxed{...}, respecting nested/escaped braces.
    private static func boxedContents(_ source: String) -> String? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(#"\boxed"#) else { return nil }
        let argument = trimmed.dropFirst(6).drop(while: { $0.isWhitespace })
        guard argument.first == "{" else { return nil }
        let start = argument.index(after: argument.startIndex)
        var depth = 1
        var escaped = false
        for index in argument.indices.dropFirst() {
            let character = argument[index]
            if escaped { escaped = false; continue }
            if character == "\\" { escaped = true; continue }
            if character == "{" { depth += 1 }
            if character == "}" {
                depth -= 1
                if depth == 0 {
                    guard argument[argument.index(after: index)...].allSatisfy(\.isWhitespace) else { return nil }
                    return String(argument[start..<index])
                }
            }
        }
        return nil
    }

    static func inlineImage(_ equation: CodexMathEquation) -> Image {
        if let image = render(equation) { return image }
        let text = NSAttributedString(string: equation.latex, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.94),
        ])
        let bounds = text.boundingRect(with: CGSize(width: 4092, height: 1020), options: [.usesLineFragmentOrigin, .usesFontLeading])
        let size = CGSize(width: ceil(bounds.width) + 4, height: ceil(bounds.height) + 4)
        return rasterize(size: size, label: equation.latex) { text.draw(in: $0.insetBy(dx: 2, dy: 2)) }
            ?? Image(systemName: "textformat")
    }

    private static func rasterize(size: CGSize, label: String, draw: (CGRect) -> Void) -> Image? {
        guard size.width > 0, size.height > 0, size.width <= 4096, size.height <= 1024 else { return nil }
        let scale: CGFloat = 2
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: scale, y: scale)
        draw(CGRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        guard let image = bitmap.cgImage else { return nil }
        return Image(image, scale: scale, label: Text(label))
    }
}

struct CodexMathBlock: View {
    let equation: CodexMathEquation

    var body: some View {
        ScrollView(.horizontal) {
            if let image = CodexMathImage.render(equation) {
                image
            } else {
                Text(equation.latex)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel("Equation: \(equation.latex)")
    }
}
