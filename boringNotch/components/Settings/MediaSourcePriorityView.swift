//
//  MediaSourcePriorityView.swift
//  boringNotch
//
//  Settings editor for the ordered media-source priority list: enable the sources you use and set
//  their priority by dragging the handle. The notch shows whichever enabled source is audibly
//  playing, preferring the one higher in the list. Generic "Now Playing" is pinned last.
//
//  Reorder interaction is gesture-based (no .onDrag/.onDrop): dragging the handle moves the row with
//  the cursor and the list is committed on release. The gesture is measured in the GLOBAL coordinate
//  space — measuring in the default local space fed the row's own movement back into the translation
//  and made it jitter. There is also no system drag image / ghost.
//

import Defaults
import SwiftUI

struct MediaSourcePriorityView: View {
    @Default(.mediaSourcePriority) private var sources
    @ObservedObject private var musicManager = MusicManager.shared

    @State private var draggingType: MediaControllerType?
    @State private var dragTranslation: CGFloat = 0
    @State private var dragStartIndex: Int?

    private let rowHeight: CGFloat = 30
    private let rowSpacing: CGFloat = 6
    private var rowPitch: CGFloat { rowHeight + rowSpacing }

    var body: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            ForEach(appEntries) { entry in
                let isDragging = draggingType == entry.type
                row(for: entry, draggable: true)
                    .offset(y: isDragging ? dragTranslation : 0)
                    .scaleEffect(isDragging ? 1.02 : 1)
                    .shadow(color: .black.opacity(isDragging ? 0.28 : 0), radius: 6, y: 3)
                    .zIndex(isDragging ? 1 : 0)
                    // Whole row is draggable; simultaneous so taps still reach the enable toggle.
                    .simultaneousGesture(dragGesture(for: entry.type))
            }

            // Generic Now Playing is always last and not reorderable. Hidden when deprecated on this OS.
            if !musicManager.isNowPlayingDeprecated, let nowPlaying = nowPlayingEntry {
                Divider().padding(.vertical, 2)
                row(for: nowPlaying, draggable: false)
            }

            HStack {
                Spacer()
                Button("Reset to Defaults") { reset() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            .padding(.top, 4)
        }
        .onAppear { normalizeSources() }
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(for entry: MediaSourceEntry, draggable: Bool) -> some View {
        HStack(spacing: 10) {
            handle(draggable: draggable)

            Toggle("", isOn: enabledBinding(for: entry.type))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)

            Text(entry.type.localizedString)
                .foregroundStyle(entry.isEnabled ? .primary : .secondary)

            Spacer()
        }
        .frame(height: rowHeight)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(draggable ? 0.5 : 0.25))
        )
        .contentShape(Rectangle())
    }

    /// Visual drag affordance only — the reorder gesture is on the whole row (see body). The pinned
    /// Now Playing row shows a hidden placeholder for alignment.
    private func handle(draggable: Bool) -> some View {
        Image(systemName: "line.3.horizontal")
            .foregroundStyle(draggable ? Color.secondary : Color.clear)
            .font(.body)
            .help(draggable ? "Drag to reorder" : "")
    }

    // MARK: - Drag-to-reorder (follow-finger in global space, commit on release)

    private func dragGesture(for type: MediaControllerType) -> some Gesture {
        // GLOBAL coordinate space: translation is measured against the screen, not the moving row, so
        // offsetting the dragged row doesn't feed back into the measurement (the cause of the jitter).
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { value in
                if draggingType != type {
                    draggingType = type
                    dragStartIndex = appEntries.firstIndex(where: { $0.type == type })
                }
                dragTranslation = value.translation.height
            }
            .onEnded { value in
                guard let start = dragStartIndex else {
                    draggingType = nil; dragTranslation = 0; dragStartIndex = nil
                    return
                }
                let steps = Int((value.translation.height / rowPitch).rounded())
                let target = max(0, min(appEntries.count - 1, start + steps))
                let changed = target != start
                let capturedType = type
                dragStartIndex = nil
                // Commit on the next runloop tick — mutating the ForEach data inside the gesture's own
                // onEnded can leave the just-dragged row's gesture stuck (handle stops responding).
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if changed { moveToIndex(capturedType, target) }
                        dragTranslation = 0
                        draggingType = nil
                    }
                    if changed { notifyChanged() }
                }
            }
    }

    private func moveToIndex(_ type: MediaControllerType, _ target: Int) {
        var apps = appEntries
        let others = sources.filter { $0.type == .nowPlaying }
        guard let from = apps.firstIndex(where: { $0.type == type }),
              apps.indices.contains(target), from != target else { return }
        let item = apps.remove(at: from)
        apps.insert(item, at: target)
        sources = apps + others
    }

    // MARK: - Derived

    private var appEntries: [MediaSourceEntry] {
        sources.filter { $0.type != .nowPlaying }
    }

    private var nowPlayingEntry: MediaSourceEntry? {
        sources.first { $0.type == .nowPlaying }
    }

    // MARK: - Mutation

    private func enabledBinding(for type: MediaControllerType) -> Binding<Bool> {
        Binding(
            get: { sources.first { $0.type == type }?.isEnabled ?? false },
            set: { newValue in setEnabled(type, newValue) }
        )
    }

    private func setEnabled(_ type: MediaControllerType, _ enabled: Bool) {
        guard let index = sources.firstIndex(where: { $0.type == type }) else { return }
        sources[index].isEnabled = enabled
        notifyChanged()
    }

    private func reset() {
        sources = MediaSourceEntry.defaultList(isNowPlayingDeprecated: musicManager.isNowPlayingDeprecated)
        notifyChanged()
    }

    /// Ensure every source appears exactly once (preserving app order) with Now Playing pinned last,
    /// so a stale/partial stored value still renders a complete, well-formed list.
    private func normalizeSources() {
        var seen = Set<MediaControllerType>()
        var apps: [MediaSourceEntry] = []
        for entry in sources where entry.type != .nowPlaying {
            if seen.insert(entry.type).inserted { apps.append(entry) }
        }
        for type in MediaSourceEntry.canonicalOrder where type != .nowPlaying && !seen.contains(type) {
            apps.append(MediaSourceEntry(type: type, isEnabled: false))
        }
        let nowPlaying = sources.first { $0.type == .nowPlaying }
            ?? MediaSourceEntry(type: .nowPlaying, isEnabled: false)
        let normalized = apps + [nowPlaying]
        if normalized != sources { sources = normalized }
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: Notification.Name.mediaControllerChanged, object: nil)
    }
}
