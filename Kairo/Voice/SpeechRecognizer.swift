import Speech
import AVFoundation

@MainActor
final class KairoSpeechRecognizer: ObservableObject {
    private let recognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    @Published var transcript: String = ""

    func start() async throws {
        SFSpeechRecognizer.requestAuthorization { _ in }
        request = SFSpeechAudioBufferRecognitionRequest()
        request?.shouldReportPartialResults = true
        let input = audioEngine.inputNode
        input.removeTap(onBus: 0)
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buf, _ in
            self?.request?.append(buf)
        }
        audioEngine.prepare()
        try audioEngine.start()
        task = recognizer?.recognitionTask(with: request!) { [weak self] result, _ in
            if let r = result {
                Task { @MainActor in self?.transcript = r.bestTranscription.formattedString }
            }
        }
    }

    func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        task?.cancel()
        request = nil
    }
}
