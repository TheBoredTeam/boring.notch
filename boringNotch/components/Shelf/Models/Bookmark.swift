import AppKit
import Foundation

struct ResolvedShelfFile: Equatable, Sendable {
    let url: URL
    let refreshedBookmarkData: Data?
    let displayName: String
    let isDirectory: Bool
    let contentTypeIdentifier: String?
}

enum ShelfFileResolutionPhase: Equatable, Sendable {
    case loading
    case available(ResolvedShelfFile)
    case unavailable
}

struct ShelfFileResolutionState: Sendable {
    private(set) var phase: ShelfFileResolutionPhase = .loading
    private var generation: UInt = 0

    mutating func begin(preservingAvailableFile: Bool = false) -> UInt {
        generation &+= 1
        if !preservingAvailableFile || phase == .unavailable { phase = .loading }
        return generation
    }

    mutating func timeOut(generation candidate: UInt) -> Bool {
        guard candidate == generation, phase == .loading else { return false }
        phase = .unavailable
        return true
    }

    mutating func finish(_ file: ResolvedShelfFile?, generation candidate: UInt) -> Bool {
        guard candidate == generation else { return false }
        phase = file.map(ShelfFileResolutionPhase.available) ?? .unavailable
        return true
    }
}

enum ShelfBookmarkResolutionIntent: Hashable, Sendable {
    case presentation
    case userInitiated
}

private final class ShelfBookmarkResolutionExecutor: @unchecked Sendable {
    static let shared = ShelfBookmarkResolutionExecutor(maxConcurrentOperationCount: 2)
    private let queue: OperationQueue

    init(maxConcurrentOperationCount: Int) {
        queue = OperationQueue()
        queue.name = "com.boringnotch.shelf-bookmark-resolution"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = maxConcurrentOperationCount
    }

    func execute<Value: Sendable>(_ operation: @escaping @Sendable () -> Value) async -> Value {
        await withCheckedContinuation { continuation in
            queue.addOperation { continuation.resume(returning: operation()) }
        }
    }
}

private actor ShelfBookmarkResolutionRegistry {
    private struct Key: Hashable {
        let data: Data
        let intent: ShelfBookmarkResolutionIntent
    }
    private struct InFlight {
        let token: UUID
        let task: Task<ResolvedShelfFile?, Never>
    }

    private let executor: ShelfBookmarkResolutionExecutor
    private var inFlight: [Key: InFlight] = [:]

    init(executor: ShelfBookmarkResolutionExecutor = .shared) {
        self.executor = executor
    }

    func resolve(
        data: Data,
        intent: ShelfBookmarkResolutionIntent,
        using resolution: @escaping @Sendable (Data, ShelfBookmarkResolutionIntent) -> ResolvedShelfFile?
    ) async -> ResolvedShelfFile? {
        let key = Key(data: data, intent: intent)
        let operation: InFlight
        if let existing = inFlight[key] {
            operation = existing
        } else {
            let token = UUID()
            let executor = executor
            let task = Task { await executor.execute { resolution(data, intent) } }
            operation = InFlight(token: token, task: task)
            inFlight[key] = operation
        }

        let result = await operation.task.value
        if inFlight[key]?.token == operation.token { inFlight[key] = nil }
        return result
    }
}

struct ShelfBookmarkResolver: Sendable {
    private let resolution: @Sendable (Data, ShelfBookmarkResolutionIntent) -> ResolvedShelfFile?
    private let registry: ShelfBookmarkResolutionRegistry

    init(resolution: @escaping @Sendable (Data, ShelfBookmarkResolutionIntent) -> ResolvedShelfFile?) {
        self.resolution = resolution
        registry = ShelfBookmarkResolutionRegistry()
    }

    func resolve(
        _ data: Data,
        intent: ShelfBookmarkResolutionIntent = .presentation
    ) async -> ResolvedShelfFile? {
        await registry.resolve(data: data, intent: intent, using: resolution)
    }
}

struct Bookmark: Sendable, Equatable, Codable {
    let data: Data

    init(data: Data) { self.data = data }

    init(url: URL) throws {
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else {
            throw NSError(
                domain: "Bookmark",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Not a valid file URL or file does not exist at \(url.path)"]
            )
        }
        data = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    fileprivate func resolve(intent: ShelfBookmarkResolutionIntent) -> (url: URL?, refreshedData: Data?) {
        guard !data.isEmpty else { return (nil, nil) }
        var isStale = false
        var options: URL.BookmarkResolutionOptions = [.withSecurityScope]
        if intent == .presentation { options.formUnion([.withoutUI, .withoutMounting]) }

        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: options,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            let refreshed = isStale ? try? url.bookmarkData(options: [.withSecurityScope]) : nil
            return (url, refreshed)
        } catch {
            return (nil, nil)
        }
    }

    /// Compatibility for item-provider import. Shelf display and user actions resolve
    /// through `ShelfBookmarkResolver` so OS bookmark work stays off the main actor.
    var importedItemURL: URL? {
        resolve(intent: .userInitiated).url
    }
}

extension ShelfBookmarkResolver {
    static let live = ShelfBookmarkResolver { bookmarkData, intent in
        let result = Bookmark(data: bookmarkData).resolve(intent: intent)
        guard let url = result.url else { return nil }
        return url.accessSecurityScopedResource { scopedURL in
            let values = try? scopedURL.resourceValues(
                forKeys: [.contentTypeKey, .isDirectoryKey, .localizedNameKey]
            )
            return ResolvedShelfFile(
                url: scopedURL,
                refreshedBookmarkData: result.refreshedData,
                displayName: shelfDisplayName(for: scopedURL, localizedName: values?.localizedName),
                isDirectory: values?.isDirectory ?? false,
                contentTypeIdentifier: values?.contentType?.identifier
            )
        }
    }
}

private func shelfDisplayName(for url: URL, localizedName: String?) -> String {
    if url.pathExtension.lowercased() == "json", url.path.contains("TextBlocks") {
        struct TextBlockData: Codable {
            let content: String
            let title: String?
        }
        if let data = try? Data(contentsOf: url) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let textData = try? decoder.decode(TextBlockData.self, from: data) {
                if let title = textData.title, !title.isEmpty { return title }
                let line = textData.content.components(separatedBy: .newlines).first ?? textData.content
                return line.count > 50 ? String(line.prefix(47)) + "..." : line
            }
        }
    } else if url.pathExtension.lowercased() == "webloc", url.path.contains("WebLocs"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let urlString = plist["URL"] as? String {
        return (plist["Title"] as? String) ?? urlString
    }
    return localizedName ?? url.lastPathComponent
}
