import XCTest
import Combine
@testable import boringNotch

private actor PearHTTPProbe {
    var requests: [URLRequest] = []
    var songRejection: Int?
    var authenticationFailures = 0
    var liked = true
    var heldPath: String?
    var pending: CheckedContinuation<(Int, Data), Never>?
    var hasPendingRequest: Bool { pending != nil }
    func holdNext(_ path: String) { heldPath = path }
    func releaseHeld(_ json: String, status: Int = 200) {
        pending?.resume(returning: (status, Data(json.utf8)))
        pending = nil
    }

    func rejectSongOnce(_ status: Int) { songRejection = status }
    func failAuthentication(_ count: Int) { authenticationFailures = count }

    func respond(_ request: URLRequest) async -> (Int, Data) {
        requests.append(request)
        let path = request.url?.path ?? ""
        if heldPath == path {
            heldPath = nil
            return await withCheckedContinuation { pending = $0 }
        }
        if path.hasPrefix("/auth/") {
            if authenticationFailures > 0 {
                authenticationFailures -= 1
                return (503, Data())
            }
            let count = requests.filter { $0.url?.path.hasPrefix("/auth/") == true }.count
            return (200, Data("{\"accessToken\":\"token-\(count)\"}".utf8))
        }
        if path == "/api/v1/like" { liked.toggle() }
        if path == "/api/v1/like-state" {
            return (200, Data("{\"state\":\"\(liked ? "LIKE" : "DISLIKE")\"}".utf8))
        }
        if path == "/api/v1/song" {
            if let status = songRejection { songRejection = nil; return (status, Data()) }
            return (200, Data("{\"isPaused\":false,\"title\":\"Fixture\",\"artist\":\"Pear\"}".utf8))
        }
        return (200, Data("{\"state\":\"LIKE\"}".utf8))
    }

    var authenticationCount: Int { requests.filter { $0.url?.path.hasPrefix("/auth/") == true }.count }
}

private final class PearURLProtocol: URLProtocol, @unchecked Sendable {
    // Tests run serially; the closure is installed before creating each session.
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) async -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let request = request
        let handler = Self.handler
        Task {
            guard let handler, let url = request.url else { return }
            let (status, data) = await handler(request)
            guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { }
}

private actor PearSocketProbe: YouTubeMusicWebSocketConnecting {
    let onMessage: @Sendable (Data) async -> Void
    let onDisconnect: @Sendable (PearDisconnectReason) async -> Void
    var url: URL?
    var token: String?
    var disconnectCount = 0

    init(onMessage: @escaping @Sendable (Data) async -> Void, onDisconnect: @escaping @Sendable (PearDisconnectReason) async -> Void) {
        self.onMessage = onMessage
        self.onDisconnect = onDisconnect
    }
    func connect(to url: URL, with token: String) { self.url = url; self.token = token }
    func disconnect() { disconnectCount += 1 }
    func emit(_ json: String) async { await onMessage(Data(json.utf8)) }
    // Deliberately delivers obsolete callbacks even after disconnect.
    func close(_ reason: PearDisconnectReason) async { await onDisconnect(reason) }
}

private actor PearArtworkProbe {
    var pending: [CheckedContinuation<Data, Error>] = []
    func fetch() async throws -> Data { try await withCheckedThrowingContinuation { pending.append($0) } }
    var count: Int { pending.count }
    func finish(_ index: Int, data: Data) { pending[index].resume(returning: data) }
    func fail(_ index: Int) { pending[index].resume(throwing: URLError(.timedOut)) }
}

@MainActor
final class PearConnectionTests: XCTestCase {
    private var sockets: [PearSocketProbe] = []

    private func makeController(_ http: PearHTTPProbe, baseURL: String = "http://localhost:26538", reconnectDelay: ClosedRange<TimeInterval> = 0.02...0.08, fetchArtwork: @escaping (URL) async throws -> Data = { _ in Data() }) -> YouTubeMusicController {
        PearURLProtocol.handler = { await http.respond($0) }
        let configuration = YouTubeMusicConfiguration(baseURL: baseURL, bundleIdentifier: "fixture.pear", reconnectDelay: reconnectDelay, updateInterval: 0.01)
        return YouTubeMusicController(
            configuration: configuration, observeEnvironment: false, startAutomatically: false,
            makeHTTPClient: { baseURL in
                let session = URLSessionConfiguration.ephemeral
                session.protocolClasses = [PearURLProtocol.self]
                return YouTubeMusicHTTPClient(baseURL: baseURL, session: URLSession(configuration: session))
            },
            makeWebSocket: { [weak self] message, disconnect in
                let socket = PearSocketProbe(onMessage: message, onDisconnect: disconnect)
                self?.sockets.append(socket)
                return socket
            },
            appIsRunning: { true }, fetchArtwork: fetchArtwork
        )
    }

    private func eventually(_ predicate: () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<1000 {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Timed out waiting for Pear fixture", file: file, line: line)
        throw CancellationError()
    }

    func testPortConfigurationUsesLoopbackAndRejectsOutOfRangeValues() throws {
        XCTAssertNil(YouTubeMusicConfiguration.default.withLoopbackPort(0))
        XCTAssertNil(YouTubeMusicConfiguration.default.withLoopbackPort(65536))
        for port in [1, 26538, 26539, 65535] {
            let configuration = try XCTUnwrap(YouTubeMusicConfiguration.default.withLoopbackPort(port))
            let url = try XCTUnwrap(URL(string: configuration.baseURL))
            XCTAssertEqual(url.host, "localhost")
            XCTAssertEqual(url.scheme, "http")
            XCTAssertEqual(url.port, port)
            XCTAssertEqual(WebSocketURLBuilder.buildURL(from: configuration.baseURL)?.port, port)
        }
    }

    func testControllerReplacementUsesFreshPortCredentialAndRetiresOldWork() async throws {
        let http = PearHTTPProbe()
        let artwork = PearArtworkProbe()
        let old = makeController(http, fetchArtwork: { _ in try await artwork.fetch() })
        old.startConnection()
        try await eventually { old.playbackState.isFavorite }
        let oldSocket = try XCTUnwrap(sockets.first)
        await oldSocket.emit("{\"isPaused\":false,\"title\":\"Old track\",\"imageSrc\":\"https://fixture.invalid/old.png\"}")
        try await eventually { await artwork.count == 1 }
        await http.holdNext("/api/v1/song")
        let oldPoll = Task { await old.updatePlaybackInfo() }
        try await eventually { await http.hasPendingRequest }

        old.stopConnection()
        let configuration = try XCTUnwrap(YouTubeMusicConfiguration.default.withLoopbackPort(26539))
        let replacement = makeController(http, baseURL: configuration.baseURL)
        defer { replacement.stopConnection() }
        replacement.startConnection()
        try await eventually { replacement.playbackState.isFavorite }
        let socketURL = await sockets.last?.url
        let token = await sockets.last?.token
        XCTAssertEqual(socketURL?.port, 26539)
        XCTAssertEqual(token, "token-2")
        await replacement.play()
        await old.play()
        let requests = await http.requests
        let command = try XCTUnwrap(requests.last { $0.url?.path == "/api/v1/play" })
        XCTAssertEqual(requests.filter { $0.url?.path == "/api/v1/play" }.count, 1)
        XCTAssertEqual(command.url?.port, 26539)
        XCTAssertEqual(command.value(forHTTPHeaderField: "Authorization"), "Bearer token-2")
        let authentication = requests.filter { $0.url?.path.hasPrefix("/auth/") == true }
        XCTAssertEqual(authentication.compactMap { $0.url?.port }, [26538, 26539])

        await http.releaseHeld("{\"isPaused\":false,\"title\":\"Obsolete HTTP\"}")
        await oldPoll.value
        await artwork.finish(0, data: Data([1]))
        await oldSocket.emit("{\"isPaused\":false,\"title\":\"Obsolete socket\"}")
        await oldSocket.close(.unauthorized)
        XCTAssertEqual(old.playbackState.title, "")
        XCTAssertNil(old.playbackState.artwork)
        XCTAssertEqual(replacement.playbackState.title, "Fixture")
        XCTAssertNil(replacement.playbackState.artwork)
        XCTAssertEqual(sockets.count, 2)
        let count = await http.authenticationCount
        XCTAssertEqual(count, 2)
    }

    private func flushSubscriberQueue() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    func testStopReachesSubscriberAndRejectsRetiredSocket() async throws {
        let http = PearHTTPProbe()
        let controller = makeController(http)
        defer { controller.stopConnection() }
        var accepted: [PlaybackState] = []
        // Match MusicManager's main-queue subscription and initialized-state
        // boundary: initial sentinel snapshots must still be ignored.
        let subscription = controller.playbackStatePublisher
            .receive(on: DispatchQueue.main)
            .filter { $0.lastUpdated != .distantPast }
            .sink { accepted.append($0) }
        defer { subscription.cancel() }
        await flushSubscriberQueue()
        XCTAssertTrue(accepted.isEmpty)
        controller.startConnection()
        try await eventually { accepted.last?.title == "Fixture" && accepted.last?.isPlaying == true }
        let old = try XCTUnwrap(sockets.first)
        await old.emit("{\"isPaused\":false,\"title\":\"Fixture\",\"elapsedSeconds\":42,\"imageSrc\":\"https://fixture.invalid/art.png\"}")
        try await eventually { accepted.last?.artwork != nil && accepted.last?.currentTime == 42 }
        controller.stopConnection()
        await flushSubscriberQueue()
        let cleared = try XCTUnwrap(accepted.last)
        XCTAssertEqual(cleared.title, "")
        XCTAssertFalse(cleared.isPlaying)
        XCTAssertNil(cleared.artwork)
        XCTAssertEqual(cleared.currentTime, 0)
        XCTAssertNotEqual(cleared.lastUpdated, .distantPast)
        await old.emit("{\"isPaused\":false,\"title\":\"Obsolete\"}")
        await flushSubscriberQueue()
        XCTAssertEqual(accepted.last?.title, "")
    }

    func testFavoriteReconcilesWhileSocketPositionSupersedesSlowSongResponse() async throws {
        let http = PearHTTPProbe()
        let controller = makeController(http)
        defer { controller.stopConnection() }
        controller.startConnection()
        try await eventually { controller.playbackState.isFavorite }
        let socket = try XCTUnwrap(sockets.first)
        await socket.emit("{\"type\":\"POSITION_CHANGED\",\"position\":40}")
        let previousLikeRequests = await http.requests.filter { $0.url?.path == "/api/v1/like-state" }.count
        await http.holdNext("/api/v1/song")
        let favorite = Task { await controller.setFavorite(false) }
        try await eventually { await http.hasPendingRequest }
        await socket.emit("{\"type\":\"POSITION_CHANGED\",\"position\":42}")
        await http.releaseHeld("{\"isPaused\":false,\"title\":\"Fixture\",\"artist\":\"Pear\",\"elapsedSeconds\":3}")
        await favorite.value
        XCTAssertEqual(controller.playbackState.currentTime, 42)
        XCTAssertFalse(controller.playbackState.isFavorite)
        let likeRequests = await http.requests.filter { $0.url?.path == "/api/v1/like-state" }.count
        XCTAssertGreaterThan(likeRequests, previousLikeRequests)
    }

    func testLikeResponseCannotAttachToAnotherTrack() async throws {
        let http = PearHTTPProbe()
        let controller = makeController(http)
        defer { controller.stopConnection() }
        controller.startConnection()
        try await eventually { controller.playbackState.isFavorite }
        let socket = try XCTUnwrap(sockets.first)
        await http.holdNext("/api/v1/like-state")
        let refresh = Task { await controller.updatePlaybackInfo() }
        try await eventually { await http.hasPendingRequest }
        await socket.emit("{\"isPaused\":false,\"title\":\"Another track\",\"artist\":\"Pear\"}")
        await http.releaseHeld("{\"state\":\"LIKE\"}")
        await refresh.value
        XCTAssertEqual(controller.playbackState.title, "Another track")
        XCTAssertFalse(controller.playbackState.isFavorite)
    }

    func testRepeatedStartCoalescesInitialization() async throws {
        let http = PearHTTPProbe()
        let controller = makeController(http)
        defer { controller.stopConnection() }
        for _ in 0..<20 { controller.startConnection() }
        try await eventually { controller.playbackState.title == "Fixture" }
        XCTAssertEqual(sockets.count, 1)
        let count = await http.authenticationCount
        XCTAssertEqual(count, 1)
    }

    func testHTTPUnauthorizedReauthorizesWithNewCredential() async throws {
        for status in [401, 403] {
            sockets = []
            let http = PearHTTPProbe()
            await http.rejectSongOnce(status)
            let controller = makeController(http)
            controller.startConnection()
            try await eventually { await http.authenticationCount == 2 && controller.playbackState.title == "Fixture" }
            let token = await sockets.last?.token
            XCTAssertEqual(token, "token-2")
            controller.stopConnection()
        }
    }

    func testRejectedMutationIsNotReplayedAndBackoffDoesNotUseRetiredToken() async throws {
        let http = PearHTTPProbe()
        let controller = makeController(http, reconnectDelay: 0.15...0.15)
        defer { controller.stopConnection() }
        controller.startConnection()
        try await eventually { controller.playbackState.isFavorite }
        await http.holdNext("/api/v1/pause")
        let command = Task { await controller.pause() }
        try await eventually { await http.hasPendingRequest }
        await http.releaseHeld("", status: 401)
        await command.value
        await controller.pause()
        await controller.updatePlaybackInfo()
        let duringBackoff = await http.requests
        XCTAssertEqual(duringBackoff.filter { $0.url?.path == "/api/v1/pause" }.count, 1)
        XCTAssertEqual(duringBackoff.filter { $0.url?.path.hasPrefix("/auth/") == true }.count, 1)
        try await eventually { await http.authenticationCount == 2 && self.sockets.count == 2 }
        let afterReconnect = await http.requests.filter { $0.url?.path == "/api/v1/pause" }.count
        XCTAssertEqual(afterReconnect, 1)
        await controller.pause()
        let commands = await http.requests.filter { $0.url?.path == "/api/v1/pause" }
        XCTAssertEqual(commands.count, 2)
        XCTAssertEqual(commands.last?.value(forHTTPHeaderField: "Authorization"), "Bearer token-2")
    }

    func testPolicyViolationReauthorizesAndStaleSocketCannotReconnect() async throws {
        let http = PearHTTPProbe()
        let controller = makeController(http)
        defer { controller.stopConnection() }
        controller.startConnection()
        try await eventually { controller.playbackState.title == "Fixture" }
        let old = sockets[0]
        await old.close(.unauthorized)
        try await eventually { self.sockets.count == 2 }
        await old.close(.transient)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(sockets.count, 2)
        let count = await http.authenticationCount
        XCTAssertEqual(count, 2)
    }

    func testTransientBackoffPreservesHTTPCommandsManualRefreshAndSingleFlightPolling() async throws {
        let http = PearHTTPProbe()
        let controller = makeController(http, reconnectDelay: 30...30)
        defer { controller.stopConnection() }
        controller.startConnection()
        try await eventually { controller.playbackState.isFavorite }
        await sockets[0].close(.transient)
        await controller.pause()
        let commands = await http.requests.filter { $0.url?.path == "/api/v1/pause" }
        XCTAssertEqual(commands.count, 1)
        XCTAssertEqual(commands.first?.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
        XCTAssertEqual(commands.first?.url?.port, 26538)

        await http.holdNext("/api/v1/song")
        let manualRefresh = Task { await controller.updatePlaybackInfo() }
        try await eventually { await http.hasPendingRequest }
        let before = await http.requests.filter { $0.url?.path == "/api/v1/song" }.count
        for _ in 0..<10 { await controller.updatePlaybackInfo() }
        try await Task.sleep(for: .milliseconds(40))
        let during = await http.requests.filter { $0.url?.path == "/api/v1/song" }.count
        XCTAssertEqual(during, before)
        await http.releaseHeld("{\"isPaused\":false,\"title\":\"Fixture\",\"artist\":\"Pear\"}")
        await manualRefresh.value
        try await eventually { await http.requests.filter { $0.url?.path == "/api/v1/song" }.count > before }
        XCTAssertEqual(sockets.count, 1, "The 30-second socket retry must still be pending")
        let authCount = await http.authenticationCount
        XCTAssertEqual(authCount, 1)
    }

    func testFailedArtworkRetriesSameURLOnLaterSnapshot() async throws {
        let http = PearHTTPProbe()
        let artwork = PearArtworkProbe()
        let controller = makeController(http, fetchArtwork: { _ in try await artwork.fetch() })
        defer { controller.stopConnection() }
        controller.startConnection()
        try await eventually { controller.playbackState.isFavorite }
        let socket = try XCTUnwrap(sockets.first)
        let snapshot = "{\"isPaused\":false,\"title\":\"Fixture\",\"imageSrc\":\"https://fixture.invalid/art.png\"}"
        await socket.emit(snapshot)
        try await eventually { await artwork.count == 1 }
        await artwork.fail(0)
        try await eventually {
            await socket.emit(snapshot)
            return await artwork.count == 2
        }
        await artwork.finish(1, data: Data([2]))
        try await eventually { controller.playbackState.artwork == Data([2]) }
        await socket.emit(snapshot)
        await socket.emit("{\"type\":\"POSITION_CHANGED\",\"position\":5}")
        let count = await artwork.count
        XCTAssertEqual(count, 2)
    }

    func testStaleArtworkFailureCannotClearNewerRequest() async throws {
        let http = PearHTTPProbe()
        let artwork = PearArtworkProbe()
        let controller = makeController(http, fetchArtwork: { _ in try await artwork.fetch() })
        defer { controller.stopConnection() }
        controller.startConnection()
        try await eventually { controller.playbackState.isFavorite }
        let socket = try XCTUnwrap(sockets.first)
        await socket.emit("{\"isPaused\":false,\"title\":\"First\",\"imageSrc\":\"https://fixture.invalid/first.png\"}")
        try await eventually { await artwork.count == 1 }
        let snapshot = "{\"isPaused\":false,\"title\":\"Second\",\"imageSrc\":\"https://fixture.invalid/second.png\"}"
        await socket.emit(snapshot)
        try await eventually { await artwork.count == 2 }
        await artwork.fail(0)
        try await Task.sleep(for: .milliseconds(20))
        await socket.emit(snapshot)
        let pendingCount = await artwork.count
        XCTAssertEqual(pendingCount, 2)
        await artwork.finish(1, data: Data([2]))
        try await eventually { controller.playbackState.artwork == Data([2]) }
        await socket.emit(snapshot)
        let finalCount = await artwork.count
        XCTAssertEqual(finalCount, 2)
    }

    func testTransientDisconnectRetainsCredentialAndStopCancelsReconnect() async throws {
        let http = PearHTTPProbe()
        let controller = makeController(http)
        controller.startConnection()
        try await eventually { controller.playbackState.title == "Fixture" }
        await sockets[0].close(.transient)
        try await eventually { self.sockets.count == 2 }
        let count = await http.authenticationCount
        XCTAssertEqual(count, 1)
        await sockets[1].close(.transient)
        controller.stopConnection()
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(sockets.count, 2)
        XCTAssertFalse(controller.isActive())
        XCTAssertEqual(controller.playbackState.title, "")
    }

    func testAPIStartingLateRecoversWithoutOverlappingInitialization() async throws {
        let http = PearHTTPProbe()
        await http.failAuthentication(2)
        let controller = makeController(http)
        defer { controller.stopConnection() }
        controller.startConnection()
        try await eventually { controller.playbackState.title == "Fixture" }
        let count = await http.authenticationCount
        XCTAssertEqual(count, 3)
        XCTAssertEqual(sockets.count, 1)
    }

    func testStaleArtworkCannotPublishAndPositionTicksDoNotRefetchArtwork() async throws {
        let http = PearHTTPProbe()
        let artwork = PearArtworkProbe()
        let controller = makeController(http, fetchArtwork: { _ in try await artwork.fetch() })
        defer { controller.stopConnection() }
        controller.startConnection()
        try await eventually { controller.playbackState.title == "Fixture" }
        let socket = sockets[0]
        await socket.emit("{\"isPaused\":false,\"title\":\"First\",\"imageSrc\":\"https://fixture.invalid/first.png\"}")
        try await eventually { await artwork.count == 1 }
        await socket.emit("{\"isPaused\":false,\"title\":\"Second\",\"imageSrc\":\"https://fixture.invalid/second.png\"}")
        try await eventually { await artwork.count == 2 }
        await artwork.finish(1, data: Data([2]))
        try await eventually { controller.playbackState.artwork == Data([2]) }
        await artwork.finish(0, data: Data([1]))
        await socket.emit("{\"type\":\"POSITION_CHANGED\",\"position\":5}")
        await socket.emit("{\"isPaused\":false,\"title\":\"Second\",\"elapsedSeconds\":6,\"imageSrc\":\"https://fixture.invalid/second.png\"}")
        XCTAssertEqual(controller.playbackState.artwork, Data([2]))
        let count = await artwork.count
        XCTAssertEqual(count, 2)
        controller.stopConnection()
        await socket.emit("{\"isPaused\":false,\"title\":\"Obsolete\"}")
        XCTAssertEqual(controller.playbackState.title, "")
    }

    func testSlowPollIsSingleFlightAndCannotPublishAfterStop() async throws {
        let http = PearHTTPProbe()
        await http.holdNext("/api/v1/song")
        let controller = makeController(http)
        defer { controller.stopConnection() }
        controller.startConnection()
        try await eventually { await http.hasPendingRequest }
        for _ in 0..<10 { await controller.updatePlaybackInfo() }
        let before = await http.requests.filter { $0.url?.path == "/api/v1/song" }.count
        XCTAssertEqual(before, 1)
        controller.stopConnection()
        await http.releaseHeld("{\"isPaused\":false,\"title\":\"Obsolete\"}")
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(controller.playbackState.title, "")
    }

    func testCommandCompletionAfterStopCannotChangePlayback() async throws {
        let http = PearHTTPProbe()
        let controller = makeController(http)
        controller.startConnection()
        try await eventually { controller.playbackState.title == "Fixture" }
        await http.holdNext("/api/v1/shuffle")
        let command = Task { await controller.toggleShuffle() }
        try await eventually { await http.hasPendingRequest }
        controller.stopConnection()
        await http.releaseHeld("{\"state\":true}")
        await command.value
        XCTAssertFalse(controller.playbackState.isShuffled)
        XCTAssertEqual(controller.playbackState.title, "")
    }

    func testRetiredHTTPClientRejectsNewRequests() async throws {
        let client = YouTubeMusicHTTPClient(baseURL: "http://localhost:26538")
        client.cancelAllRequests()
        do {
            _ = try await client.authenticate()
            XCTFail("A retired client must reject new work before starting HTTP")
        } catch is CancellationError { }
    }

    func testDisconnectClassification() throws {
        XCTAssertEqual(PearDisconnectReason.classify(closeCode: .policyViolation, response: nil), .unauthorized)
        let url = try XCTUnwrap(URL(string: "http://localhost:26538"))
        for status in [401, 403] {
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
            XCTAssertEqual(PearDisconnectReason.classify(closeCode: .invalid, response: response), .unauthorized)
        }
        XCTAssertEqual(PearDisconnectReason.classify(closeCode: .abnormalClosure, response: nil), .transient)
    }
}
