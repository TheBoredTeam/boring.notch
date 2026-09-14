//
//  YouTubeMusicController.swift
//  boringNotch
//
//  Created By Alexander on 2025-03-30.
//  Modified by Pranav on 2025-06-16.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class YouTubeMusicController: MediaControllerProtocol {
    // MARK: - Published Properties
    @Published var playbackState = PlaybackState(
        bundleIdentifier: YouTubeMusicConfiguration.default.bundleIdentifier
    )

    private var artworkFetchTask: Task<Void, Never>?
    
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var supportsVolumeControl: Bool {
        return true
    }

    var supportsFavorite: Bool { true }

    func setFavorite(_ favorite: Bool) async {
        guard favorite != playbackState.isFavorite else { return }
        await sendCommand(endpoint: "/like")
    }

    // The endpoint is immutable for this controller. Resets retire work from its previous connection.
    private let configuration: YouTubeMusicConfiguration
    private var httpClient: YouTubeMusicHTTPClient
    private var authManager: YouTubeMusicAuthManager
    private var webSocketClient: (any YouTubeMusicWebSocketConnecting)?
    private let makeHTTPClient: (String) -> YouTubeMusicHTTPClient
    private let makeWebSocket: (@escaping @Sendable (Data) async -> Void,
                               @escaping @Sendable (PearDisconnectReason) async -> Void) -> any YouTubeMusicWebSocketConnecting
    private let appIsRunning: () -> Bool
    private let fetchArtwork: (URL) async throws -> Data
    private var enabled = true
    private var generation: UInt64 = 0
    private var socketID: UUID?
    private var metadataRevision: UInt64 = 0
    private var initializationTask: Task<Void, Never>?
    private var initializationID: UUID?
    private var pollID: UUID?
    private var pollingTask: Task<Void, Never>?
    private var updateTimer: Timer?
    private var appStateObserver: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectID: UUID?
    private var reconnectDelay: TimeInterval
    private var artworkURL: String?
    private var artworkID: UUID?

    init(
        configuration: YouTubeMusicConfiguration = .default,
        observeEnvironment: Bool = true,
        startAutomatically: Bool = true,
        makeHTTPClient: @escaping (String) -> YouTubeMusicHTTPClient = { YouTubeMusicHTTPClient(baseURL: $0) },
        makeWebSocket: @escaping (@escaping @Sendable (Data) async -> Void,
                                 @escaping @Sendable (PearDisconnectReason) async -> Void) -> any YouTubeMusicWebSocketConnecting = {
            YouTubeMusicWebSocketClient(onMessage: $0, onDisconnect: $1)
        },
        appIsRunning: (() -> Bool)? = nil,
        fetchArtwork: @escaping (URL) async throws -> Data = { try await ImageService.shared.fetchImageData(from: $0) }
    ) {
        self.configuration = configuration
        self.makeHTTPClient = makeHTTPClient
        self.makeWebSocket = makeWebSocket
        self.fetchArtwork = fetchArtwork
        self.httpClient = makeHTTPClient(configuration.baseURL)
        self.authManager = YouTubeMusicAuthManager(httpClient: httpClient)
        self.reconnectDelay = configuration.reconnectDelay.lowerBound
        self.appIsRunning = appIsRunning ?? {
            NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == configuration.bundleIdentifier }
        }
        if observeEnvironment {
            setupAppStateObserver()
        }
        if startAutomatically { startConnection() }
    }

    deinit {
        initializationTask?.cancel()
        pollingTask?.cancel()
        artworkFetchTask?.cancel()
        reconnectTask?.cancel()
        appStateObserver?.cancel()
        updateTimer?.invalidate()
        httpClient.cancelAllRequests()
        let auth = authManager
        let socket = webSocketClient
        Task { await auth.invalidateToken(); await socket?.disconnect() }
    }

    func stopConnection() {
        enabled = false
        appStateObserver?.cancel()
        appStateObserver = nil
        resetConnection(resetDelay: true)
        resetPlaybackState()
    }

    private func isCurrent(_ expectedGeneration: UInt64) -> Bool {
        enabled && generation == expectedGeneration && !Task.isCancelled && isActive()
    }

    private func resetConnection(resetDelay: Bool, keepAuthentication: Bool = false) {
        generation &+= 1
        initializationTask?.cancel()
        initializationTask = nil
        initializationID = nil
        pollingTask?.cancel()
        pollingTask = nil
        pollID = nil
        artworkFetchTask?.cancel()
        artworkFetchTask = nil
        artworkID = nil
        artworkURL = nil
        cancelReconnect(resetDelay: resetDelay)
        stopPeriodicUpdates()
        let oldSocket = webSocketClient
        webSocketClient = nil
        socketID = nil
        let oldAuth = authManager
        httpClient.cancelAllRequests()
        httpClient = makeHTTPClient(configuration.baseURL)
        if !keepAuthentication { authManager = YouTubeMusicAuthManager(httpClient: httpClient) }
        Task {
            if !keepAuthentication { await oldAuth.invalidateToken() }
            await oldSocket?.disconnect()
        }
    }

    // MARK: - MediaControllerProtocol Implementation
    func play() async { await sendCommand(endpoint: "/play", method: "POST") }
    
    func pause() async { await sendCommand(endpoint: "/pause", method: "POST") }
    
    func togglePlay() async {
        guard enabled else { return }
        if !isActive() { launchApp() }
        await sendCommand(endpoint: "/toggle-play", method: "POST")
    }
    
    func nextTrack() async { await sendCommand(endpoint: "/next", method: "POST") }

    func previousTrack() async { await sendCommand(endpoint: "/previous", method: "POST") }
    
    func seek(to time: Double) async {
        let payload = ["seconds": time]
        await sendCommand(endpoint: "/seek-to", method: "POST", body: payload)
    }

    func setVolume(_ level: Double) async {
        let clampedLevel = max(0.0, min(1.0, level))
        let volumePercentage = Int(clampedLevel * 100)
        let payload = ["volume": volumePercentage]
        await sendCommand(endpoint: "/volume", method: "POST", body: payload)
    }
    func fetchShuffleState() async { await sendCommand(endpoint: "/shuffle", method: "GET", refresh: false) }
    func fetchRepeatMode() async { await sendCommand(endpoint: "/repeat-mode", method: "GET", refresh: false) }
    
    func toggleShuffle() async { await sendCommand(endpoint: "/shuffle", method: "POST") }
    func toggleRepeat() async { await sendCommand(endpoint: "/switch-repeat", method: "POST") }

    func isActive() -> Bool { enabled && appIsRunning() }

    func updatePlaybackInfo() async {
        guard isActive(), pollID == nil else { return }
        let expected = generation
        let id = UUID()
        pollID = id
        defer { if pollID == id { pollID = nil } }
        let auth = authManager
        let http = httpClient
        do {
            // Socket retry delays must not suspend authenticated HTTP fallback.
            // Without a credential, let the bounded reconnect own authentication.
            if reconnectTask != nil, await auth.currentToken == nil { return }
            let token = try await auth.authenticate()
            guard isCurrent(expected) else { return }
            let revision = metadataRevision
            let response = try await http.getPlaybackInfo(token: token)
            guard isCurrent(expected) else { return }
            if metadataRevision == revision { updatePlaybackState(with: response) }
            // A socket position can supersede the song snapshot without making
            // favorite reconciliation obsolete. Bind that readback to the track
            // current when its request starts, including its album.
            let track = (playbackState.title, playbackState.artist, playbackState.album)
            do {
                let like = try await http.getLikeState(token: token)
                guard isCurrent(expected), track == (playbackState.title, playbackState.artist, playbackState.album) else { return }
                playbackState.isFavorite = like.state?.uppercased() == "LIKE"
            } catch YouTubeMusicError.authenticationRequired {
                authenticationRejected(generation: expected)
            } catch { /* Older Pear versions may not expose like state. */ }
        } catch YouTubeMusicError.authenticationRequired {
            authenticationRejected(generation: expected)
        } catch is CancellationError { }
        catch { /* The bounded reconnect loop handles API startup and restarts. */ }
    }

    // MARK: - Private Methods
    private func setupAppStateObserver() {
        appStateObserver = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    let launchNotifications = NSWorkspace.shared.notificationCenter.notifications(
                        named: NSWorkspace.didLaunchApplicationNotification
                    )
                    
                    for await notification in launchNotifications {
                        await self?.handleAppLaunched(notification)
                    }
                }
                
                group.addTask {
                    let terminateNotifications = NSWorkspace.shared.notificationCenter.notifications(
                        named: NSWorkspace.didTerminateApplicationNotification
                    )
                    
                    for await notification in terminateNotifications {
                        await self?.handleAppTerminated(notification)
                    }
                }
            }
        }
    }
    
    private func handleAppLaunched(_ notification: Notification) async {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == configuration.bundleIdentifier else {
            return
        }
        
        resetConnection(resetDelay: true)
        startConnection()
    }

    private func handleAppTerminated(_ notification: Notification) async {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == configuration.bundleIdentifier else { return }
        resetConnection(resetDelay: true)
        resetPlaybackState()
    }

    func startConnection() {
        guard isActive(), initializationID == nil, webSocketClient == nil else { return }
        let id = UUID()
        let expected = generation
        initializationID = id
        initializationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.initializationID == id {
                    self.initializationID = nil
                    self.initializationTask = nil
                }
            }
            let auth = self.authManager
            do {
                let token = try await auth.authenticate()
                guard self.isCurrent(expected) else { return }
                try await self.setupWebSocket(token: token, generation: expected)
                guard self.isCurrent(expected) else { return }
                await self.updatePlaybackInfo()
            } catch is CancellationError { }
            catch {
                guard self.isCurrent(expected) else { return }
                self.startPeriodicUpdates()
                self.scheduleReconnect()
            }
        }
    }

    private func setupWebSocket(token: String, generation expected: UInt64) async throws {
        guard let wsURL = WebSocketURLBuilder.buildURL(from: configuration.baseURL) else {
            throw YouTubeMusicError.invalidURL
        }
        let id = UUID()
        let client = makeWebSocket(
            { [weak self] data in await self?.receive(data, generation: expected, socketID: id) },
            { [weak self] reason in await self?.handleWebSocketDisconnect(reason, generation: expected, socketID: id) }
        )
        // Install identity before resuming the socket; an immediate failure is still ours.
        socketID = id
        webSocketClient = client
        do {
            try await client.connect(to: wsURL, with: token)
            guard isCurrent(expected), socketID == id else { await client.disconnect(); return }
        } catch {
            if socketID == id { socketID = nil; webSocketClient = nil }
            await client.disconnect()
            throw error
        }
    }

    private func receive(_ data: Data, generation expected: UInt64, socketID id: UUID) async {
        guard isCurrent(expected), socketID == id,
              WebSocketMessage(from: data) != nil || (try? JSONDecoder().decode(PlaybackResponse.self, from: data)) != nil else { return }
        metadataRevision &+= 1
        cancelReconnect(resetDelay: true)
        stopPeriodicUpdates()
        await handleWebSocketMessage(data)
    }

    private func handleWebSocketMessage(_ data: Data) async {
        guard let message = WebSocketMessage(from: data) else {
            if let response = try? JSONDecoder().decode(PlaybackResponse.self, from: data) {
                updatePlaybackState(with: response)
            }
            return
        }
        switch message.type {
        case .playerInfo, .videoChanged, .playerStateChanged:
            if let data = message.extractData(),
               let response = PlaybackResponse.from(websocketData: data) {
                updatePlaybackState(with: response)
            }

        case .positionChanged:
            guard let data = message.extractData() else { return }

            var position: Double? = nil
            if let pos = data["position"] as? Double {
                position = pos
            } else if let elapsed = data["elapsedSeconds"] as? Double {
                position = elapsed
            }
            guard let newPosition = position else { return }

            // Threshold position updates: the websocket pushes ~1/s (often
            // more), and an always-new lastUpdated defeated the Equatable
            // check so every tick republished the whole playback state.
            guard abs(newPosition - playbackState.currentTime) > 0.25 else { return }
            var copied = playbackState
            copied.currentTime = newPosition
            copied.lastUpdated = Date()
            playbackState = copied

        case .repeatChanged:
            guard let data = message.extractData() else { return }
            var copy = playbackState

            if let repeatStr = data["repeat"] as? String {
                switch repeatStr.uppercased() {
                case "NONE": copy.repeatMode = .off
                case "ALL": copy.repeatMode = .all
                case "ONE": copy.repeatMode = .one
                default: break
                }
            }
            copy.lastUpdated = Date()
            if copy != playbackState { playbackState = copy }

        case .shuffleChanged:
            guard let data = message.extractData() else { return }
            var copy = playbackState
            if let shuffle = data["shuffle"] as? Bool { copy.isShuffled = shuffle }
            else if let shuffle = data["isShuffled"] as? Bool { copy.isShuffled = shuffle }
            copy.lastUpdated = Date()
            if copy != playbackState { playbackState = copy }

        case .volumeChanged:
            guard let data = message.extractData() else { return }
            var copy = playbackState
            if let volume = data["volume"] as? Double {
                copy.volume = volume / 100.0
            } else if let volume = data["volume"] as? Int {
                copy.volume = Double(volume) / 100.0
            }
            copy.lastUpdated = Date()
            if copy != playbackState { playbackState = copy }
        }
    }
    
    private func handleWebSocketDisconnect(_ reason: PearDisconnectReason, generation expected: UInt64, socketID id: UUID) async {
        guard isCurrent(expected), socketID == id else { return }
        socketID = nil
        webSocketClient = nil
        if case .unauthorized = reason {
            authenticationRejected(generation: expected)
        } else {
            resetConnection(resetDelay: false, keepAuthentication: true)
            startPeriodicUpdates()
            scheduleReconnect()
        }
    }

    private func authenticationRejected(generation expected: UInt64) {
        guard isCurrent(expected) else { return }
        // Retire the credential and all its in-flight consumers together. Do not
        // retry the command: a mutating command must never be replayed implicitly.
        resetConnection(resetDelay: false)
        scheduleReconnect()
    }

    private func cancelReconnect(resetDelay: Bool) {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectID = nil
        if resetDelay { reconnectDelay = configuration.reconnectDelay.lowerBound }
    }

    private func scheduleReconnect() {
        guard isActive(), reconnectTask == nil else { return }
        let delay = reconnectDelay
        let expected = generation
        let id = UUID()
        reconnectID = id
        reconnectTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, self.isCurrent(expected), self.reconnectID == id else { return }
            self.reconnectTask = nil
            self.reconnectID = nil
            self.reconnectDelay = min(delay * 2, self.configuration.reconnectDelay.upperBound)
            self.startConnection()
        }
    }

    private func startPeriodicUpdates() {
        guard isActive(), updateTimer == nil else { return }
        updateTimer = Timer.scheduledTimer(withTimeInterval: configuration.updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.pollingTask == nil else { return }
                let expected = self.generation
                self.pollingTask = Task { [weak self] in
                    await self?.updatePlaybackInfo()
                    if self?.generation == expected { self?.pollingTask = nil }
                }
            }
        }
    }

    private func stopPeriodicUpdates() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    func pollPlaybackState() async {
        if !isActive() {
            return
        }
        
        await fetchRepeatMode()
        await fetchShuffleState()
        await updatePlaybackInfo()
    }
    
    private func sendCommand(
        endpoint: String,
        method: String = "POST",
        body: (any Codable & Sendable)? = nil,
        refresh: Bool = true
    ) async {
        guard isActive() else { return }
        let expected = generation
        let auth = authManager
        let http = httpClient
        do {
            // Socket retry delays must not suspend authenticated HTTP fallback.
            // Without a credential, let the bounded reconnect own authentication.
            if reconnectTask != nil, await auth.currentToken == nil { return }
            let token = try await auth.authenticate()
            guard isCurrent(expected) else { return }
            let data = try await http.sendCommand(
                endpoint: endpoint,
                method: method,
                body: body,
                token: token
            )
            guard isCurrent(expected) else { return }
            // Lightweight endpoint-specific parsing
            if endpoint == "/shuffle" {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let shuffleState = json["state"] as? Bool {
                    playbackState.isShuffled = shuffleState
                } else {
                    playbackState.isShuffled = !playbackState.isShuffled
                }
            } else if endpoint == "/repeat-mode" {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let mode = json["mode"] as? String { updateRepeatMode(mode) }
                }
            }  else if endpoint == "/switch-repeat" {
                // Find next repeat mode
                let nextMode: RepeatMode
                switch playbackState.repeatMode {
                case .off: nextMode = .all
                case .all: nextMode = .one
                case .one: nextMode = .off
                }
                playbackState.repeatMode = nextMode
            } else if refresh && (webSocketClient == nil || endpoint == "/like") {
                try await Task.sleep(for: .milliseconds(100))
                guard isCurrent(expected) else { return }
                await updatePlaybackInfo()
            }
        } catch YouTubeMusicError.authenticationRequired {
            authenticationRejected(generation: expected)
        } catch { /* Failed commands are not automatically replayed. */ }
    }
    
    private func updatePlaybackState(with response: PlaybackResponse) {
        var newState = playbackState
        
        newState.isPlaying = !response.isPaused

        if let title = response.title {
            newState.title = title
        }

        if let artist = response.artist {
            newState.artist = artist
        }

        if let album = response.album {
            newState.album = album
        }

        if let elapsed = response.elapsedSeconds {
            newState.currentTime = elapsed
        }

        if let duration = response.songDuration {
            newState.duration = duration
        }

        newState.lastUpdated = Date()
        
        if let shuffled = response.isShuffled {
            newState.isShuffled = shuffled
        }
        
        if let mode = response.repeatMode {
            switch mode {
            case 0: newState.repeatMode = .off
            case 1: newState.repeatMode = .all
            case 2: newState.repeatMode = .one
            default: break
            }
        }

        if let volume = response.volume {
            newState.volume = volume / 100.0
        }

        let trackChanged = newState.title != playbackState.title
            || newState.artist != playbackState.artist
            || newState.album != playbackState.album
        if trackChanged {
            newState.artwork = nil
            newState.isFavorite = false
        }
        if newState != playbackState { playbackState = newState }

        // Position ticks must not restart artwork or extend track-change peeks.
        if trackChanged || (response.imageSrc != nil && response.imageSrc != artworkURL) {
            artworkFetchTask?.cancel()
            artworkID = nil
            artworkURL = response.imageSrc
            guard let artworkURL, let url = URL(string: artworkURL) else { return }
            let id = UUID()
            let expected = generation
            let fetch = fetchArtwork
            artworkID = id
            artworkFetchTask = Task { [weak self] in
                do {
                    let data = try await fetch(url)
                    guard let self, self.isCurrent(expected), self.artworkID == id else { return }
                    self.playbackState.artwork = data
                    self.artworkFetchTask = nil
                } catch {
                    guard let self, self.generation == expected, self.artworkID == id else { return }
                    // A later snapshot can retry this URL. An obsolete failure
                    // must not retire a newer in-flight or successful image.
                    self.artworkID = nil
                    self.artworkURL = nil
                    self.artworkFetchTask = nil
                }
            }
        }
    }

    private func resetPlaybackState() {
        // MusicManager ignores the initial distantPast sentinel. An intentional
        // reset is a current snapshot that must clear the accepted old endpoint.
        playbackState = PlaybackState(
            bundleIdentifier: configuration.bundleIdentifier,
            isPlaying: false,
            lastUpdated: Date()
        )
    }
    
    private func launchApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: configuration.bundleIdentifier) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

     private func updateRepeatMode(_ mode: String) {
        var target: RepeatMode? = nil
        switch mode {
            case "NONE": target = .off
            case "ALL": target = .all
            case "ONE": target = .one
            default: break
        }
        if let target, target != playbackState.repeatMode { playbackState.repeatMode = target }
    }
    
}
