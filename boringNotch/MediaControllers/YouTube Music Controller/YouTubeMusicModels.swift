//
//  YouTubeMusicModels.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-14.
//

import Foundation

// MARK: - Configuration
struct YouTubeMusicConfiguration: Sendable {
    let baseURL: String
    let bundleIdentifier: String
    let reconnectDelay: ClosedRange<TimeInterval>
    let updateInterval: TimeInterval
    
    static let `default` = YouTubeMusicConfiguration(
        baseURL: "http://localhost:26538",
        bundleIdentifier: "com.github.th-ch.youtube-music",
        reconnectDelay: 1...60,
        updateInterval: 2.0
    )
}

// MARK: - API Models
struct AuthResponse: Decodable, Sendable {
    let accessToken: String
}

struct PlaybackResponse: Decodable, Sendable {
    let isPaused: Bool
    let title: String?
    let artist: String?
    let album: String?
    let elapsedSeconds: Double?
    let songDuration: Double?
    let imageSrc: String?
    let repeatMode: Int?
    let isShuffled: Bool?
    let volume: Double?
}

// MARK: - WebSocket Message Types
enum WebSocketMessageType: String, Sendable {
    case playerInfo = "PLAYER_INFO"
    case videoChanged = "VIDEO_CHANGED"
    case playerStateChanged = "PLAYER_STATE_CHANGED"
    case positionChanged = "POSITION_CHANGED"
    case volumeChanged = "VOLUME_CHANGED"
    case repeatChanged = "REPEAT_CHANGED"
    case shuffleChanged = "SHUFFLE_CHANGED"
}

struct WebSocketMessage {
    let type: WebSocketMessageType
    let rawData: Data
    private let parsedJSON: [String: Any]?

    init?(from data: Data) {
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
        guard let typeString = json?["type"] as? String,
              let messageType = WebSocketMessageType(rawValue: typeString) else {
            return nil
        }

        self.type = messageType
        self.rawData = data
        self.parsedJSON = json
    }

    func extractData() -> [String: Any]? {
        parsedJSON
    }
}

// MARK: - Extensions
extension PlaybackResponse {
    static func from(websocketData: [String: Any]) -> PlaybackResponse? {
        let songData = websocketData["song"] as? [String: Any]
        
        let isPaused: Bool
        if let paused = songData?["isPaused"] as? Bool {
            isPaused = paused
        } else if let playing = websocketData["isPlaying"] as? Bool {
            isPaused = !playing
        } else {
            isPaused = true
        }
        
        let title = (songData?["title"] as? String) ??
                   (songData?["alternativeTitle"] as? String) ??
                   (websocketData["title"] as? String)
        let artist = (songData?["artist"] as? String) ?? (websocketData["artist"] as? String)
        let album = songData?["album"] as? String

        let elapsed = extractDouble(from: songData, key: "elapsedSeconds") ??
                     extractDouble(from: websocketData, key: "position")

        let duration = extractDouble(from: songData, key: "songDuration") ??
                      extractDouble(from: websocketData, key: "songDuration")
        
        let imageSrc = (songData?["imageSrc"] as? String) ?? (websocketData["imageSrc"] as? String)
        let isShuffled = (websocketData["shuffle"] as? Bool) ?? (songData?["isShuffled"] as? Bool)

        var repeatModeInt: Int? = nil
        if let repeatVal = websocketData["repeat"] as? String {
            switch repeatVal.uppercased() {
            case "NONE": repeatModeInt = 0
            case "ALL": repeatModeInt = 1
            case "ONE": repeatModeInt = 2
            default: break
            }
        } else if let repeatStr = songData?["repeat"] as? String {
            switch repeatStr.uppercased() {
            case "NONE": repeatModeInt = 0
            case "ALL": repeatModeInt = 1
            case "ONE": repeatModeInt = 2
            default: break
            }
        }
        
        let volume = extractDouble(from: websocketData, key: "volume") ?? extractDouble(from: songData, key: "volume")

        return PlaybackResponse(
            isPaused: isPaused,
            title: title,
            artist: artist,
            album: album,
            elapsedSeconds: elapsed,
            songDuration: duration,
            imageSrc: imageSrc,
            repeatMode: repeatModeInt,
            isShuffled: isShuffled,
            volume: volume
        )
    }
    
    func with(elapsedSeconds: Double) -> PlaybackResponse {
        PlaybackResponse(
            isPaused: isPaused,
            title: title,
            artist: artist,
            album: album,
            elapsedSeconds: elapsedSeconds,
            songDuration: songDuration,
            imageSrc: imageSrc,
            repeatMode: repeatMode,
            isShuffled: isShuffled,
            volume: volume
        )
    }
}

private func extractDouble(from dict: [String: Any]?, key: String) -> Double? {
    guard let dict = dict else { return nil }
    if let value = dict[key] as? Double {
        return value
    } else if let value = dict[key] as? Int {
        return Double(value)
    }
    return nil
}
