//
//  YouTubeMusicController.swift
//  boringNotch
//

//  Created By Alexander on 2025-03-30.
//  Modified by Pranav on 2025-06-16.


import Foundation
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
    private var playbackInfoCancellable: AnyCancellable?
    private var isAuthenticating = false
    private let authQueue = DispatchQueue(label: "com.boringnotch.youtubemusicauth", qos: .background)
    
    init() {
        setupAppStateObservers()
        authQueue.async { [weak self] in
            self?.authenticateAndSetup()
        }
    }
    
    deinit {
        stopPeriodicUpdates()
        cancellables.forEach { $0.cancel() }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    
    // MARK: - Authentication
    
    private func authenticateAndSetup() {
        // Prevent multiple concurrent authentication attempts
        guard !isAuthenticating else { return }
        
        isAuthenticating = true
        getAccessToken { [weak self] success in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isAuthenticating = false
                if success {
                    self.startPeriodicUpdates()
                    self.updatePlaybackInfo()
                } else {
                    // Retry authentication after a delay if it fails
                    DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 5) { [weak self] in
                        self?.authenticateAndSetup()
                    }
                }
            }
        }
    }
    
    private func getAccessToken(completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(baseURL)/auth/boringNotch") else {
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        URLSession.shared.dataTaskPublisher(for: request)
            .map { data, response -> Data in
                return data
            }
            .decode(type: AuthResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completionStatus in
                switch completionStatus {
                case .failure(_):
                    completion(false)
                case .finished:
                    break
                }
            }, receiveValue: { [weak self] response in
                self?.accessToken = response.accessToken
                completion(true)
            })
            .store(in: &cancellables)
    }
    
    // MARK: - Protocol Implementation
    
    func play() {
        sendCommand(endpoint: "/play", method: "POST")
        updatePlaybackInfo()
    }
    
    func pause() {
        sendCommand(endpoint: "/pause", method: "POST")
        updatePlaybackInfo()
    }
    
    func togglePlay() {
        if !isActive() {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: playbackState.bundleIdentifier) {
                NSWorkspace.shared.open(url)
            }
        }
        sendCommand(endpoint: "/toggle-play", method: "POST")
        updatePlaybackInfo()
    }
    
    func nextTrack() {
        sendCommand(endpoint: "/next", method: "POST")
        updatePlaybackInfo()
    }
    
    func previousTrack() {
        sendCommand(endpoint: "/previous", method: "POST")
        updatePlaybackInfo()
    }
    
    func seek(to time: Double) {
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
                authenticateAndSetup()
                return
            }
            
            request.httpBody = jsonData
            
            URLSession.shared.dataTaskPublisher(for: request)
                .tryMap { data, response -> Data in
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw URLError(.badServerResponse)
                    }
                    
                    if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                        throw URLError(.userAuthenticationRequired)
                    } else if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
                        throw URLError(.badServerResponse)
                    }
                    
                    return data
                }
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        print("Seek error: \(error)")
                        if let urlError = error as? URLError, urlError.code == .userAuthenticationRequired {
                            self?.accessToken = nil
                            self?.authenticateAndSetup()
                        }
                    }
                }, receiveValue: { [weak self] _ in
                    // Update playback info after seeking
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        self?.updatePlaybackInfo()
                    }
                })
                .store(in: &cancellables)
            
        } catch {
            print("Error encoding seek data: \(error)")
            return
        }
    }
    
    func fetchShuffleState() {
        sendCommand(endpoint: "/shuffle", method: "GET")
    }
    
    func toggleShuffle() {
        sendCommand(endpoint: "/shuffle", method: "POST")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.fetchShuffleState()
        }
    }

    func toggleRepeat() {
        sendCommand(endpoint: "/switch-repeat", method: "POST")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.fetchRepeatMode()
        }
    }

    func fetchRepeatMode() {
        sendCommand(endpoint: "/repeat-mode", method: "GET")
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
        fetchRepeatMode()
        fetchShuffleState()
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
        guard let request = createAuthenticatedRequest(for: "/api/v1/song") else { return }
        
        let backgroundQueue = DispatchQueue.global(qos: .utility)
        
        backgroundQueue.async { [weak self] in
            guard let self = self else { return }
            
            playbackInfoCancellable?.cancel()
            
            playbackInfoCancellable = URLSession.shared.dataTaskPublisher(for: request)
                .tryMap { data, response -> Data in
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw URLError(.badServerResponse)
                    }
                    
                    // Check for authentication errors
                    if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                        // Re-authenticate and retry later
                        DispatchQueue.main.async { [weak self] in
                            self?.accessToken = nil
                            self?.authenticateAndSetup()
                        }
                        throw URLError(.userAuthenticationRequired)
                    } else if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
                        throw URLError(.badServerResponse)
                    }
                    
                    return data
                }
                .decode(type: PlaybackResponse.self, decoder: JSONDecoder())
                .subscribe(on: backgroundQueue)
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { _ in }, receiveValue: { [weak self] response in
                    self?.updatePlaybackState(with: response)
                })
        }
    }
    
    private func updatePlaybackState(with response: PlaybackResponse) {
        playbackState.isPlaying = !response.isPaused
        playbackState.title = response.title
        playbackState.artist = response.artist
        playbackState.album = response.album ?? ""
        playbackState.currentTime = response.elapsedSeconds
        playbackState.duration = response.songDuration
        playbackState.lastUpdated = Date()
        
        if let isShuffled = response.isShuffled {
            playbackState.isShuffled = isShuffled
        }

        // Load artwork if available
        if let artworkURL = response.imageSrc, let url = URL(string: artworkURL) {
            DispatchQueue.global(qos: .background).async { [weak self] in
                do {
                    let artworkData = try Data(contentsOf: url)
                    DispatchQueue.main.async {
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
        
        fetchRepeatMode()
        fetchShuffleState()
        
        updatePlaybackInfo()
    }

    private func sendCommand(endpoint: String, method: String = "GET") {
        guard let url = URL(string: "\(baseURL)/api/v1\(endpoint)") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            authenticateAndSetup()
            return
        }
        
        URLSession.shared.dataTaskPublisher(for: request)
            .tryMap { data, response -> Data in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    throw URLError(.userAuthenticationRequired)
                } else if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
                    throw URLError(.badServerResponse)
                }
                
                return data
            }
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    if let urlError = error as? URLError, urlError.code == .userAuthenticationRequired {
                        // Authentication error - token might be expired
                        self?.accessToken = nil
                        self?.authenticateAndSetup()
                        
                        // Try the command again after authentication
                        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 2) { [weak self] in
                            self?.sendCommand(endpoint: endpoint, method: method)
                        }
                    }
                }
            }, receiveValue: { [weak self] data in
                // Handle data based on endpoint
                if endpoint == "/shuffle" || endpoint == "/shuffle-status" {
                    do {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                        let shuffleState = json["state"] as? Bool {
                            DispatchQueue.main.async {
                                self?.playbackState.isShuffled = shuffleState
                            }
                        }
                    } catch {
                        print("Error parsing shuffle state: \(error)")
                    }
                } else if endpoint == "/repeat-mode" {
                    do {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                        let mode = json["mode"] as? String {
                            self?.updateRepeatMode(mode)
                        }
                    } catch {
                        print("Error parsing repeat mode: \(error)")
                    }
                }

                // Update playback info for relevant commands
                self?.updatePlaybackInfo()
            })
            .store(in: &cancellables)
    }
    
    private func createAuthenticatedRequest(for endpoint: String) -> URLRequest? {
        guard let token = accessToken, let url = URL(string: "\(baseURL)\(endpoint)") else {
            if accessToken == nil {
                // Token is missing, try to authenticate again
                authenticateAndSetup()
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
