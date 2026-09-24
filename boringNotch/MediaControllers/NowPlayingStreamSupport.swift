import Foundation

enum TimedProcessRunner {
    static func exitsSuccessfully(
        _ process: Process,
        timeout: Duration
    ) async throws -> Bool {
        try Task.checkCancellation()

        let terminations = AsyncStream<Bool> { continuation in
            process.terminationHandler = { process in
                continuation.yield(
                    process.terminationReason == .exit && process.terminationStatus == 0
                )
                continuation.finish()
            }
        }

        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            throw error
        }

        defer { process.terminationHandler = nil }

        return try await withTaskCancellationHandler {
            let succeeded = await withTaskGroup(of: Bool.self) { group in
                group.addTask {
                    for await succeeded in terminations {
                        return succeeded
                    }
                    return false
                }
                group.addTask {
                    try? await Task.sleep(for: timeout)
                    return false
                }

                let result = await group.next() ?? false
                group.cancelAll()
                return result
            }

            try Task.checkCancellation()
            stop(process)
            return succeeded
        } onCancel: {
            stop(process)
        }
    }

    static func stop(_ process: Process) {
        guard process.isRunning else { return }
        _ = kill(process.processIdentifier, SIGKILL)
    }
}

enum NowPlayingError: Error, Sendable { case unavailable }

struct NowPlayingResources: Sendable {
    let adapterScriptURL: URL
    let adapterFrameworkPath: String
    let testClientURL: URL

    static func load(from bundle: Bundle = .main) throws -> Self {
        let fileManager = FileManager.default

        guard let scriptURL = bundle.url(
            forResource: "mediaremote-adapter",
            withExtension: "pl"
        ), fileManager.isReadableFile(atPath: scriptURL.path) else {
            throw NowPlayingError.unavailable
        }

        guard let privateFrameworksPath = bundle.privateFrameworksPath else {
            throw NowPlayingError.unavailable
        }
        let frameworkPath = privateFrameworksPath.appending("/MediaRemoteAdapter.framework")
        let frameworkExecutable = frameworkPath.appending("/MediaRemoteAdapter")
        guard fileManager.isExecutableFile(atPath: frameworkExecutable) else {
            throw NowPlayingError.unavailable
        }

        guard let testClientURL = bundle.url(
            forResource: "MediaRemoteAdapterTestClient",
            withExtension: nil
        ), fileManager.isExecutableFile(atPath: testClientURL.path) else {
            throw NowPlayingError.unavailable
        }

        return Self(
            adapterScriptURL: scriptURL,
            adapterFrameworkPath: frameworkPath,
            testClientURL: testClientURL
        )
    }
}

enum NowPlayingFailure: Equatable, Sendable {
    case setup
    case probe
    case runtime
}

enum NowPlayingAvailability: Equatable, Sendable {
    case unchecked
    case checking
    case available
    case unavailable(NowPlayingFailure)

    var isSelectable: Bool { self == .available }

    var failure: NowPlayingFailure? {
        guard case let .unavailable(failure) = self else { return nil }
        return failure
    }

    var offersManualRetry: Bool { failure == .probe }

    var usesTemporaryFallback: Bool {
        guard let failure else { return false }
        return failure != .setup
    }

    var settingsMessage: LocalizedStringResource? {
        switch self {
        case .unchecked, .checking, .available:
            nil
        case .unavailable(.setup):
            LocalizedStringResource(
                "Boring Notch's Now Playing components are unavailable. Reopen or reinstall the app.",
                comment: "Now Playing setup failure message shown when required bundled components cannot be used."
            )
        case .unavailable(.probe):
            LocalizedStringResource(
                "Boring Notch could not verify Now Playing. Try again, or reopen the app if it keeps happening.",
                comment: "Recoverable Now Playing probe failure message."
            )
        case .unavailable(.runtime):
            LocalizedStringResource(
                "Boring Notch lost its Now Playing connection. Reconnecting automatically...",
                comment: "Now Playing runtime failure message shown before an automatic recovery attempt."
            )
        }
    }
}

@MainActor
final class NowPlayingStreamSession {
    private let process: Process
    private let reader: JSONLinesPipeHandler
    private let onUpdate: @MainActor (NowPlayingUpdate) async -> Void
    private let onFailure: @MainActor () -> Void

    private var readTask: Task<Void, Never>?
    private var isStopped = false

    init(
        process: Process,
        reader: JSONLinesPipeHandler = JSONLinesPipeHandler(),
        onUpdate: @escaping @MainActor (NowPlayingUpdate) async -> Void,
        onFailure: @escaping @MainActor () -> Void
    ) {
        self.process = process
        self.reader = reader
        self.onUpdate = onUpdate
        self.onFailure = onFailure
    }

    func start() {
        guard readTask == nil, !isStopped else { return }

        process.standardOutput = reader.outputPipe
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.finish()
            }
        }

        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            finish()
            return
        }

        let session = self
        readTask = Task { @MainActor [reader, session] in
            await reader.readJSONLines(as: NowPlayingUpdate.self) { update in
                await session.receive(update)
            }
            session.finish()
        }
    }

    func stop() {
        guard !isStopped else { return }
        cleanup()
    }

    private func receive(_ update: NowPlayingUpdate) async {
        guard !isStopped else { return }
        await onUpdate(update)
    }

    private func finish() {
        guard !isStopped else { return }
        cleanup()
        onFailure()
    }

    private func cleanup() {
        isStopped = true
        process.terminationHandler = nil
        readTask?.cancel()
        readTask = nil
        reader.close()
        TimedProcessRunner.stop(process)
    }

    deinit {
        process.terminationHandler = nil
        reader.close()
        TimedProcessRunner.stop(process)
    }
}

struct NowPlayingUpdate: Codable, Sendable {
    let payload: NowPlayingPayload
    let diff: Bool?
}

struct NowPlayingPayload: Codable, Sendable {
    let title: String?
    let artist: String?
    let album: String?
    let duration: Double?
    let elapsedTime: Double?
    let shuffleMode: Int?
    let repeatMode: Int?
    let artworkData: String?
    let timestamp: String?
    let playbackRate: Double?
    let playing: Bool?
    let parentApplicationBundleIdentifier: String?
    let bundleIdentifier: String?
    let volume: Double?
}
