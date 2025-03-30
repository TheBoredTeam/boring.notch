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
    @Published private var playbackState: PlaybackState = PlaybackState(
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
    
    init() {
        authenticateAndSetup()
    }
    
    deinit {
        refreshTimer?.invalidate()
        cancellables.forEach { $0.cancel() }
    }
    
    // MARK: - Authentication
    
    private func authenticateAndSetup() {
        getAccessToken { [weak self] success in
            guard success, let self = self else { return }
            self.startPeriodicUpdates()
            self.updatePlaybackInfo()
        }
    }
    
    private func getAccessToken(completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(baseURL)/auth/boringNotch") else {
            print("Invalid authentication URL")
            completion(false)
            return
        }
        
        URLSession.shared.dataTaskPublisher(for: url)
            .map { $0.data }
            .decode(type: AuthResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completionStatus in
                switch completionStatus {
                case .failure(let error):
                    print("Authentication failed: \(error.localizedDescription)")
                    completion(false)
                case .finished:
                    break
                }
            }, receiveValue: { [weak self] response in
                self?.accessToken = response.accessToken
                print("Successfully obtained YouTube Music access token")
                completion(true)
            })
            .store(in: &cancellables)
    }
    
    // MARK: - Protocol Implementation
    
    func play() {
        sendCommand(endpoint: "/play")
    }
    
    func pause() {
        sendCommand(endpoint: "/pause")
    }
    
    func togglePlay() {
        sendCommand(endpoint: "/playPause")
    }
    
    func nextTrack() {
        sendCommand(endpoint: "/next")
    }
    
    func previousTrack() {
        sendCommand(endpoint: "/previous")
    }
    
    func seek(to time: Double) {
        guard let url = getAuthenticatedURL(for: "/seek-to?position=\(time)") else { return }
        
        URLSession.shared.dataTaskPublisher(for: url)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    print("Seek error: \(error.localizedDescription)")
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
    }
    
    private func updatePlaybackInfo() {
        guard let url = getAuthenticatedURL(for: "/song") else { return }
        
        URLSession.shared.dataTaskPublisher(for: url)
            .map { $0.data }
            .decode(type: PlaybackResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    print("Error fetching playback status: \(error.localizedDescription)")
                }
            }, receiveValue: { [weak self] response in
                self?.updatePlaybackState(with: response)
            })
            .store(in: &cancellables)
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
        if let artworkURL = response.artworkURL, let url = URL(string: artworkURL) {
            DispatchQueue.global(qos: .background).async { [weak self] in
                do {
                    let artworkData = try Data(contentsOf: url)
                    DispatchQueue.main.async {
                        newState.artwork = artworkData
                        self?.playbackState = newState
                    }
                } catch {
                    print("Failed to load artwork: \(error)")
                    DispatchQueue.main.async {
                        self?.playbackState = newState
                    }
                }
            }
        } else {
            playbackState = newState
        }
    }
    
    private func sendCommand(endpoint: String) {
        guard let url = getAuthenticatedURL(for: endpoint) else { return }
        
        URLSession.shared.dataTaskPublisher(for: url)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    print("Command error: \(error.localizedDescription)")
                }
            }, receiveValue: { [weak self] _ in
                self?.updatePlaybackInfo()
            })
            .store(in: &cancellables)
    }
    
    private func getAuthenticatedURL(for endpoint: String) -> URL? {
        guard let token = accessToken, let url = URL(string: "\(baseURL)\(endpoint)") else {
            if accessToken == nil {
                // Token is missing, try to authenticate again
                authenticateAndSetup()
            }
            return nil
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request.url
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
    let artworkURL: String?
}
