//
//  KairoSocket.swift
//  Kairo
//
//  Persistent WebSocket connection to Kairo backend server.
//  Receives real-time events: motion alerts, reminders,
//  command responses, speaking notifications.
//  Auto-reconnects on disconnect.
//

import AVFoundation
import Combine
import Foundation

// MARK: - Event Types

enum KairoEventType: String, Codable {
    case proposalAsk = "proposal_ask"
    case proposalExecuted = "proposal_executed"
    case proposalNotify = "proposal_notify"
    case proposalExpired = "proposal_expired"
    case proposalResolved = "proposal_resolved"
    case proposalAudio = "proposal_audio"
    case cameraMotion = "camera_motion"
    case cameraAnalysis = "camera_analysis"
    case agentProgress = "agent_progress"
}

struct KairoProposal: Codable {
    let id: String
    let trigger: String
    let message: String
    let approvalLevel: String?
    let actionName: String?
    let status: String?
    let imageB64: String?

    enum CodingKeys: String, CodingKey {
        case id, trigger, message, status
        case approvalLevel = "approval_level"
        case actionName = "action_name"
        case imageB64 = "image_b64"
    }
}

struct KairoEvent: Codable {
    let type: String
    let proposal: KairoProposal?
    let camera: String?
    let location: String?
    let timestamp: Double?
    let description: String?
    let imageB64: String?
    let audioB64: String?
    // Agent progress fields
    let message: String?
    let taskId: String?
    let status: String?
    let iteration: Int?

    enum CodingKeys: String, CodingKey {
        case type, proposal, camera, location, timestamp, description, message, status, iteration
        case imageB64 = "image_b64"
        case audioB64 = "audio_b64"
        case taskId = "task_id"
    }
}

// MARK: - WebSocket Manager

class KairoSocket: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    static let shared = KairoSocket()

    @Published var isConnected = false
    @Published var lastEvent: KairoEvent?
    @Published var latestMotionImage: Data?
    @Published var latestMotionDescription: String = ""
    @Published var latestMotionCamera: String = ""
    @Published var pendingProposal: KairoProposal?

    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var reconnectTimer: Timer?

    // Exponential backoff for the legacy Python backend. Most users never
    // set up that backend (the new in-process Brain replaces it) — so
    // hammering localhost:8420 every 5s spams the log endlessly. After
    // `maxNoisyAttempts` failures, we keep trying but stop logging, and
    // back off to up to `maxReconnectInterval`.
    private var reconnectInterval: TimeInterval = 5.0
    private let maxReconnectInterval: TimeInterval = 120.0
    private var consecutiveFailures: Int = 0
    private let maxNoisyAttempts: Int = 3
    /// Set to true via env `KAIRO_BACKEND=off` to skip the legacy WebSocket
    /// entirely. Use this if you only need the in-process Brain.
    private let isDisabled: Bool = {
        let v = ProcessInfo.processInfo.environment["KAIRO_BACKEND"]?.lowercased() ?? ""
        return v == "off" || v == "false" || v == "0" || v == "no"
    }()

    var serverURL: String {
        if let env = ProcessInfo.processInfo.environment["KAIRO_BACKEND_URL"], !env.isEmpty {
            return env
        }
        return UserDefaults.standard.string(forKey: "kairoServerURL")
            ?? "ws://localhost:8420/ws"
    }

    var httpBaseURL: String {
        serverURL
            .replacingOccurrences(of: "ws://", with: "http://")
            .replacingOccurrences(of: "wss://", with: "https://")
            .replacingOccurrences(of: "/ws", with: "")
    }

    override init() {
        super.init()
        if isDisabled {
            print("[KairoSocket] disabled via KAIRO_BACKEND=off")
        } else {
            connect()
        }
    }

    // MARK: - Connection

    func connect() {
        guard !isDisabled else { return }
        disconnect()

        guard let url = URL(string: serverURL) else {
            print("[KairoSocket] Invalid URL: \(serverURL)")
            return
        }

        session = URLSession(
            configuration: .default,
            delegate: self,
            delegateQueue: OperationQueue.main
        )

        webSocket = session?.webSocketTask(with: url)
        webSocket?.resume()

        if consecutiveFailures < maxNoisyAttempts {
            print("[KairoSocket] Connecting to \(serverURL)")
        }
        listenForMessages()
    }

    func disconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        session = nil
        DispatchQueue.main.async { self.isConnected = false }
    }

    private func scheduleReconnect() {
        guard !isDisabled, reconnectTimer == nil else { return }
        consecutiveFailures += 1

        // Exponential backoff: 5s → 10s → 30s → 60s → 120s (cap)
        switch consecutiveFailures {
        case 1: reconnectInterval = 5
        case 2: reconnectInterval = 10
        case 3: reconnectInterval = 30
        case 4: reconnectInterval = 60
        default: reconnectInterval = maxReconnectInterval
        }

        if consecutiveFailures == maxNoisyAttempts + 1 {
            print("[KairoSocket] suppressing further reconnect logs (backend unavailable)")
        }

        reconnectTimer = Timer.scheduledTimer(withTimeInterval: reconnectInterval, repeats: false) { [weak self] _ in
            self?.reconnectTimer = nil
            self?.connect()
        }
    }

    /// Call from urlSession(_:webSocketTask:didOpenWithProtocol:) — resets the
    /// backoff once we get a real handshake. Already-implemented delegate
    /// methods are unaffected.
    fileprivate func didOpenSuccessfully() {
        consecutiveFailures = 0
        reconnectInterval = 5
    }

    // MARK: - Messaging

    private func listenForMessages() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self?.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                // Continue listening
                self?.listenForMessages()

            case .failure(let error):
                if let self, self.consecutiveFailures < self.maxNoisyAttempts {
                    print("[KairoSocket] Receive error: \(error.localizedDescription)")
                }
                DispatchQueue.main.async { self?.isConnected = false }
                self?.scheduleReconnect()
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let event = try? JSONDecoder().decode(KairoEvent.self, from: data) else {
            print("[KairoSocket] Failed to decode: \(text.prefix(100))")
            return
        }

        DispatchQueue.main.async {
            self.lastEvent = event

            switch event.type {
            case "camera_motion", "camera_analysis":
                self.latestMotionCamera = event.camera ?? "Camera"
                if let desc = event.description {
                    self.latestMotionDescription = desc
                }
                if let b64 = event.imageB64, let imgData = Data(base64Encoded: b64) {
                    self.latestMotionImage = imgData
                }

            case "proposal_ask":
                self.pendingProposal = event.proposal

            case "proposal_audio":
                if let b64 = event.audioB64, let audioData = Data(base64Encoded: b64) {
                    self.playAudio(audioData)
                }

            case "agent_progress":
                if let message = event.message {
                    KairoFeedbackEngine.shared.flash(message, duration: 3.0)
                }

            default:
                break
            }
        }
    }

    // MARK: - Send

    func sendRaw(_ text: String) {
        webSocket?.send(.string(text)) { error in
            if let error { print("[KairoSocket] Send error: \(error)") }
        }
    }

    func respondToProposal(id: String, approved: Bool) {
        let payload: [String: Any] = [
            "type": "proposal_respond",
            "proposal_id": id,
            "approved": approved
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let text = String(data: data, encoding: .utf8) {
            webSocket?.send(.string(text)) { error in
                if let error { print("[KairoSocket] Send error: \(error)") }
            }
        }
    }

    // MARK: - Audio Playback

    var audioPlayer: AVAudioPlayer?

    func playAudio(_ data: Data) {
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.play()
        } catch {
            print("[KairoSocket] Audio playback error: \(error)")
        }
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol proto: String?) {
        didOpenSuccessfully()
        if consecutiveFailures == 0 {
            print("[KairoSocket] Connected")
        }
        DispatchQueue.main.async { self.isConnected = true }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        if consecutiveFailures < maxNoisyAttempts {
            print("[KairoSocket] Disconnected (code: \(closeCode.rawValue))")
        }
        DispatchQueue.main.async { self.isConnected = false }
        scheduleReconnect()
    }
}

// MARK: - HTTP API Calls

extension KairoSocket {

    func sendTextCommand(_ text: String, completion: @escaping (String) -> Void) {
        guard let url = URL(string: "\(httpBaseURL)/text") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = ["text": text, "tts": false]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let responseText = json["response"] as? String else {
                DispatchQueue.main.async { completion("Server error") }
                return
            }
            DispatchQueue.main.async { completion(responseText) }
        }.resume()
    }

    func sendVoiceCommand(_ text: String, completion: @escaping (String, Data?) -> Void) {
        guard let url = URL(string: "\(httpBaseURL)/text") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = ["text": text, "tts": true]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            let httpResponse = response as? HTTPURLResponse
            let responseText = httpResponse?.value(forHTTPHeaderField: "X-Kairo-Response") ?? ""
            DispatchQueue.main.async { completion(responseText, data) }
        }.resume()
    }

    func sendAudioToServer(_ audioData: Data, completion: @escaping (String, String, Data?) -> Void) {
        guard let url = URL(string: "\(httpBaseURL)/voice") else {
            DispatchQueue.main.async { completion("", "Server not configured", nil) }
            return
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45  // Voice pipeline needs STT + think + TTS

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"command.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        print("[KairoSocket] Sending \(audioData.count) bytes to /voice")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                print("[KairoSocket] Voice request failed: \(error.localizedDescription)")
                DispatchQueue.main.async { completion("", "Connection error: \(error.localizedDescription)", nil) }
                return
            }

            let httpResponse = response as? HTTPURLResponse
            let statusCode = httpResponse?.statusCode ?? 0

            guard statusCode == 200 else {
                let errorBody = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown error"
                print("[KairoSocket] Voice endpoint error \(statusCode): \(errorBody.prefix(200))")
                DispatchQueue.main.async { completion("", "Server error (\(statusCode))", nil) }
                return
            }

            let transcript = httpResponse?.value(forHTTPHeaderField: "X-Kairo-Transcript") ?? ""
            let responseText = httpResponse?.value(forHTTPHeaderField: "X-Kairo-Response") ?? ""

            print("[KairoSocket] Voice response: transcript=\(transcript.prefix(50)), response=\(responseText.prefix(50)), audio=\(data?.count ?? 0) bytes")

            DispatchQueue.main.async { completion(transcript, responseText, data) }
        }.resume()
    }

    func checkHealth(completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(httpBaseURL)/health") else {
            completion(false)
            return
        }
        URLSession.shared.dataTask(with: url) { data, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async { completion(ok) }
        }.resume()
    }
}
