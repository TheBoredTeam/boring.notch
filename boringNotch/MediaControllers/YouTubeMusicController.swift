//
//  YouTubeMusicController.swift
//  boringNotch
//
//  Created By Alexander Greco on 2025-03-30.
//

import Foundation
import Combine
import SwiftUI

class YouTubeMusicController: MediaControllerProtocol {
    // MARK: - Properties
    @Published var playbackState: PlaybackState = .init(
        bundleIdentifier: "com.github.th-ch.youtube-music",
        isPlaying: false,
        title: "",
        artist: "",
        album: "",
        currentTime: 0,
        duration: 0,
        playbackRate: 1,
        lastUpdated: Date()
    )
    
    var playbackStatePublisher: Published<PlaybackState>.Publisher { $playbackState }
    private let baseURL = "http://localhost:26538"
    private var accessToken: String?
    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var isAuthenticating = false
    private let authQueue = DispatchQueue(label: "com.boringnotch.youtubemusicauth", qos: .background)
    private let updateQueue = DispatchQueue(label: "com.boringnotch.youtubemusicupdate", qos: .utility)
    
    init() {
        authQueue.async { [weak self] in
            self?.authenticateAndSetup()
        }
    }
    
    deinit {
        refreshTimer?.invalidate()
        cancellables.forEach { $0.cancel() }
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
                case .failure(let error):
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
    }
    
    func pause() {
        sendCommand(endpoint: "/pause", method: "POST")
    }
    
    func togglePlay() {
        sendCommand(endpoint: "/toggle-play", method: "POST")
    }
    
    func nextTrack() {
        sendCommand(endpoint: "/next", method: "POST")
    }
    
    func previousTrack() {
        sendCommand(endpoint: "/previous", method: "POST")
    }
    
    func seek(to time: Double) {
        guard let url = URL(string: "\(baseURL)/seek-to") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            authenticateAndSetup()
            return
        }
        
        // Create the request body with the seconds value
        let seekData = ["seconds": time]
        
        do {
            request.httpBody = try JSONEncoder().encode(seekData)
        } catch {
            return
        }
        
        URLSession.shared.dataTaskPublisher(for: request)
            .map { data, response -> Data in
                return data
            }
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completion in
                if case .failure(let error) = completion {
                }
            }, receiveValue: { [weak self] _ in
                self?.updatePlaybackInfo()
            })
            .store(in: &cancellables)
    }
    
    func isActive() -> Bool {
        return accessToken != nil
    }
    
    // MARK: - Private Methods
    
    private func startPeriodicUpdates() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updatePlaybackInfo()
        }
        refreshTimer?.tolerance = 0.5
    }
    
    private func updatePlaybackInfo() {
        guard let url = getAuthenticatedURL(for: "/api/v1/song") else { return }
        
        // Use a lower priority queue for network operations
        let backgroundQueue = DispatchQueue.global(qos: .utility)
        
        // Run the network request on a background queue
        backgroundQueue.async { [weak self] in
            guard let self = self else { return }
            
            URLSession.shared.dataTaskPublisher(for: url)
                .map { data, response -> (Data, HTTPURLResponse) in
                    return (data, response as! HTTPURLResponse)
                }
                .tryMap { data, response -> Data in
                    // Check for authentication errors
                    if response.statusCode == 401 || response.statusCode == 403 {
                        
                        // Re-authenticate on main thread and throw error to trigger retry
                        DispatchQueue.main.async { [weak self] in
                            self?.accessToken = nil
                            self?.authenticateAndSetup()
                        }
                        
                        throw URLError(.userAuthenticationRequired)
                    } else if response.statusCode < 200 || response.statusCode >= 300 {
                        throw URLError(.badServerResponse)
                    }
                    
                    return data
                }
                .decode(type: PlaybackResponse.self, decoder: JSONDecoder())
                // Process the data on the background queue
                .subscribe(on: backgroundQueue)
                // Only use the main queue for the final UI update
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        
                        // For network errors, retry after a delay
                        if let urlError = error as? URLError {
                            // Retry logic for network issues
                            let delay: TimeInterval = (urlError.code == .userAuthenticationRequired) ? 2.0 : 1.0
                            DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + delay) { [weak self] in
                                self?.updatePlaybackInfo()
                            }
                        }
                    }
                }, receiveValue: { [weak self] response in
                    
                    self?.updatePlaybackState(with: response)
                })
                .store(in: &self.cancellables)
        }
    }
    
    private func updatePlaybackState(with response: PlaybackResponse) {
        var newState = PlaybackState(
            bundleIdentifier: "com.github.th-ch.youtube-music",
            isPlaying: !response.isPaused,
            title: response.title,
            artist: response.artist,
            album: response.album ?? "",
            currentTime: response.elapsedSeconds,
            duration: response.songDuration,
            playbackRate: 1.0,
            isShuffled: false,
            isRepeating: false,
            lastUpdated: Date()
        )
        
        // Load artwork if available
        if let artworkURL = response.imageSrc, let url = URL(string: artworkURL) {
            DispatchQueue.global(qos: .background).async { [weak self] in
                do {
                    let artworkData = try Data(contentsOf: url)
                    DispatchQueue.main.async {
                        newState.artwork = artworkData
                        self?.playbackState = newState
                    }
                } catch {
                    DispatchQueue.main.async {
                        self?.playbackState = newState
                    }
                }
            }
        }
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
            .map { data, response -> (Data, HTTPURLResponse) in
                return (data, response as! HTTPURLResponse)
            }
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    // Attempt to recover from network errors by re-authenticating
                    DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 1) { [weak self] in
                        self?.authenticateAndSetup()
                    }
                }
            }, receiveValue: { [weak self] data, response in
                if response.statusCode == 401 || response.statusCode == 403 {
                    // Authentication error - token might be expired
                    self?.accessToken = nil
                    self?.authenticateAndSetup()
                    
                    // Try the command again after a short delay
                    DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 2) { [weak self] in
                        self?.sendCommand(endpoint: endpoint, method: method)
                    }
                } else if response.statusCode >= 200 && response.statusCode < 300 {
                    self?.updatePlaybackInfo()
                }
            })
            .store(in: &cancellables)
    }
    
    private func getAuthenticatedURL(for endpoint: String) -> URLRequest? {
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
}
