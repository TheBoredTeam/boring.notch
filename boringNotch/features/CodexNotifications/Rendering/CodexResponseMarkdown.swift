import Foundation
import SwiftUI
import MarkdownUI

/// Static response rendering with local formatting and no remote image loading.
public struct CodexResponseMarkdown: View {
    let document: CodexResponseDocument
    private let onOpenCodex: () -> Void

    public init(source: String, onOpenCodex: @escaping () -> Void) {
        self.document = CodexResponseDocument(source: source)
        self.onOpenCodex = onOpenCodex
    }

    public var body: some View {
        Markdown(document.markdown)
            .markdownTheme(Self.responseTheme)
            .markdownBlockStyle(\.paragraph) { configuration in
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.25))
                    .markdownMargin(top: 0, bottom: 8)
            }
            .markdownBlockStyle(\.table) { configuration in
                ScrollView(.horizontal) {
                    configuration.label
                        .fixedSize(horizontal: false, vertical: true)
                        .markdownTableBorderStyle(.init(color: .white.opacity(0.18)))
                }
                .markdownMargin(top: 0, bottom: 8)
            }
            .markdownSoftBreakMode(.lineBreak)
            .markdownImageProvider(CodexResponseImageProvider(equations: document.equations))
            .markdownInlineImageProvider(CodexResponseInlineImageProvider(equations: document.equations))
            .environment(\.openURL, OpenURLAction { url in
                openLink(url)
            })
            .textSelection(.enabled)
    }

    // Override the theme itself: its default text style otherwise takes precedence
    // over the surrounding text environment, restoring 16 pt and a gray background.
    private static let responseTheme = Theme.gitHub.text {
        FontSize(11)
        ForegroundColor(.white.opacity(0.9))
        BackgroundColor(nil)
    }

    static func allowsLink(_ url: URL) -> Bool {
        ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "")
    }

    func openLink(_ url: URL) -> OpenURLAction.Result {
        if document.annotationURLs.contains(url) {
            onOpenCodex()
            return .handled
        }
        return Self.allowsLink(url) ? .systemAction : .discarded
    }
}

struct CodexResponseImageProvider: ImageProvider {
    let equations: [URL: CodexMathEquation]

    func makeImage(url: URL?) -> some View {
        if let url, let equation = equations[url] {
            CodexMathBlock(equation: equation)
        } else {
            Text("Image omitted from preview")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

struct CodexResponseInlineImageProvider: InlineImageProvider {
    let equations: [URL: CodexMathEquation]

    func image(with url: URL, label: String) async throws -> Image {
        guard let equation = equations[url] else {
            // One omitted image must not cancel the renderer's entire inline image group.
            return Image(systemName: "photo")
        }
        return await CodexMathImage.inlineImage(equation)
    }
}
