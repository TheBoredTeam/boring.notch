//  ScreenshotStore+Index.swift
//  IslandNotch
//
//  Purpose: index.json read/write (atomic, serialized) and reconciliation of
//           the in-memory list against the PNGs actually on disk.
//  Layer: Service

import Foundation

/// Serializes all index.json file IO so a capture landing during a retention
/// sweep can't clobber the file. An actor gives us a single writer for free.
actor IndexIO {
    private let encoder = ScreenshotIndex.makeEncoder()
    private let decoder = ScreenshotIndex.makeDecoder()

    /// Reads and decodes index.json, returning an empty index if absent/corrupt.
    func read(at url: URL) -> ScreenshotIndex {
        guard let data = try? Data(contentsOf: url) else {
            return ScreenshotIndex()
        }
        do {
            return try decoder.decode(ScreenshotIndex.self, from: data)
        } catch {
            Log.store.error("index.json decode failed, starting fresh: \(error.localizedDescription)")
            return ScreenshotIndex()
        }
    }

    /// Atomically writes the index: encode → temp file in same dir → replace.
    func write(_ index: ScreenshotIndex, to url: URL) {
        do {
            let data = try encoder.encode(index)
            let fm = FileManager.default
            let tmp = url.deletingLastPathComponent()
                .appendingPathComponent(".index.\(UUID().uuidString).tmp")
            try data.write(to: tmp, options: .atomic)
            // replaceItemAt requires the original to exist; on first write it
            // doesn't, so move the temp into place instead.
            if fm.fileExists(atPath: url.path) {
                _ = try fm.replaceItemAt(url, withItemAt: tmp)
            } else {
                try fm.moveItem(at: tmp, to: url)
            }
        } catch {
            Log.store.error("index.json write failed: \(error.localizedDescription)")
        }
    }
}

extension ScreenshotStore {
    /// Loads index.json, reconciles against PNGs on disk, and publishes the list.
    func reload() async {
        let folder = folderURL
        let index = await indexIO.read(at: indexURL)
        let reconciled = Self.reconcile(index: index, folder: folder)

        // Persist if reconciliation changed anything (e.g. dropped missing rows
        // or adopted orphan PNGs) so disk and memory stay in agreement.
        if reconciled.entries != index.entries {
            await indexIO.write(reconciled, to: indexURL)
        }
        setPublishedEntries(reconciled.entries)
    }

    /// Appends an entry, persists, and refreshes the published list.
    func append(_ entry: ScreenshotEntry) async {
        var index = await indexIO.read(at: indexURL)
        index.entries.removeAll { $0.file == entry.file } // de-dupe by name
        index.entries.append(entry)
        await indexIO.write(index, to: indexURL)
        setPublishedEntries(index.entries)
    }

    /// Persists an explicit entry set (used by the retention sweep).
    func persist(entries newEntries: [ScreenshotEntry]) async {
        let index = ScreenshotIndex(entries: newEntries)
        await indexIO.write(index, to: indexURL)
        setPublishedEntries(newEntries)
    }

    /// Drops index rows whose PNG is gone and adopts orphan PNGs found on disk.
    nonisolated static func reconcile(index: ScreenshotIndex, folder: URL) -> ScreenshotIndex {
        let fm = FileManager.default
        var entries = index.entries.filter {
            fm.fileExists(atPath: folder.appendingPathComponent($0.file).path)
        }

        let known = Set(entries.map(\.file))
        if let names = try? fm.contentsOfDirectory(atPath: folder.path) {
            for name in names where name.lowercased().hasSuffix(".png") && !known.contains(name) {
                let url = folder.appendingPathComponent(name)
                let ts = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? Date()
                entries.append(ScreenshotEntry(file: name, ts: ts, source: nil))
            }
        }
        return ScreenshotIndex(version: index.version, entries: entries)
    }
}
