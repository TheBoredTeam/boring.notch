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

class YouTubeMusicController: MediaControllerProtocol {
    // MARK: - Properties
    @Published var playbackState: PlaybackState = .init(
        bundleIdentifier: "com.github.th-ch.youtube-music"
    )

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    private let baseURL = "http://localhost:26538"
    private var accessToken: String?
    private var periodicUpdateTask: Task<Void, Never>?
    private var notificationTask: Task<Void, Never>?
    private var isAuthenticating = false
    private let decoder = JSONDecoder()
    
    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        return URLSession(configuration: config)
    }()
    
    
    init() {
        setupAppStateObservers()
        Task { await authenticateAndSetup() }
    }
    
    deinit {
        stopPeriodicUpdates()
        notificationTask?.cancel()
    }
    
    // MARK: - Authentication
    
    private func authenticateAndSetup() async {
        guard !isAuthenticating else { return }
        
        isAuthenticating = true
        let success = await getAccessToken()
        isAuthenticating = false
        if success {
            await startPeriodicUpdates()
            await updatePlaybackInfo()
        } else {
            try? await Task.sleep(for: .seconds(5))
            await authenticateAndSetup()
        }
    }
    
    private func getAccessToken() async -> Bool {
        guard let url = URL(string: "\(baseURL)/auth/boringNotch") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        do {
            let (data, _) = try await urlSession.data(for: request)
            let response = try decoder.decode(AuthResponse.self, from: data)
            accessToken = response.accessToken
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - Protocol Implementation
    
    func play() async { await sendCommand(endpoint: "/play", method: "POST", refresh: true) }
    
    func pause() async { await sendCommand(endpoint: "/pause", method: "POST", refresh: true) }
    
    func togglePlay() async {
        if !isActive(),
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: playbackState.bundleIdentifier) {
            NSWorkspace.shared.open(url)
        }
        await sendCommand(endpoint: "/toggle-play", method: "POST", refresh: true)
    }
    
    func nextTrack() async { await sendCommand(endpoint: "/next", method: "POST", refresh: true) }
    
    func previousTrack() async { await sendCommand(endpoint: "/previous", method: "POST", refresh: true) }
    
    func seek(to time: Double) async {
        let payload = ["seconds": time]
        guard let jsonData = try? JSONEncoder().encode(payload) else { return }
        await sendCommand(endpoint: "/seek-to", method: "POST", body: jsonData, refresh: true)
    }
    
    func fetchShuffleState() async { await sendCommand(endpoint: "/shuffle", method: "GET", refresh: false) }
    func toggleShuffle() async { await sendCommand(endpoint: "/shuffle", method: "POST", refresh: true) }
    func toggleRepeat() async { await sendCommand(endpoint: "/switch-repeat", method: "POST", refresh: true) }
    func fetchRepeatMode() async { await sendCommand(endpoint: "/repeat-mode", method: "GET", refresh: false) }

    func isActive() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == playbackState.bundleIdentifier
        }
    }
    
    // MARK: - Private Methods
    
    private func setupAppStateObservers() {
        notificationTask = Task { @Sendable [weak self] in
            await withTaskGroup(of: Void.self) { group in
                // Handle app launch notifications
                group.addTask {
                    let launchNotifications = NSWorkspace.shared.notificationCenter.notifications(
                        named: NSWorkspace.didLaunchApplicationNotification
                    )
                    
                    for await notification in launchNotifications {
                        await self?.handleAppStateChange(notification: notification)
                    }
                }
                
                // Handle app termination notifications
                group.addTask {
                    let terminateNotifications = NSWorkspace.shared.notificationCenter.notifications(
                        named: NSWorkspace.didTerminateApplicationNotification
                    )
                    
                    for await notification in terminateNotifications {
                        await self?.handleAppStateChange(notification: notification)
                    }
                }
            }
        }
    }
    
    private func handleAppStateChange(notification: Notification) async {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == playbackState.bundleIdentifier else {
            return
        }
        
        if notification.name == NSWorkspace.didLaunchApplicationNotification {
            await startPeriodicUpdates()
        } else if notification.name == NSWorkspace.didTerminateApplicationNotification {
            stopPeriodicUpdates()
            self.playbackState = PlaybackState(
                bundleIdentifier: self.playbackState.bundleIdentifier,
                isPlaying: false
            )
        }
    }
    
    private func startPeriodicUpdates() async {
        stopPeriodicUpdates() // Ensure we don't create multiple timers
        
        // Only start the timer if the app is actually running
        guard isActive() else { return }
        
        periodicUpdateTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.updatePlaybackInfo()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        await updatePlaybackInfo()
    }
    
    private func stopPeriodicUpdates() {
        periodicUpdateTask?.cancel()
        periodicUpdateTask = nil
    }

    private func updateRepeatMode(_ mode: String? = nil) {
        var target: RepeatMode? = nil
        if let mode = mode {
            switch mode {
                case "NONE": target = .off
                case "ALL": target = .all
                case "ONE": target = .one
                default: break
            }
        }
        if let target, target != playbackState.repeatMode { playbackState.repeatMode = target }
    }

    func updatePlaybackInfo() async {
        if !isActive() {
            playbackState = PlaybackState(bundleIdentifier: playbackState.bundleIdentifier, isPlaying: false)
            stopPeriodicUpdates()
            return
        }

        guard let request = await createAuthenticatedRequest(for: "/api/v1/song") else { return }
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            
            // Check for authentication errors
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                // Re-authenticate and retry later
                self.accessToken = nil
                await authenticateAndSetup()
                throw URLError(.userAuthenticationRequired)
            } else if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
                throw URLError(.badServerResponse)
            }

            let playbackResponse = try decoder.decode(PlaybackResponse.self, from: data)
            await updatePlaybackState(with: playbackResponse)
            
        } catch {
            // Handle error silently for now, as this is called periodically
        }
    }
    
    private func updatePlaybackState(with response: PlaybackResponse) async {
        let now = Date()
        var updatedState = playbackState

        updatedState.isPlaying = !response.isPaused
        updatedState.title = response.title
        updatedState.artist = response.artist
        updatedState.album = response.album ?? ""
        updatedState.currentTime = response.elapsedSeconds
        updatedState.duration = response.songDuration
        updatedState.lastUpdated = now

        if let shuffled = response.isShuffled { updatedState.isShuffled = shuffled }

        if let artworkURL = response.imageSrc, let url = URL(string: artworkURL) {
            Task.detached { [weak self] in
                do {
                    let data = try await ImageService.shared.fetchImageData(from: url)
                    await MainActor.run { [weak self] in self?.playbackState.artwork = data }
                } catch { /* ignore */ }
            }
        }
        playbackState = updatedState
    }
    
    func pollPlaybackState() async {
        if !isActive() {
            return
        }
        
        await fetchRepeatMode()
        await fetchShuffleState()
        await updatePlaybackInfo()
    }


    private func sendCommand(endpoint: String, method: String = "GET", body: Data? = nil, refresh: Bool) async {
        let path = "/api/v1\(endpoint)"
        guard let url = URL(string: "\(baseURL)\(path)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body { request.httpBody = body; request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        
        guard let token = accessToken else { await authenticateAndSetup(); return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 { throw URLError(.userAuthenticationRequired) }
            if (200..<300).contains(httpResponse.statusCode) == false { throw URLError(.badServerResponse) }

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
            }

            if refresh {
                try? await Task.sleep(for: .milliseconds(100))
                await updatePlaybackInfo()
            }
        } catch {
            if let urlError = error as? URLError, urlError.code == .userAuthenticationRequired {
                accessToken = nil
                await authenticateAndSetup()
            }
        }
    }
    
    private func createAuthenticatedRequest(for endpoint: String) async -> URLRequest? {
        guard let token = accessToken, let url = URL(string: "\(baseURL)\(endpoint)") else {
            if accessToken == nil {
                // Token is missing, try to authenticate again
                await authenticateAndSetup()
            }
            return nil
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }
}

// MARK: - API Response Models

struct AuthResponse: Codable {
    let accessToken: String
}

struct PlaybackResponse: Codable {
    let isPaused: Bool
    let title: String
    let artist: String
    let album: String?
    let elapsedSeconds: Double
    let songDuration: Double
    let imageSrc: String?
    let repeatMode: Int?
    let isShuffled: Bool?
}
