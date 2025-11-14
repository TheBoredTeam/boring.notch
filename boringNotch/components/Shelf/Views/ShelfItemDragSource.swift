//
//  ShelfItemDragSource.swift
//  boringNotch
//
//  Created for shelf auto-remove feature
//

import Foundation
import AppKit
import Defaults

/// Service to monitor file access and handle auto-removal of shelf items after drag operations
@MainActor
final class ShelfItemDragMonitor {
    static let shared = ShelfItemDragMonitor()

    private var fileMonitors: [UUID: DispatchSourceFileSystemObject] = [:]
    private var monitoredURLs: [UUID: URL] = [:]

    private init() {}

    /// Monitor a file after drag begins to detect when it's safe to delete from shelf
    func monitorFileForDrag(itemID: UUID, url: URL, completion: @escaping () -> Void) {
        // Clean up any existing monitor for this item
        cancelMonitor(for: itemID)

        monitoredURLs[itemID] = url

        // Start monitoring on background queue
        Task.detached(priority: .utility) { [weak self] in
            await self?.startFileMonitoring(itemID: itemID, url: url, completion: completion)
        }
    }

    /// Cancel monitoring for a specific item (e.g., if drag was cancelled)
    func cancelMonitor(for itemID: UUID) {
        fileMonitors[itemID]?.cancel()
        fileMonitors.removeValue(forKey: itemID)
        monitoredURLs.removeValue(forKey: itemID)
    }

    private func startFileMonitoring(itemID: UUID, url: URL, completion: @escaping () -> Void) async {
        let fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            // File already gone or inaccessible, safe to delete from shelf
            await MainActor.run {
                self.cancelMonitor(for: itemID)
                completion()
            }
            return
        }

        // Create dispatch source to monitor file events
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.delete, .write, .extend, .attrib, .link, .rename],
            queue: DispatchQueue.global(qos: .utility)
        )

        var hasBeenAccessed = false
        let startTime = Date()

        source.setEventHandler { [weak self] in
            hasBeenAccessed = true

            // File was accessed for copy operation
            // Now wait for the file to no longer be in use
            Task {
                await self?.waitForFileAvailability(itemID: itemID, url: url, startTime: startTime, completion: completion)
            }
        }

        source.setCancelHandler {
            close(fileDescriptor)
        }

        await MainActor.run {
            self.fileMonitors[itemID] = source
        }

        source.resume()

        // Fallback: If no file access detected after 1 second,
        // assume operation completed or was cancelled
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0) { [weak self] in
            if !hasBeenAccessed {
                Task { @MainActor [weak self] in
                    self?.cancelMonitor(for: itemID)
                    completion()
                }
            }
        }
    }

    private func waitForFileAvailability(itemID: UUID, url: URL, startTime: Date, completion: @escaping () -> Void) async {
        func checkFile() async {
            // Check if file is still being accessed
            let fileHandle = try? FileHandle(forReadingFrom: url)
            fileHandle?.closeFile()

            // If we can't open the file, it might be locked - wait and retry
            if fileHandle == nil {
                // Timeout after 10 minutes
                if Date().timeIntervalSince(startTime) < 600 {
                    try? await Task.sleep(for: .milliseconds(500))
                    await checkFile()
                } else {
                    await MainActor.run {
                        self.cancelMonitor(for: itemID)
                        completion()
                    }
                }
            } else {
                // File is accessible and not locked, safe to delete
                await MainActor.run {
                    self.cancelMonitor(for: itemID)
                    completion()
                }
            }
        }

        // Wait 500ms after last file event before checking
        try? await Task.sleep(for: .milliseconds(500))
        await checkFile()
    }
}

/// Extension to DraggableClickView to support auto-remove functionality
extension ShelfItemDragMonitor {
    /// Handle drag end for auto-remove feature
    func handleDragEnd(
        for items: [ShelfItem],
        operation: NSDragOperation,
        autoRemoveEnabled: Bool
    ) {
        // Only proceed if auto-remove is enabled and drag succeeded (not cancelled)
        guard autoRemoveEnabled && !operation.isEmpty else { return }

        // Monitor each file item
        for item in items {
            guard case .file = item.kind else {
                // For non-file items (text, links), remove immediately
                ShelfStateViewModel.shared.remove(item)
                continue
            }

            // For file items, monitor the file to ensure copy is complete
            if let url = ShelfStateViewModel.shared.resolveFileURL(for: item) {
                monitorFileForDrag(itemID: item.id, url: url) {
                    ShelfStateViewModel.shared.remove(item)
                }
            }
        }
    }
}
