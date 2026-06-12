import AppKit
import Defaults
import SwiftUI

private enum ClipboardTheme {
    static let rowHoverBackground = Color.white.opacity(0.055)
    static let border = Color.white.opacity(0.08)
    static let secondaryText = Color.white.opacity(0.62)
    static let tertiaryText = Color.white.opacity(0.42)
    static let accent = Color.cyan.opacity(0.9)
    static let bubbleBackground = Color.black.opacity(0.95)
    static let searchBackground = Color.white.opacity(0.06)
}

private enum ClipboardBubbleTailEdge {
    case left
    case right
}

private enum ClipboardPreviewLayout {
    static let previewWidth: CGFloat = 408
    static let previewHeight: CGFloat = 320
    static let gutter: CGFloat = 9
    static let screenEdgeInset: CGFloat = 8
    static let tailWidth: CGFloat = 11
    static let tailHeight: CGFloat = 22
    static let cornerRadius: CGFloat = 22
    static let contentHorizontalPadding: CGFloat = 18
    static let contentVerticalPadding: CGFloat = 18
    static let sectionSpacing: CGFloat = 10
    static let metadataSpacing: CGFloat = 3
    static let topContentHeight: CGFloat = 208

    static var visibleNotchEdgeInset: CGFloat {
        (Defaults[.cornerRadiusScaling] ? cornerRadiusInsets.opened.top : cornerRadiusInsets.opened.bottom) + 12
    }
}

struct ClipboardView: View {
    @EnvironmentObject var vm: GojoViewModel
    @ObservedObject private var clipboard = ClipboardStateViewModel.shared
    @ObservedObject private var coordinator = GojoViewCoordinator.shared
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            topBar
            if clipboard.filteredItems.isEmpty {
                emptyState
            } else {
                contentArea
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, NotchContentLayout.horizontalPadding)
        .padding(.top, NotchContentLayout.topPadding)
        .padding(.bottom, NotchContentLayout.bottomPadding)
        .onAppear {
            clipboard.start()
            focusSearchSoon()
        }
        .onDisappear {
            clipboard.hideHoverPreview(force: true)
            clipboard.setHoveredItemID(nil)
        }
        .onChange(of: coordinator.currentView) { _, newValue in
            if newValue == .clipboard {
                focusSearchSoon()
            } else {
                clipboard.hideHoverPreview(force: true)
            }
        }
        .onChange(of: clipboard.searchFocusRequestID) { _, _ in
            focusSearchSoon()
        }
        .onChange(of: clipboard.filteredItems.map(\.id)) { _, visibleIDs in
            if let hovered = clipboard.hoveredItemID, !visibleIDs.contains(hovered) {
                clipboard.hideHoverPreview(force: true)
                clipboard.setHoveredItemID(nil)
            }
        }
    }

    private var contentArea: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(clipboard.filteredItems) { item in
                    ClipboardItemRow(item: item)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var topBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ClipboardTheme.secondaryText)
            TextField("Search clipboard", text: $clipboard.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .focused($searchFieldFocused)

            if !clipboard.searchQuery.isEmpty {
                Button {
                    clipboard.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(ClipboardTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }

            if !clipboard.filteredItems.isEmpty {
                Button {
                    clipboard.clearNonPinned()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(ClipboardTheme.secondaryText)
                }
                .buttonStyle(.plain)
                .help("Clear non-pinned history")
            }

            if !clipboard.historyEnabled {
                Image(systemName: "pause.circle")
                    .foregroundStyle(.yellow.opacity(0.95))
                    .help("Clipboard history is paused")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(ClipboardTheme.searchBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(ClipboardTheme.border, lineWidth: 1)
                )
        )
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            Image(systemName: clipboard.historyEnabled ? "doc.on.clipboard" : "pause.circle")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(ClipboardTheme.secondaryText)
            Text(clipboard.historyEnabled ? "Clipboard history will appear here." : "Clipboard history is paused.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(ClipboardTheme.secondaryText)
            Text(
                clipboard.historyEnabled
                ? "Copy text or images anywhere on macOS, then open Gojo to search and reuse them."
                : "Enable it in Settings → Clipboard when you want Gojo to start storing copied content on this Mac."
            )
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(ClipboardTheme.tertiaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func focusSearchSoon() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            guard coordinator.currentView == .clipboard else { return }
            searchFieldFocused = true
        }
    }
}

private struct ClipboardItemRow: View {
    let item: ClipboardItem
    @ObservedObject private var clipboard = ClipboardStateViewModel.shared
    @State private var isHovered = false
    @State private var hoverAnchor = ClipboardHoverAnchor(rowFrame: .zero, windowFrame: .zero)
    private var isCopied: Bool { clipboard.copiedItemID == item.id }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            if item.kind == .image, let payload = item.image {
                ClipboardImageThumbnailView(payload: payload, maxPixelSize: 72)
                    .frame(width: 28, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(ClipboardTheme.border, lineWidth: 1)
                    )
            }

            Text(item.previewLine.isEmpty ? item.normalizedContent : item.previewLine)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 6)

            ZStack(alignment: .trailing) {
                HStack(spacing: 4) {
                    miniButton(systemName: item.isPinned ? "pin.slash" : "pin") {
                        clipboard.togglePin(item)
                    }
                    .help(item.isPinned ? "Unpin" : "Pin")

                    miniButton(systemName: "trash") {
                        clipboard.delete(item)
                    }
                    .help("Delete")
                }
                .opacity(isHovered && !isCopied ? 1 : 0)
                .allowsHitTesting(isHovered && !isCopied)

                Image(systemName: "pin.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(ClipboardTheme.accent)
                    .frame(width: 16, height: 16)
                    .opacity(item.isPinned && !isHovered && !isCopied ? 1 : 0)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.green.opacity(0.95))
                    .frame(width: 18, height: 18)
                    .opacity(isCopied ? 1 : 0)
            }
            .frame(width: 42, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isCopied ? Color.white.opacity(0.08) : (isHovered ? ClipboardTheme.rowHoverBackground : .clear))
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background(
            ClipboardRowFrameReader { anchor in
                hoverAnchor = anchor
                if isHovered, anchor.rowFrame != .zero, anchor.windowFrame != .zero {
                    clipboard.showHoverPreview(for: item, rowFrame: anchor.rowFrame, windowFrame: anchor.windowFrame)
                }
            }
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ClipboardTheme.border.opacity(0.75))
                .frame(height: 1)
                .padding(.horizontal, 2)
        }
        .onTapGesture {
            clipboard.copy(item)
        }
        .animation(.smooth(duration: 0.18), value: isCopied)
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.18)) {
                isHovered = hovering
            }
            clipboard.setHoveredItemID(hovering ? item.id : nil)
            clipboard.setPointerOverHoveredRow(hovering)
            if hovering, hoverAnchor.rowFrame != .zero, hoverAnchor.windowFrame != .zero {
                clipboard.showHoverPreview(for: item, rowFrame: hoverAnchor.rowFrame, windowFrame: hoverAnchor.windowFrame)
            }
        }
        .contextMenu {
            Button(item.isPinned ? "Unpin" : "Pin") {
                clipboard.togglePin(item)
            }
            Button("Delete", role: .destructive) {
                clipboard.delete(item)
            }
            Button("Copy Again") {
                clipboard.copy(item)
            }
        }
    }

    private func miniButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(ClipboardTheme.secondaryText)
                .frame(width: 18, height: 18)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct ClipboardImageThumbnailView: View {
    let payload: ClipboardImagePayload
    let maxPixelSize: CGFloat
    @State private var image: NSImage?

    // Cache hits render on the first frame; only uncached thumbnails go
    // through the async generation path.
    private var resolvedImage: NSImage? {
        image ?? ClipboardImageStore.shared.cachedThumbnail(named: payload.fileName, maxPixelSize: maxPixelSize)
    }

    var body: some View {
        Group {
            if let resolvedImage {
                Image(nsImage: resolvedImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(ClipboardTheme.tertiaryText)
                    )
            }
        }
        .task(id: "\(payload.fileName)#\(Int(maxPixelSize))") {
            guard resolvedImage == nil else { return }
            let fileName = payload.fileName
            let size = maxPixelSize
            let loaded = await Task.detached(priority: .utility) {
                ClipboardImageStore.shared.thumbnail(named: fileName, maxPixelSize: size)
            }.value
            guard !Task.isCancelled, fileName == payload.fileName else { return }
            image = loaded
        }
    }
}

private struct ClipboardHoverAnchor {
    var rowFrame: CGRect
    var windowFrame: CGRect
}

private struct ClipboardRowFrameReader: NSViewRepresentable {
    let onChange: (ClipboardHoverAnchor) -> Void

    func makeNSView(context: Context) -> ClipboardRowFrameReaderView {
        let view = ClipboardRowFrameReaderView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: ClipboardRowFrameReaderView, context: Context) {
        nsView.onChange = onChange
        nsView.reportFrame()
    }
}

private final class ClipboardRowFrameReaderView: NSView {
    var onChange: ((ClipboardHoverAnchor) -> Void)?

    override func layout() {
        super.layout()
        reportFrame()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportFrame()
    }

    func reportFrame() {
        guard let window else { return }
        let frameInWindow = convert(bounds, to: nil)
        let rowFrameInScreen = window.convertToScreen(frameInWindow)
        let windowFrame = window.frame
        DispatchQueue.main.async { [weak self] in
            self?.onChange?(ClipboardHoverAnchor(rowFrame: rowFrameInScreen, windowFrame: windowFrame))
        }
    }
}

final class ClipboardHoverPreviewPanel: NSPanel {
    var onHoverChanged: ((Bool) -> Void)?

    private let clearContentView = TransparentClipboardPreviewContentView()
    private let hostingView = TransparentClipboardPreviewHostingView(rootView: AnyView(EmptyView()))

    init() {
        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: ClipboardPreviewLayout.previewWidth,
                height: ClipboardPreviewLayout.previewHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        ignoresMouseEvents = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        clearContentView.frame = NSRect(
            x: 0,
            y: 0,
            width: ClipboardPreviewLayout.previewWidth,
            height: ClipboardPreviewLayout.previewHeight
        )
        contentView = clearContentView

        hostingView.frame = clearContentView.bounds
        hostingView.autoresizingMask = [.width, .height]
        clearContentView.addSubview(hostingView)
    }

    func present(item: ClipboardItem, rowFrame: CGRect, windowFrame: CGRect) {
        let screenFrame = NSScreen.screens.first(where: { $0.frame.intersects(windowFrame) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? .zero
        let visibleWindowMinX = windowFrame.minX + ClipboardPreviewLayout.visibleNotchEdgeInset
        let visibleWindowMaxX = windowFrame.maxX - ClipboardPreviewLayout.visibleNotchEdgeInset

        let wantsRightPlacement = visibleWindowMaxX + ClipboardPreviewLayout.gutter + ClipboardPreviewLayout.previewWidth
            <= screenFrame.maxX - ClipboardPreviewLayout.screenEdgeInset

        let tailEdge: ClipboardBubbleTailEdge = wantsRightPlacement ? .left : .right
        let originX: CGFloat
        if wantsRightPlacement {
            originX = visibleWindowMaxX + ClipboardPreviewLayout.gutter
        } else {
            originX = max(
                screenFrame.minX + ClipboardPreviewLayout.screenEdgeInset,
                visibleWindowMinX - ClipboardPreviewLayout.previewWidth - ClipboardPreviewLayout.gutter
            )
        }

        let unclampedY = rowFrame.midY - ClipboardPreviewLayout.previewHeight / 2
        let originY = min(
            max(unclampedY, screenFrame.minY + ClipboardPreviewLayout.screenEdgeInset),
            screenFrame.maxY - ClipboardPreviewLayout.previewHeight - ClipboardPreviewLayout.screenEdgeInset
        )
        let panelTopY = originY + ClipboardPreviewLayout.previewHeight
        let tailCenterY = max(
            ClipboardPreviewLayout.cornerRadius + ClipboardPreviewLayout.tailHeight / 2,
            min(
                ClipboardPreviewLayout.previewHeight - ClipboardPreviewLayout.cornerRadius - ClipboardPreviewLayout.tailHeight / 2,
                panelTopY - rowFrame.midY
            )
        )

        hostingView.rootView = AnyView(
            ClipboardHoverPreview(
                item: item,
                tailEdge: tailEdge,
                tailCenterY: tailCenterY,
                onHoverChanged: { [weak self] isHovering in
                    self?.onHoverChanged?(isHovering)
                }
            )
        )

        setFrame(
            NSRect(
                x: originX,
                y: originY,
                width: ClipboardPreviewLayout.previewWidth,
                height: ClipboardPreviewLayout.previewHeight
            ),
            display: true
        )

        if !isVisible {
            orderFrontRegardless()
        } else {
            orderFront(nil)
        }
    }
}

private final class TransparentClipboardPreviewContentView: NSView {
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

private final class TransparentClipboardPreviewHostingView: NSHostingView<AnyView> {
    override var isOpaque: Bool { false }

    required init(rootView: AnyView) {
        super.init(rootView: rootView)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct ClipboardHoverPreview: View {
    let item: ClipboardItem
    let tailEdge: ClipboardBubbleTailEdge
    let tailCenterY: CGFloat
    let onHoverChanged: (Bool) -> Void

    private var sourceAppIcon: NSImage {
        if let bundleID = item.sourceBundleID,
           let icon = AppIconAsNSImage(for: bundleID) {
            return icon
        }

        let fallback = NSWorkspace.shared.icon(for: .applicationBundle)
        fallback.size = NSSize(width: 32, height: 32)
        return fallback
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ClipboardPreviewLayout.sectionSpacing) {
            if item.kind == .image, let payload = item.image {
                ClipboardImageThumbnailView(payload: payload, maxPixelSize: ClipboardPreviewLayout.previewWidth * 2)
                    .frame(maxWidth: .infinity)
                    .frame(height: ClipboardPreviewLayout.topContentHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    Text(item.normalizedContent)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineSpacing(0.5)
                        .padding(.bottom, 2)
                }
                .frame(height: ClipboardPreviewLayout.topContentHeight, alignment: .top)
            }

            Rectangle()
                .fill(Color.white.opacity(0.09))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: ClipboardPreviewLayout.metadataSpacing) {
                HStack(spacing: 8) {
                    Image(nsImage: sourceAppIcon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 12, height: 12)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))

                    Text(item.sourceAppName ?? "Unknown")
                        .foregroundStyle(.white.opacity(0.94))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }

                HStack(spacing: 14) {
                    compactMetaInline(title: "Last copied", value: item.lastCopiedAt.formatted(date: .abbreviated, time: .shortened))
                    compactMetaInline(title: "Copies", value: "\(item.copyCount)")
                    if let payload = item.image {
                        compactMetaInline(title: "Size", value: "\(payload.dimensionsLabel) px")
                    }
                    if item.isPinned {
                        compactMetaInline(title: "Pinned", value: "Yes")
                    }
                    Spacer(minLength: 0)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Text("Click to copy again. Hover out to dismiss.")
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(ClipboardTheme.tertiaryText)
        }
        .padding(.top, ClipboardPreviewLayout.contentVerticalPadding)
        .padding(.bottom, ClipboardPreviewLayout.contentVerticalPadding)
        .padding(.leading, (tailEdge == .left ? ClipboardPreviewLayout.tailWidth : 0) + ClipboardPreviewLayout.contentHorizontalPadding)
        .padding(.trailing, (tailEdge == .right ? ClipboardPreviewLayout.tailWidth : 0) + ClipboardPreviewLayout.contentHorizontalPadding)
        .frame(
            width: ClipboardPreviewLayout.previewWidth,
            height: ClipboardPreviewLayout.previewHeight,
            alignment: .topLeading
        )
        .background(
            ClipboardBubbleShape(tailEdge: tailEdge, tailCenterY: tailCenterY)
                .fill(ClipboardTheme.bubbleBackground)
                .overlay(
                    ClipboardBubbleShape(tailEdge: tailEdge, tailCenterY: tailCenterY)
                        .stroke(ClipboardTheme.border.opacity(0.9), lineWidth: 1)
                )
        )
        .onHover(perform: onHoverChanged)
    }

    private func compactMetaInline(title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(ClipboardTheme.secondaryText)
            Text(value)
                .foregroundStyle(.white.opacity(0.92))
        }
        .font(.system(size: 10.5, weight: .medium, design: .rounded))
        .foregroundStyle(.white.opacity(0.92))
    }
}

private struct ClipboardBubbleShape: Shape {
    let tailEdge: ClipboardBubbleTailEdge
    let tailCenterY: CGFloat

    func path(in rect: CGRect) -> Path {
        let cornerRadius = ClipboardPreviewLayout.cornerRadius
        let tailWidth = ClipboardPreviewLayout.tailWidth
        let tailHeight = ClipboardPreviewLayout.tailHeight
        let joinHalfHeight = tailHeight * 0.18
        let bellyHalfHeight = tailHeight * 0.46
        let resolvedTailCenterY = min(
            max(cornerRadius + bellyHalfHeight, tailCenterY),
            rect.height - cornerRadius - bellyHalfHeight
        )
        let bodyRect: CGRect = {
            switch tailEdge {
            case .left:
                return CGRect(x: tailWidth, y: 0, width: rect.width - tailWidth, height: rect.height)
            case .right:
                return CGRect(x: 0, y: 0, width: rect.width - tailWidth, height: rect.height)
            }
        }()
        let upperJoinY = resolvedTailCenterY - joinHalfHeight
        let lowerJoinY = resolvedTailCenterY + joinHalfHeight
        let minX = bodyRect.minX
        let maxX = bodyRect.maxX
        let minY = bodyRect.minY
        let maxY = bodyRect.maxY
        let bodyInsetControl = tailWidth * 0.22
        let tipControlXLeft = rect.minX + tailWidth * 0.34
        let tipControlXRight = rect.maxX - tailWidth * 0.34

        var path = Path()

        switch tailEdge {
        case .left:
            path.move(to: CGPoint(x: minX + cornerRadius, y: minY))
            path.addLine(to: CGPoint(x: maxX - cornerRadius, y: minY))
            path.addQuadCurve(
                to: CGPoint(x: maxX, y: minY + cornerRadius),
                control: CGPoint(x: maxX, y: minY)
            )
            path.addLine(to: CGPoint(x: maxX, y: maxY - cornerRadius))
            path.addQuadCurve(
                to: CGPoint(x: maxX - cornerRadius, y: maxY),
                control: CGPoint(x: maxX, y: maxY)
            )
            path.addLine(to: CGPoint(x: minX + cornerRadius, y: maxY))
            path.addQuadCurve(
                to: CGPoint(x: minX, y: maxY - cornerRadius),
                control: CGPoint(x: minX, y: maxY)
            )
            path.addLine(to: CGPoint(x: minX, y: lowerJoinY))
            path.addCurve(
                to: CGPoint(x: rect.minX + 0.25, y: resolvedTailCenterY),
                control1: CGPoint(x: minX + bodyInsetControl, y: resolvedTailCenterY + bellyHalfHeight),
                control2: CGPoint(x: tipControlXLeft, y: resolvedTailCenterY + tailHeight * 0.14)
            )
            path.addCurve(
                to: CGPoint(x: minX, y: upperJoinY),
                control1: CGPoint(x: tipControlXLeft, y: resolvedTailCenterY - tailHeight * 0.14),
                control2: CGPoint(x: minX + bodyInsetControl, y: resolvedTailCenterY - bellyHalfHeight)
            )
            path.addLine(to: CGPoint(x: minX, y: minY + cornerRadius))
            path.addQuadCurve(
                to: CGPoint(x: minX + cornerRadius, y: minY),
                control: CGPoint(x: minX, y: minY)
            )
        case .right:
            path.move(to: CGPoint(x: minX + cornerRadius, y: minY))
            path.addLine(to: CGPoint(x: maxX - cornerRadius, y: minY))
            path.addQuadCurve(
                to: CGPoint(x: maxX, y: minY + cornerRadius),
                control: CGPoint(x: maxX, y: minY)
            )
            path.addLine(to: CGPoint(x: maxX, y: upperJoinY))
            path.addCurve(
                to: CGPoint(x: rect.maxX - 0.25, y: resolvedTailCenterY),
                control1: CGPoint(x: maxX - bodyInsetControl, y: resolvedTailCenterY - bellyHalfHeight),
                control2: CGPoint(x: tipControlXRight, y: resolvedTailCenterY - tailHeight * 0.14)
            )
            path.addCurve(
                to: CGPoint(x: maxX, y: lowerJoinY),
                control1: CGPoint(x: tipControlXRight, y: resolvedTailCenterY + tailHeight * 0.14),
                control2: CGPoint(x: maxX - bodyInsetControl, y: resolvedTailCenterY + bellyHalfHeight)
            )
            path.addLine(to: CGPoint(x: maxX, y: maxY - cornerRadius))
            path.addQuadCurve(
                to: CGPoint(x: maxX - cornerRadius, y: maxY),
                control: CGPoint(x: maxX, y: maxY)
            )
            path.addLine(to: CGPoint(x: minX + cornerRadius, y: maxY))
            path.addQuadCurve(
                to: CGPoint(x: minX, y: maxY - cornerRadius),
                control: CGPoint(x: minX, y: maxY)
            )
            path.addLine(to: CGPoint(x: minX, y: minY + cornerRadius))
            path.addQuadCurve(
                to: CGPoint(x: minX + cornerRadius, y: minY),
                control: CGPoint(x: minX, y: minY)
            )
        }

        path.closeSubpath()
        return path
    }
}
