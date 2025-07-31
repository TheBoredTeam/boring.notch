//
//  YouTubeMusicController.swift
//  boringNotch
//
//  Created By Alexander on 2025-03-30.
//  Modified by Pranav on 2025-06-16.
//

@preconcurrency import Foundation
import Combine
import SwiftUI

class YouTubeMusicController: MediaControllerProtocol {
    // MARK: - Properties
    @Published var playbackState: PlaybackState = .init(
        bundleIdentifier: "com.github.th-ch.youtube-music",
        isPlaying: true
    )
    
    var playbackStatePublisher: Published<PlaybackState>.Publisher { $playbackState }
    private let baseURL = "http://localhost:26538"
    private var accessToken: String?
    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var isAuthenticating = false
    
    init() {
        setupAppStateObservers()
        Task { [weak self] in
            await self?.authenticateAndSetup()
        }
    }
    
    deinit {
        stopPeriodicUpdates()
        cancellables.forEach { $0.cancel() }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    
    // MARK: - Authentication
    
    private func authenticateAndSetup() async {
        // Prevent multiple concurrent authentication attempts
        guard !isAuthenticating else { return }
        
        await MainActor.run {
            isAuthenticating = true
        }
        
        let success = await getAccessToken()
        
        await MainActor.run { [weak self] in
            guard let self = self else { return }
            self.isAuthenticating = false
            if success {
                self.startPeriodicUpdates()
                self.updatePlaybackInfo()
            } else {
                // Retry authentication after a delay if it fails
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(5))
                    await self?.authenticateAndSetup()
                }
            }
        }
    }
    
    private func getAccessToken() async -> Bool {
        guard let url = URL(string: "\(baseURL)/auth/boringNotch") else {
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(AuthResponse.self, from: data)
            await MainActor.run { [weak self] in
                self?.accessToken = response.accessToken
            }
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - Protocol Implementation
    
    func play() async {
        await sendCommand(endpoint: "/play", method: "POST")
        updatePlaybackInfo()
    }
    
    func pause() async {
        await sendCommand(endpoint: "/pause", method: "POST")
        updatePlaybackInfo()
    }
    
    func togglePlay() async {
        if !isActive() {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: playbackState.bundleIdentifier) {
                NSWorkspace.shared.open(url)
            }
        }
        await sendCommand(endpoint: "/toggle-play", method: "POST")
        updatePlaybackInfo()
    }
    
    func nextTrack() async {
        await sendCommand(endpoint: "/next", method: "POST")
        updatePlaybackInfo()
    }
    
    func previousTrack() async {
        await sendCommand(endpoint: "/previous", method: "POST")
        updatePlaybackInfo()
    }
    
    func seek(to time: Double) async {
        // Format the seek data payload according to the API schema
        let seekData = ["seconds": time]
        
        do {
            // Convert seek data to JSON
            let jsonData = try JSONEncoder().encode(seekData)
            
            guard let url = URL(string: "\(baseURL)/api/v1/seek-to") else { return }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            if let token = accessToken {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            } else {
                await authenticateAndSetup()
                return
            }
            
            request.httpBody = jsonData
            
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    throw URLError(.userAuthenticationRequired)
                } else if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
                    throw URLError(.badServerResponse)
                }
                
                // Update playback info after seeking
                try? await Task.sleep(for: .milliseconds(300))
                updatePlaybackInfo()
                
            } catch {
                print("Seek error: \(error)")
                if let urlError = error as? URLError, urlError.code == .userAuthenticationRequired {
                    await MainActor.run {
                        self.accessToken = nil
                        Task {
                            await self.authenticateAndSetup()
                        }
                    }
                }
            }
            
        } catch {
            print("Error encoding seek data: \(error)")
            return
        }
    }
    
    func fetchShuffleState() async {
        await sendCommand(endpoint: "/shuffle", method: "GET")
    }
    
    func toggleShuffle() async {
        await sendCommand(endpoint: "/shuffle", method: "POST")
        try? await Task.sleep(for: .milliseconds(200))
        await fetchShuffleState()
    }

    func toggleRepeat() async {
        await sendCommand(endpoint: "/switch-repeat", method: "POST")
        try? await Task.sleep(for: .milliseconds(200))
        await fetchRepeatMode()
    }

    func fetchRepeatMode() async {
        await sendCommand(endpoint: "/repeat-mode", method: "GET")
    }

    func isActive() -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { $0.bundleIdentifier == playbackState.bundleIdentifier }
    }
    
    // MARK: - Private Methods
    
    private func setupAppStateObservers() {
        // Register for app launch notifications
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAppStateChange),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        
        // Register for app termination notifications
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAppStateChange),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
    }
    
    @objc private func handleAppStateChange(notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == playbackState.bundleIdentifier else {
            return
        }
        
        if notification.name == NSWorkspace.didLaunchApplicationNotification {
            startPeriodicUpdates()
        } else if notification.name == NSWorkspace.didTerminateApplicationNotification {
            // App has terminated - update state and stop timer
            stopPeriodicUpdates()
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.playbackState = PlaybackState(
                    bundleIdentifier: self.playbackState.bundleIdentifier,
                    isPlaying: false
                )
            }
        }
    }
    
    private func startPeriodicUpdates() {
        stopPeriodicUpdates() // Ensure we don't create multiple timers
        
        // Only start the timer if the app is actually running
        guard isActive() else { return }
        
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updatePlaybackInfo()
        }
        refreshTimer?.tolerance = 0.5
        
        // Initial update when timer starts
        updatePlaybackInfo()
        Task { [weak self] in
            await self?.fetchRepeatMode()
            await self?.fetchShuffleState()
        }
    }
    
    private func stopPeriodicUpdates() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func updateRepeatMode(_ modeString: String?) {
        guard let modeString = modeString else { return }
        
        let repeatMode: RepeatMode
        switch modeString {
            case "NONE":
                repeatMode = .off
            case "ALL":
                repeatMode = .all
            case "ONE":
                repeatMode = .one
            default:
                repeatMode = .off
        }
        
        if repeatMode != playbackState.repeatMode {
            DispatchQueue.main.async { [weak self] in
                self?.playbackState.repeatMode = repeatMode
            }
        }
    }
    
    func updatePlaybackInfo() {
        if !isActive() {
            playbackState = PlaybackState(bundleIdentifier: playbackState.bundleIdentifier, isPlaying: false)
            stopPeriodicUpdates()
            return
        }
        
        Task { [weak self] in
            guard let self = self else { return }
            guard let request = await self.createAuthenticatedRequest(for: "/api/v1/song") else { return }
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                
                // Check for authentication errors
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    // Re-authenticate and retry later
                    await MainActor.run {
                        self.accessToken = nil
                    }
                    await self.authenticateAndSetup()
                    throw URLError(.userAuthenticationRequired)
                } else if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
                    throw URLError(.badServerResponse)
                }
                
                let playbackResponse = try JSONDecoder().decode(PlaybackResponse.self, from: data)
                await self.updatePlaybackState(with: playbackResponse)
                
            } catch {
                // Handle error silently for now, as this is called periodically
            }
        }
    }
    
    private func updatePlaybackState(with response: PlaybackResponse) async {
        await MainActor.run { [weak self] in
            guard let self = self else { return }
            self.playbackState.isPlaying = !response.isPaused
            self.playbackState.title = response.title
            self.playbackState.artist = response.artist
            self.playbackState.album = response.album ?? ""
            self.playbackState.currentTime = response.elapsedSeconds
            self.playbackState.duration = response.songDuration
            self.playbackState.lastUpdated = Date()
            
            if let isShuffled = response.isShuffled {
                self.playbackState.isShuffled = isShuffled
            }
        }

        // Load artwork if available
        if let artworkURL = response.imageSrc, let url = URL(string: artworkURL) {
            Task {
                do {
                    let artworkData = try Data(contentsOf: url)
                    await MainActor.run { [weak self] in
                        self?.playbackState.artwork = artworkData
                    }
                } catch { return }
            }
        }
    }
    
    func pollPlaybackState() {
        if !isActive() {
            return
        }
        
        Task { [weak self] in
            await self?.fetchRepeatMode()
            await self?.fetchShuffleState()
            self?.updatePlaybackInfo()
        }
    }

    private func sendCommand(endpoint: String, method: String = "GET") async {
        guard let url = URL(string: "\(baseURL)/api/v1\(endpoint)") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            await authenticateAndSetup()
            return
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw URLError(.userAuthenticationRequired)
            } else if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
                throw URLError(.badServerResponse)
            }
            
            // Handle data based on endpoint
            if endpoint == "/shuffle" || endpoint == "/shuffle-status" {
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let shuffleState = json["state"] as? Bool {
                        await MainActor.run {
                            playbackState.isShuffled = shuffleState
                        }
                    }
                } catch {
                    print("Error parsing shuffle state: \(error)")
                }
            } else if endpoint == "/repeat-mode" {
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let mode = json["mode"] as? String {
                        updateRepeatMode(mode)
                    }
                } catch {
                    print("Error parsing repeat mode: \(error)")
                }
            }

            // Update playback info for relevant commands
            updatePlaybackInfo()
            
        } catch {
            if let urlError = error as? URLError, urlError.code == .userAuthenticationRequired {
                // Authentication error - token might be expired
                accessToken = nil
                await authenticateAndSetup()
                
                // Try the command again after authentication
                try? await Task.sleep(for: .seconds(2))
                await sendCommand(endpoint: endpoint, method: method)
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
