//
//  ClipboardHistoryPanelView.swift
//  boringNotch
//

import AppKit
import Defaults
import Sparkle
import SwiftUI

struct ClipboardHistoryPanelView: View {
    @ObservedObject private var viewModel = ClipboardHistoryViewModel.shared
    @Default(.clipboardHistoryEnabled) private var historyEnabled
    @Default(.clipboardHistoryShowSourceApps) private var showSourceApps

    let updater: SPUUpdater?

    init(updater: SPUUpdater? = nil) {
        self.updater = updater
    }

    var body: some View {
        ZStack {
            ClipboardPanelBackground()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 12)

                if historyEnabled {
                    activeContent
                } else {
                    ClipboardOnboardingView {
                        viewModel.enableHistory()
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                }

                footer
            }
        }
        .frame(width: 430, height: 580)
        .onAppear {
            viewModel.start()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.thinMaterial)
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .frame(width: 46, height: 46)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.quaternary, lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text("Clipboard")
                        .font(.system(size: 25, weight: .semibold, design: .default))
                        .foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.isMonitoring ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                        Text(viewModel.statusText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if historyEnabled {
                    Button {
                        viewModel.toggleUserPaused()
                    } label: {
                        Image(systemName: viewModel.isUserPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 31, height: 31)
                            .background(.thinMaterial, in: Circle())
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.primary)
                    .help(viewModel.isUserPaused ? "Resume clipboard history" : "Pause clipboard history")
                }
            }

            if historyEnabled {
                ClipboardSearchField(text: $viewModel.searchText)
            }
        }
    }

    private var activeContent: some View {
        VStack(spacing: 12) {
            filterBar
                .padding(.horizontal, 18)

            if viewModel.items.isEmpty {
                ClipboardEmptyStateView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 18)
            } else if viewModel.visibleItems.isEmpty {
                ClipboardNoResultsView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 18)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(viewModel.sections) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(section.title)
                                    .font(.caption.weight(.semibold))
                                    .textCase(.uppercase)
                                    .tracking(0.8)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 2)

                                ForEach(section.items) { item in
                                    ClipboardHistoryRow(
                                        item: item,
                                        image: viewModel.thumbnail(for: item),
                                        sourceIcon: showSourceApps ? viewModel.sourceIcon(for: item) : nil,
                                        isCopied: viewModel.copiedItemID == item.id,
                                        onCopy: { viewModel.copy(item) },
                                        onPin: { viewModel.togglePinned(item) },
                                        onDelete: { viewModel.remove(item) }
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.never)
            }
        }
    }

    private var filterBar: some View {
        Picker("Clipboard Filter", selection: $viewModel.selectedFilter) {
            ForEach(ClipboardHistoryFilter.allCases) { filter in
                Label(filter.label, systemImage: filter.systemImage)
                    .tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(.separator)

            HStack(spacing: 10) {
                Text("\(viewModel.items.count) items")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(viewModel.storageText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)

                Spacer()

                if historyEnabled && !viewModel.items.isEmpty {
                    Button("Clear") {
                        viewModel.clear()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .font(.caption.weight(.semibold))
                }

                if let updater {
                    CheckForUpdatesView(updater: updater)
                        .font(.caption.weight(.semibold))
                }

                Button("Settings") {
                    SettingsWindowController.shared.showWindow()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .font(.caption.weight(.semibold))

                Menu {
                    Button("Restart minitap") {
                        ApplicationRelauncher.restart()
                    }
                    Button("Quit", role: .destructive) {
                        NSApplication.shared.terminate(nil)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 26, height: 26)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
    }
}

private struct ClipboardPanelBackground: View {
    var body: some View {
        Rectangle()
            .fill(.regularMaterial)
            .overlay(Color(nsColor: .windowBackgroundColor).opacity(0.18))
        .ignoresSafeArea()
    }
}

private struct ClipboardSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("Search history", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
    }
}

private struct ClipboardHistoryRow: View {
    let item: ClipboardHistoryItem
    let image: NSImage?
    let sourceIcon: NSImage?
    let isCopied: Bool
    let onCopy: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onCopy) {
                HStack(alignment: .center, spacing: 12) {
                    thumbnail
                    textContent
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            rowActions
                .opacity(isHovering || isCopied ? 1 : 0)
                .animation(.smooth(duration: 0.16), value: isHovering)
        }
        .padding(10)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isHovering ? Color.primary.opacity(0.13) : Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(isHovering ? 0.16 : 0.07), radius: isHovering ? 10 : 4, y: 4)
        .scaleEffect(isHovering ? 1.01 : 1)
        .onHover { hovering in
            isHovering = hovering
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Copies this item back to the clipboard")
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Text(item.previewTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(item.kind == .text ? 2 : 1)
                    .multilineTextAlignment(.leading)

                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.effectiveAccent)
                }
            }

            Text(item.detailText)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                if let sourceIcon {
                    Image(nsImage: sourceIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 15, height: 15)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else {
                    Image(systemName: item.kind.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                }

                Text(sourceLine)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isCopied {
                    Label("Copied", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)

            if item.kind == .image, let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 66, height: 66)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                Image(systemName: item.kind.systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 66, height: 66)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    private var rowActions: some View {
        HStack(spacing: 6) {
            Button(action: onPin) {
                Image(systemName: item.isPinned ? "pin.slash" : "pin")
                    .frame(width: 25, height: 25)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .help(item.isPinned ? "Unpin" : "Pin")

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .frame(width: 25, height: 25)
                    .background(.thinMaterial, in: Circle())
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Delete")
        }
        .foregroundStyle(.primary)
    }

    private var rowBackground: some ShapeStyle {
        if isCopied {
            return AnyShapeStyle(Color.green.opacity(0.14))
        }
        if isHovering {
            return AnyShapeStyle(.regularMaterial)
        }
        return AnyShapeStyle(.thinMaterial)
    }

    private var sourceLine: String {
        let app = item.sourceAppName ?? "Unknown app"
        let relative = RelativeDateTimeFormatter.clipboardFormatter.localizedString(for: item.createdAt, relativeTo: Date())
        return "\(app) • \(relative)"
    }

    private var accessibilityLabel: String {
        "\(item.kind.label), \(item.previewTitle), \(sourceLine)"
    }
}

private struct ClipboardOnboardingView: View {
    let onEnable: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 10)

            ZStack {
                Circle()
                    .fill(Color.effectiveAccent.opacity(0.16))
                    .frame(width: 118, height: 118)
                    .blur(radius: 18)
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.thinMaterial)
                    .frame(width: 92, height: 92)
                    .overlay(
                        Image(systemName: "sparkles.rectangle.stack")
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundStyle(Color.effectiveAccent)
                    )
            }

            VStack(spacing: 8) {
                Text("Your clipboard, beautifully remembered")
                    .font(MinitapBrand.Fonts.heading(size: 24))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text("minitap can save copied text and real image data, then bring it back with one click from the menu bar.")
                    .font(MinitapBrand.Fonts.body(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 8)
            }

            VStack(alignment: .leading, spacing: 10) {
                ClipboardPrivacyPoint(icon: "lock.shield", text: "Opt-in only. Nothing is recorded until you enable it.")
                ClipboardPrivacyPoint(icon: "eye.slash", text: "Private and transient pasteboard items are skipped.")
                ClipboardPrivacyPoint(icon: "photo", text: "Images are stored locally as bounded PNG history.")
            }
            .padding(14)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Button(action: onEnable) {
                Text("Enable Clipboard History")
                    .font(MinitapBrand.Fonts.body(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.effectiveAccent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 6)
        }
    }
}

private struct ClipboardPrivacyPoint: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.effectiveAccent)
                .frame(width: 18)
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}

private struct ClipboardEmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 74, height: 74)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            Text("Copy something")
                .font(.system(size: 20, weight: .semibold, design: .default))
                .foregroundStyle(.primary)
            Text("Text and screenshots you copy from now on will appear here.")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

private struct ClipboardNoResultsView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("No matches")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("Try another search or filter.")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

private extension RelativeDateTimeFormatter {
    static let clipboardFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

#Preview {
    ClipboardHistoryPanelView()
}
