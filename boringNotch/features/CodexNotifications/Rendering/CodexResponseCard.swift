import SwiftUI

/// The complete response card, shared by the app and native layout regression tests.
public struct CodexResponseCard: View {
    private let source: String
    private let isTruncated: Bool
    private let projectName: String
    private let chatTitle: String
    private let launchError: String?
    private let maximumHeight: CGFloat
    private let onHeightChange: (CGFloat) -> Void
    private let onOpenCodex: () -> Void
    private let composer: AnyView?
    @State private var contentHeight: CGFloat = 20
    @State private var composerHeight: CGFloat = 0

    public init(
        source: String, isTruncated: Bool, projectName: String, chatTitle: String, launchError: String?,
        maximumHeight: CGFloat, onHeightChange: @escaping (CGFloat) -> Void,
        onOpenCodex: @escaping () -> Void, composer: AnyView?
    ) {
        self.source = source
        self.isTruncated = isTruncated
        self.projectName = projectName
        self.chatTitle = chatTitle
        self.launchError = launchError
        self.maximumHeight = maximumHeight
        self.onHeightChange = onHeightChange
        self.onOpenCodex = onOpenCodex
        self.composer = composer
    }

    private var viewportHeight: CGFloat {
        // Header (20), footer (24), two gaps (12), bottom inset (10).
        let chromeHeight: CGFloat = 66 + (launchError == nil ? 0 : 34)
            + (composer == nil ? 0 : composerHeight + 6)
        return max(20, min(contentHeight, maximumHeight - chromeHeight))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "text.bubble.fill")
                    .foregroundStyle(.cyan)
                    .accessibilityHidden(true)
                Text("Response ready")
                Spacer()
                Text(projectName)
                    .lineLimit(1)

            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(height: 20)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 8) {
                    CodexResponseMarkdown(source: source)
                    if isTruncated {
                        // Kept outside Markdown so a cutoff inside a fence cannot hide it.
                        Text("...")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Response shortened. Open Codex to read the rest.")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    contentHeight = ceil(height)
                }
                // macOS overlay scrollers must have their own empty gutter.
                .padding(.trailing, 16)
            }
            .scrollIndicators(.visible)
            .defaultScrollAnchor(.top)
            .frame(height: viewportHeight)
            .focusable()
            .accessibilityLabel("Final Codex response")

            if let launchError {
                Text(launchError)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .frame(height: 28, alignment: .topLeading)
                    .accessibilityAddTraits(.updatesFrequently)
            }

            if let composer {
                composer
                    .padding(.top, 8)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        composerHeight = ceil(height)
                    }
            }

            HStack {
                Text(chatTitle)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(chatTitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Open in Codex", action: onOpenCodex)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.blue)
                    .buttonStyle(.plain)
                    .fixedSize()
                    .accessibilityLabel("Open this response’s conversation in Codex")
            }
            .frame(height: 24)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            guard height > 0 else { return }
            onHeightChange(height)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Codex response preview")
    }
}
