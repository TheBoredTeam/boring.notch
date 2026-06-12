import AppKit
import Combine
import Defaults
import SwiftUI

@MainActor
final class ClipboardStateViewModel: ObservableObject {
    static let shared = ClipboardStateViewModel()
    private static let hoverPreviewDelay: TimeInterval = 0.5

    // Mirrors macOS screenshot file naming: "Image 2026-06-11 at 12.24.01 PM".
    private static let imageNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' h.mm.ss a"
        return formatter
    }()

    @Published private(set) var items: [ClipboardItem] = []
    @Published var searchQuery: String = ""
    @Published private(set) var historyEnabled = Defaults[.clipboardHistoryEnabled]
    @Published private(set) var maxStoredItems = Defaults[.clipboardMaxEntries]
    @Published private(set) var ignoredBundleIDs = Defaults[.clipboardIgnoredBundleIDs]
    @Published private(set) var showCopiedFlash = false
    @Published private(set) var copiedItemID: ClipboardItem.ID?
    @Published private(set) var hoveredItemID: ClipboardItem.ID?
    @Published private(set) var keepsNotchOpenOnHoverExit = false
    @Published private(set) var searchFocusRequestID = UUID()

    private let persistence = ClipboardPersistenceService.shared
    private let monitor = ClipboardMonitorService.shared
    private var collection: ClipboardCollection
    private var interactionState = ClipboardTransientInteractionState()
    private var cancellables = Set<AnyCancellable>()
    private var flashTask: Task<Void, Never>?
    private var copiedItemTask: Task<Void, Never>?
    private var hoverPreviewPanel: ClipboardHoverPreviewPanel?
    private var showPreviewWorkItem: DispatchWorkItem?
    private var hidePreviewWorkItem: DispatchWorkItem?
    private var isPointerOverHoveredRow = false
    private var isPointerOverPreviewPanel = false
    private var didStart = false
    // One-shot sha256 marker so a copy-back picked up by the poller isn't
    // re-registered as a fresh capture from an unrelated frontmost app.
    private var suppressedCaptureFingerprint: String?
    private var knownImageFileNames: Set<String> = []

    private init() {
        let loadedItems = persistence.load()
        let collection = ClipboardCollection(
            items: loadedItems ?? [],
            maxStoredItems: Defaults[.clipboardMaxEntries]
        )
        self.collection = collection
        self.items = collection.orderedItems
        self.knownImageFileNames = Set(collection.orderedItems.compactMap { $0.image?.fileName })
        // A failed load (loadedItems == nil) must not be mistaken for an
        // empty history — pruning against it would delete every blob.
        if loadedItems != nil {
            ClipboardImageStore.shared.pruneOrphans(keeping: knownImageFileNames)
        }
        configureMonitor()
        observeDefaults()
    }

    var isEmpty: Bool {
        filteredItems.isEmpty
    }

    var filteredItems: [ClipboardItem] {
        collection.filteredItems(matching: searchQuery)
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        configureMonitor()
        if historyEnabled {
            monitor.start()
        }
    }

    func stop() {
        monitor.stop()
        hideHoverPreview(force: true)
        flashTask?.cancel()
        flashTask = nil
        copiedItemTask?.cancel()
        copiedItemTask = nil
        copiedItemID = nil
        interactionState = ClipboardTransientInteractionState()
        didStart = false
    }

    func requestSearchFocus() {
        searchFocusRequestID = UUID()
    }

    func copy(_ item: ClipboardItem) {
        switch item.kind {
        case .text:
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(item.content, forType: .string)
            monitor.syncChangeCountToCurrentPasteboard()
            presentCopiedFeedback(message: "Copied to clipboard")
            presentCopiedRowFeedback(for: item.id)
        case .image:
            guard let image = item.image else { return }
            suppressedCaptureFingerprint = image.sha256
            Task { [weak self] in
                let fileName = image.fileName
                let prepared = await Task.detached(priority: .userInitiated) { () -> (Data, Data?)? in
                    guard let data = ClipboardImageStore.shared.loadData(named: fileName) else {
                        return nil
                    }
                    return (data, NSImage(data: data)?.tiffRepresentation)
                }.value

                guard let self else { return }
                guard let (data, tiff) = prepared else {
                    // The blob is gone; the entry can never be copied again.
                    self.suppressedCaptureFingerprint = nil
                    self.delete(item)
                    return
                }

                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setData(data, forType: .png)
                if let tiff {
                    pasteboard.setData(tiff, forType: .tiff)
                }
                self.monitor.syncChangeCountToCurrentPasteboard()
                self.presentCopiedFeedback(message: "Copied to clipboard")
                self.presentCopiedRowFeedback(for: item.id)
            }
        }
    }

    func togglePin(_ item: ClipboardItem) {
        collection.togglePin(for: item.id)
        syncItemsFromCollection()
        persistItems()
    }

    func delete(_ item: ClipboardItem) {
        collection.delete(item.id)
        syncItemsFromCollection()
        if hoveredItemID == item.id {
            hoveredItemID = nil
        }
        hideHoverPreview(force: true)
        persistItems()
    }

    func clearNonPinned() {
        collection.clearNonPinned()
        syncItemsFromCollection()
        hoveredItemID = nil
        hideHoverPreview(force: true)
        persistItems()
    }

    func setHoveredItemID(_ id: ClipboardItem.ID?) {
        hoveredItemID = id
        interactionState.setHoveredItemID(id)
    }

    func setPointerOverHoveredRow(_ isHovering: Bool) {
        if !isHovering {
            showPreviewWorkItem?.cancel()
            showPreviewWorkItem = nil
        }
        isPointerOverHoveredRow = isHovering
        interactionState.setPointerOverHoveredRow(isHovering)
        updatePreviewVisibility()
    }

    func setPointerOverPreviewPanel(_ isHovering: Bool) {
        isPointerOverPreviewPanel = isHovering
        interactionState.setPointerOverPreviewPanel(isHovering)
        updatePreviewVisibility()
    }

    func showHoverPreview(for item: ClipboardItem, rowFrame: CGRect, windowFrame: CGRect) {
        showPreviewWorkItem?.cancel()
        hidePreviewWorkItem?.cancel()
        let panel = hoverPreviewPanel ?? ClipboardHoverPreviewPanel()
        hoverPreviewPanel = panel
        panel.onHoverChanged = { [weak self] isHovering in
            Task { @MainActor in
                self?.setPointerOverPreviewPanel(isHovering)
            }
        }

        let presentPreview = { [weak self] in
            guard let self else { return }
            panel.present(item: item, rowFrame: rowFrame, windowFrame: windowFrame)
            self.keepsNotchOpenOnHoverExit = true
        }

        if panel.isVisible {
            presentPreview()
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                guard self.interactionState.shouldPresentPreview(for: item.id) else { return }
                presentPreview()
            }
        }
        showPreviewWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hoverPreviewDelay, execute: workItem)
    }

    func hideHoverPreview(force: Bool = false) {
        showPreviewWorkItem?.cancel()
        showPreviewWorkItem = nil
        hidePreviewWorkItem?.cancel()
        hoverPreviewPanel?.orderOut(nil)
        interactionState.resetPreviewHover()
        isPointerOverHoveredRow = interactionState.isPointerOverHoveredRow
        isPointerOverPreviewPanel = interactionState.isPointerOverPreviewPanel
        if force {
            keepsNotchOpenOnHoverExit = false
        } else {
            Task { @MainActor in
                self.keepsNotchOpenOnHoverExit = false
            }
        }
    }

    func addIgnoredBundleID(_ bundleID: String) {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var next = Set(ignoredBundleIDs)
        next.insert(trimmed)
        Defaults[.clipboardIgnoredBundleIDs] = next.sorted()
    }

    func removeIgnoredBundleID(_ bundleID: String) {
        Defaults[.clipboardIgnoredBundleIDs] = ignoredBundleIDs.filter { $0 != bundleID }
    }

    private func configureMonitor() {
        monitor.onCapture = { [weak self] capture in
            self?.handleCapture(capture)
        }
        monitor.setIgnoredBundleIDs(Set(ignoredBundleIDs))
    }

    private func observeDefaults() {
        Defaults.publisher(.clipboardHistoryEnabled)
            .sink { [weak self] change in
                guard let self else { return }
                self.historyEnabled = change.newValue
                if change.newValue {
                    self.monitor.start()
                } else {
                    self.monitor.stop()
                    self.hideHoverPreview(force: true)
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.clipboardMaxEntries)
            .sink { [weak self] change in
                guard let self else { return }
                self.collection.setMaxStoredItems(change.newValue)
                self.maxStoredItems = self.collection.maxStoredItems
                self.syncItemsFromCollection()
                self.persistItems()
            }
            .store(in: &cancellables)

        Defaults.publisher(.clipboardIgnoredBundleIDs)
            .sink { [weak self] change in
                self?.ignoredBundleIDs = change.newValue
                self?.monitor.setIgnoredBundleIDs(Set(change.newValue))
            }
            .store(in: &cancellables)
    }

    private func handleCapture(_ capture: ClipboardCapture) {
        guard historyEnabled else { return }
        if let sourceBundleID = capture.sourceBundleID,
           sourceBundleID == Bundle.main.bundleIdentifier {
            return
        }
        if let bundleID = capture.sourceBundleID, ignoredBundleIDs.contains(bundleID) {
            return
        }

        let suppressedFingerprint = suppressedCaptureFingerprint
        suppressedCaptureFingerprint = nil

        switch capture.payload {
        case .text(let text):
            collection.registerCopy(
                content: text,
                sourceAppName: capture.sourceAppName,
                sourceBundleID: capture.sourceBundleID
            )
            finishCaptureRegistration()
        case .image(let data, let sha256, let pixelWidth, let pixelHeight):
            // Our own copy-back re-observed by the poller — not a new copy.
            if sha256 == suppressedFingerprint { return }

            if let existingPayload = collection.orderedItems
                .first(where: { $0.kind == .image && $0.image?.sha256 == sha256 })?
                .image {
                registerImageCapture(payload: existingPayload, capture: capture)
                return
            }

            let payload = ClipboardImagePayload(
                fileName: "\(UUID().uuidString).png",
                sha256: sha256,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                byteCount: data.count
            )
            Task { [weak self] in
                let saved = await Task.detached(priority: .utility) {
                    ClipboardImageStore.shared.save(data, named: payload.fileName)
                }.value
                guard saved, let self else { return }
                self.registerImageCapture(payload: payload, capture: capture)
            }
        }
    }

    private func registerImageCapture(payload: ClipboardImagePayload, capture: ClipboardCapture) {
        collection.registerCopy(
            content: "Image \(Self.imageNameFormatter.string(from: Date()))",
            kind: .image,
            image: payload,
            sourceAppName: capture.sourceAppName,
            sourceBundleID: capture.sourceBundleID
        )
        finishCaptureRegistration()
    }

    private func finishCaptureRegistration() {
        syncItemsFromCollection()
        persistItems()
        presentCopiedFeedback(message: "Copied to clipboard")
    }

    private func persistItems() {
        let orderedItems = collection.orderedItems
        persistence.save(orderedItems)

        // Blobs whose items just left the history (deleted, cleared, or
        // evicted by the entry limit) are removed immediately; the age-guarded
        // orphan sweep at launch only handles crash leftovers.
        let currentFileNames = Set(orderedItems.compactMap { $0.image?.fileName })
        for removed in knownImageFileNames.subtracting(currentFileNames) {
            ClipboardImageStore.shared.delete(named: removed)
        }
        knownImageFileNames = currentFileNames
    }

    private func syncItemsFromCollection() {
        items = collection.orderedItems
    }

    private func presentCopiedFeedback(message _: String) {
        showCopiedFlash = true
        flashTask?.cancel()
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.showCopiedFlash = false
            }
        }
    }

    private func presentCopiedRowFeedback(for id: ClipboardItem.ID) {
        copiedItemID = id
        interactionState.markCopied(id)
        copiedItemTask?.cancel()
        copiedItemTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.9))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.interactionState.clearCopied(ifMatches: id)
                if self?.interactionState.copiedItemID == nil {
                    self?.copiedItemID = nil
                }
            }
        }
    }

    private func updatePreviewVisibility() {
        if interactionState.shouldHidePreview() {
            showPreviewWorkItem?.cancel()
            showPreviewWorkItem = nil
        }
        hidePreviewWorkItem?.cancel()

        guard interactionState.shouldHidePreview() else {
            keepsNotchOpenOnHoverExit = true
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                if self.interactionState.shouldHidePreview() {
                    self.hideHoverPreview(force: true)
                }
            }
        }
        hidePreviewWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: workItem)
    }
}
