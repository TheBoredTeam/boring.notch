import Foundation

enum ChildProcessTermination: Equatable, Sendable {
    case exited(Int32)
    case signaled(Int32)
    case unknown(status: Int32)

    init(process: Process) {
        switch process.terminationReason {
        case .exit:
            self = .exited(process.terminationStatus)
        case .uncaughtSignal:
            self = .signaled(process.terminationStatus)
        @unknown default:
            self = .unknown(status: process.terminationStatus)
        }
    }
}

enum TimedProcessResult: Equatable, Sendable {
    case terminated(ChildProcessTermination)
    case timedOut
}

enum TimedProcessRunner {
    static func run(
        _ process: Process,
        timeout: Duration
    ) async throws -> TimedProcessResult {
        try Task.checkCancellation()

        let terminations = AsyncStream<ChildProcessTermination> { continuation in
            process.terminationHandler = { terminatedProcess in
                continuation.yield(ChildProcessTermination(process: terminatedProcess))
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
            let result = try await withThrowingTaskGroup(of: TimedProcessResult.self) { group in
                group.addTask {
                    for await termination in terminations {
                        try Task.checkCancellation()
                        return .terminated(termination)
                    }
                    throw CancellationError()
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    return .timedOut
                }

                guard let firstResult = try await group.next() else {
                    throw CancellationError()
                }
                group.cancelAll()
                return firstResult
            }

            if result == .timedOut {
                forceStop(process)
            }
            return result
        } onCancel: {
            forceStop(process)
        }
    }

    static func forceStop(_ process: Process) {
        guard process.isRunning else { return }
        _ = kill(process.processIdentifier, SIGKILL)
    }
}

enum NowPlayingSetupFailure: Error, Equatable, Sendable {
    case missingAdapterScript
    case missingAdapterFramework
    case missingTestClient
    case mediaRemoteUnavailable
}

struct NowPlayingResources: Sendable {
    let adapterScriptURL: URL
    let adapterFrameworkPath: String
    let testClientURL: URL?

    static func load(
        from bundle: Bundle = .main,
        requiresTestClient: Bool
    ) throws -> Self {
        let fileManager = FileManager.default

        guard let scriptURL = bundle.url(
            forResource: "mediaremote-adapter",
            withExtension: "pl"
        ), fileManager.isReadableFile(atPath: scriptURL.path) else {
            throw NowPlayingSetupFailure.missingAdapterScript
        }

        guard let privateFrameworksPath = bundle.privateFrameworksPath else {
            throw NowPlayingSetupFailure.missingAdapterFramework
        }
        let frameworkPath = privateFrameworksPath.appending("/MediaRemoteAdapter.framework")
        let frameworkExecutable = frameworkPath.appending("/MediaRemoteAdapter")
        guard fileManager.isExecutableFile(atPath: frameworkExecutable) else {
            throw NowPlayingSetupFailure.missingAdapterFramework
        }

        let testClientURL: URL?
        if requiresTestClient {
            guard let url = bundle.url(
                forResource: "MediaRemoteAdapterTestClient",
                withExtension: nil
            ), fileManager.isExecutableFile(atPath: url.path) else {
                throw NowPlayingSetupFailure.missingTestClient
            }
            testClientURL = url
        } else {
            testClientURL = nil
        }

        return Self(
            adapterScriptURL: scriptURL,
            adapterFrameworkPath: frameworkPath,
            testClientURL: testClientURL
        )
    }
}

enum NowPlayingProbeFailure: Equatable, Sendable {
    case launchFailed
    case timedOut
    case helperPathMissing
    case helperLaunchFailed
    case helperSetupTimedOut
    case noData
    case wrapperFailed
    case signaled(Int32)
    case unexpectedExit(Int32)
}

enum NowPlayingAvailability: Equatable, Sendable {
    case unchecked
    case available
    case setupFailure(NowPlayingSetupFailure)
    case temporaryFailure(NowPlayingProbeFailure)
    case runtimeStreamFailed

    var requiresFallback: Bool {
        switch self {
        case .unchecked, .available:
            false
        case .setupFailure, .temporaryFailure, .runtimeStreamFailed:
            true
        }
    }

    var isRecoverableFailure: Bool {
        switch self {
        case .temporaryFailure, .runtimeStreamFailed:
            true
        case .unchecked, .available, .setupFailure:
            false
        }
    }

    var isSelectable: Bool { self == .available }

    var showsCheckAgainButton: Bool { isRecoverableFailure }

    var settingsMessage: LocalizedStringResource? {
        switch self {
        case .unchecked, .available:
            nil
        case .setupFailure(.mediaRemoteUnavailable):
            LocalizedStringResource(
                "Now Playing is not supported by this version of macOS. Choose another music source.",
                comment: "Now Playing availability message when required private macOS APIs are unavailable."
            )
        case .setupFailure:
            LocalizedStringResource(
                "Boring Notch is missing a required Now Playing component. Reinstalling the app should fix this.",
                comment: "Now Playing availability message when a bundled component is missing."
            )
        case .temporaryFailure(.timedOut):
            LocalizedStringResource(
                "The Now Playing check took too long. Try again in a moment.",
                comment: "Now Playing availability message when the self-check times out."
            )
        case .temporaryFailure(.noData):
            LocalizedStringResource(
                "macOS did not return data to the Now Playing self-check. Try again, or reopen Boring Notch if it keeps happening.",
                comment: "Now Playing availability message when the self-check receives no test data."
            )
        case .temporaryFailure:
            LocalizedStringResource(
                "Boring Notch could not check Now Playing. Try again, or reopen the app if it keeps happening.",
                comment: "Generic recoverable Now Playing availability message."
            )
        case .runtimeStreamFailed:
            LocalizedStringResource(
                "Now Playing stopped responding. Boring Notch switched music sources temporarily. Check again to restore Now Playing.",
                comment: "Media settings message after the Now Playing runtime stream repeatedly stops."
            )
        }
    }

    var shouldRetry: Bool {
        if case .temporaryFailure = self { return true }
        return false
    }
}

protocol NowPlayingAvailabilityChecking: Sendable {
    func checkAvailability(maxAttempts: Int) async throws -> NowPlayingAvailability
}

enum NowPlayingRuntimeFailure: Equatable, Sendable {
    case helperLaunchFailed
    case helperExited(ChildProcessTermination)
    case streamEnded
    case streamReadFailed
    case malformedOutput
}

enum NowPlayingRuntimeRecoveryAction: Equatable, Sendable {
    case restart(after: Duration)
    case fallback
}

struct NowPlayingRuntimeRecoveryPolicy: Sendable {
    static let retryDelay: Duration = .milliseconds(500)
    static let rapidFailureWindow: Duration = .seconds(60)

    private(set) var previousFailure: ContinuousClock.Instant?

    mutating func action(at instant: ContinuousClock.Instant) -> NowPlayingRuntimeRecoveryAction {
        defer { previousFailure = instant }

        guard let previousFailure else {
            return .restart(after: Self.retryDelay)
        }

        return previousFailure.duration(to: instant) < Self.rapidFailureWindow
            ? .fallback
            : .restart(after: Self.retryDelay)
    }

    mutating func reset() {
        previousFailure = nil
    }
}

actor JSONLinesPipeHandler {
    nonisolated let outputPipe: Pipe
    nonisolated let fileHandle: FileHandle
    private var byteIterator: FileHandle.AsyncBytes.Iterator
    private var consecutiveMalformedLines = 0

    init(pipe: Pipe = Pipe()) {
        outputPipe = pipe
        fileHandle = pipe.fileHandleForReading
        byteIterator = fileHandle.bytes.makeAsyncIterator()
    }

    func readJSONLines<Value: Decodable & Sendable>(
        as type: Value.Type,
        onValue: @escaping @Sendable (Value) async -> Void
    ) async -> NowPlayingRuntimeFailure {
        var line = Data()
        var iterator = byteIterator

        do {
            while let byte = try await iterator.next() {
                guard !Task.isCancelled else { return .streamEnded }

                guard byte == UInt8(ascii: "\n") else {
                    line.append(byte)
                    continue
                }

                if line.last == UInt8(ascii: "\r") {
                    line.removeLast()
                }

                guard !line.isEmpty,
                      let decoded = try? JSONDecoder().decode(Value.self, from: line)
                else {
                    consecutiveMalformedLines += 1
                    line.removeAll(keepingCapacity: true)
                    if consecutiveMalformedLines >= 3 {
                        return .malformedOutput
                    }
                    continue
                }

                consecutiveMalformedLines = 0
                line.removeAll(keepingCapacity: true)
                await onValue(decoded)
            }

            return .streamEnded
        } catch {
            return Task.isCancelled ? .streamEnded : .streamReadFailed
        }
    }

    nonisolated func close() {
        try? fileHandle.close()
        try? outputPipe.fileHandleForWriting.close()
    }
}

@MainActor
final class NowPlayingStreamSession {
    private let process: Process
    private let reader: JSONLinesPipeHandler
    private let onUpdate: @MainActor (NowPlayingUpdate) async -> Void
    private let onFailure: @MainActor (NowPlayingRuntimeFailure) -> Void

    private var readTask: Task<Void, Never>?
    private var isStopped = false
    private var didReportFailure = false

    init(
        process: Process,
        reader: JSONLinesPipeHandler = JSONLinesPipeHandler(),
        onUpdate: @escaping @MainActor (NowPlayingUpdate) async -> Void,
        onFailure: @escaping @MainActor (NowPlayingRuntimeFailure) -> Void
    ) {
        self.process = process
        self.reader = reader
        self.onUpdate = onUpdate
        self.onFailure = onFailure
    }

    func start() {
        guard readTask == nil, !isStopped else { return }

        process.standardOutput = reader.outputPipe
        process.terminationHandler = { [weak self] terminatedProcess in
            let termination = ChildProcessTermination(process: terminatedProcess)
            Task { @MainActor [weak self] in
                self?.finish(with: .helperExited(termination))
            }
        }

        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            finish(with: .helperLaunchFailed)
            return
        }

        let session = self
        readTask = Task { @MainActor [reader, session] in
            let failure = await reader.readJSONLines(as: NowPlayingUpdate.self) { update in
                await session.receive(update)
            }
            session.finish(with: failure)
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

    private func finish(with failure: NowPlayingRuntimeFailure) {
        guard !isStopped, !didReportFailure else { return }
        didReportFailure = true
        cleanup()
        onFailure(failure)
    }

    private func cleanup() {
        isStopped = true
        process.terminationHandler = nil
        readTask?.cancel()
        readTask = nil
        reader.close()
        TimedProcessRunner.forceStop(process)
    }

    deinit {
        process.terminationHandler = nil
        reader.close()
        TimedProcessRunner.forceStop(process)
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
