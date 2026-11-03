import AppKit
import ImageIO
import MathJaxSwift
import SwiftDraw
import SwiftUI

/// One offline engine, isolated from UI work and shared by inline and block math.
private actor CodexMathTypesetter {
    static let shared = CodexMathTypesetter()
    private var engine: MathJax?
    private let cache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 128
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()

    func render(_ equation: CodexMathEquation) -> Data? {
        let key = equation.url.absoluteString as NSString
        if let cached = cache.object(forKey: key) { return cached as Data }
        guard equation.latex.utf8.count <= 64 * 1024 else { return nil }
        do {
            let engine = try self.engine ?? MathJax(preferredOutputFormats: [.svg])
            self.engine = engine
            // Load mathematical syntax only. HTML, URLs, dynamic package loading,
            // and user-defined macros are unavailable to response content.
            let input = TeXInputProcessorOptions(
                loadPackages: ["base", "ams", "boldsymbol", "mathtools"],
                // A literal decimal point prevents numeric tokens consuming TeX braces.
                digits: #"^(?:[0-9]+(?:{,}[0-9]{3})*(?:\.[0-9]*)?|\.[0-9]+)"#,
                maxMacros: 1000, maxBuffer: 64 * 1024
            )
            let source: String = try engine.tex2svg(
                equation.latex, styles: false,
                conversionOptions: ConversionOptions(display: equation.isDisplay),
                inputOptions: input,
                outputOptions: SVGOutputProcessorOptions(fontCache: "none")
            )
            guard source.utf8.count <= 1024 * 1024 else { return nil }
            let document = try XMLDocument(xmlString: source, options: .nodeLoadExternalEntitiesNever)
            guard let root = document.rootElement(), root.name == "svg",
                  let viewBox = root.attribute(forName: "viewBox")?.stringValue else { return nil }
            let dimensions = viewBox.split(whereSeparator: { $0.isWhitespace || $0 == "," }).compactMap { Double($0) }
            guard dimensions.count == 4, dimensions.allSatisfy(\.isFinite) else { return nil }
            // MathJax's SVG viewBox uses 1000 units per em. Explicit point sizes
            // avoid interpreting CSS ex units as pixels in the native renderer.
            let em: Double = equation.isDisplay ? 13 : 11
            let width = dimensions[2] * em / 1000
            let height = dimensions[3] * em / 1000
            guard width > 0, height > 0, width <= 4096, height <= 1024 else { return nil }
            root.attribute(forName: "width")?.stringValue = String(width)
            root.attribute(forName: "height")?.stringValue = String(height)
            let xml = document.xmlString.replacingOccurrences(of: "currentColor", with: "#f0f0f0")
            guard let svg = SVG(xml: xml) else { return nil }
            let data = try svg.pngData(scale: 2)
            cache.setObject(data as NSData, forKey: key, cost: data.count)
            return data
        } catch {
            // Malformed or unsupported input stays readable; never log response text.
            return nil
        }
    }
}

@MainActor
enum CodexMathImage {
    static func render(_ equation: CodexMathEquation) async -> Image? {
        guard let data = await CodexMathTypesetter.shared.render(equation),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return Image(image, scale: 2, label: Text(equation.latex))
    }

    static func inlineImage(_ equation: CodexMathEquation) async -> Image {
        if let image = await render(equation) { return image }
        let text = NSAttributedString(string: equation.latex, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.94),
        ])
        let bounds = text.boundingRect(with: CGSize(width: 4092, height: 1020), options: [.usesLineFragmentOrigin, .usesFontLeading])
        let size = CGSize(width: ceil(bounds.width) + 4, height: ceil(bounds.height) + 4)
        guard size.width > 0, size.height > 0, size.width <= 4096, size.height <= 1024,
              let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
              ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return Image(systemName: "textformat") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: 2, y: 2)
        text.draw(in: CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2))
        NSGraphicsContext.restoreGraphicsState()
        guard let image = bitmap.cgImage else { return Image(systemName: "textformat") }
        return Image(image, scale: 2, label: Text(equation.latex))
    }
}

struct CodexMathBlock: View {
    let equation: CodexMathEquation
    @State private var image: Image?
    @State private var finishedRendering = false

    var body: some View {
        ScrollView(.horizontal) {
            if let image {
                image
            } else {
                Text(equation.latex)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .redacted(reason: finishedRendering ? [] : .placeholder)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel("Equation: \(equation.latex)")
        .task(id: equation.url) {
            image = nil
            finishedRendering = false
            let rendered = await CodexMathImage.render(equation)
            guard !Task.isCancelled else { return }
            image = rendered
            finishedRendering = true
        }
    }
}
