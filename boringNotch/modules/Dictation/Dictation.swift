//
//  Dictation.swift
//  boringNotch
//
//  Dictée vocale 100 % locale : micro → SpeechAnalyzer (Apple) → nettoyage par segments → collage.
//  Chaque segment finalisé est nettoyé pendant que tu parles : à l'arrêt, il ne reste que le dernier à traiter.
//

import AVFoundation
import Defaults
import FoundationModels
import OSLog
import Speech
import SwiftUI

/// Niveau sonore lu par l'interface (écrit depuis le thread audio, lu depuis le MainActor).
final class LevelMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var v: Float = 0
    private var top: Float = 0
    var value: Float { lock.lock(); defer { lock.unlock() }; return v }
    /// RMS brut le plus fort depuis `reset()` : sert au filtre de silence.
    var peak: Float { lock.lock(); defer { lock.unlock() }; return top }
    // attaque immédiate, retombée douce
    func push(_ x: Float, rms: Float) { lock.lock(); v = max(x, v * 0.7); top = max(top, rms); lock.unlock() }
    func reset() { lock.lock(); v = 0; top = 0; lock.unlock() }
}

/// Audio du micro → format de l'analyseur. Tout ce qui arrive avant que l'analyseur soit prêt est gardé puis rejoué
/// dans l'ordre : parler dès l'appui sur la touche ne perd plus le début. Écrit depuis le thread audio, d'où le verrou.
@available(macOS 26.0, *)
final class AudioFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [AVAudioPCMBuffer] = []
    private var target: AVAudioFormat?
    private var out: AsyncStream<AnalyzerInput>.Continuation?
    private var converter: AVAudioConverter?

    func reset() { lock.lock(); pending = []; target = nil; out = nil; converter = nil; lock.unlock() }

    func push(_ b: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        if out != nil { convert(b) } else if let c = Self.copy(b) { pending.append(c) }
    }

    /// L'analyseur est prêt : rejoue ce qui a été entendu pendant la préparation, puis passe en direct. Renvoie le nombre de tampons rejoués.
    @discardableResult
    func attach(_ format: AVAudioFormat, _ cont: AsyncStream<AnalyzerInput>.Continuation) -> Int {
        lock.lock(); defer { lock.unlock() }
        target = format; out = cont; converter = nil
        let n = pending.count
        pending.forEach(convert); pending = []
        return n
    }

    /// Fin de l'entrée : vide le convertisseur (sinon les dernières ms de la dernière syllabe restent dedans).
    func finish() {
        lock.lock(); defer { lock.unlock() }
        if let converter, let target, let out, let o = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 4096) {
            converter.convert(to: o, error: nil) { _, s in s.pointee = .endOfStream; return nil }
            if o.frameLength > 0 { out.yield(AnalyzerInput(buffer: o)) }
        }
        out?.finish(); out = nil; pending = []; converter = nil
    }

    private func convert(_ b: AVAudioPCMBuffer) { // verrou déjà pris
        guard let target, let out else { return }
        // Le micro peut changer de format en route (casque Bluetooth qui bascule en mode appel) : nouveau convertisseur.
        if converter == nil || converter?.inputFormat != b.format { converter = AVAudioConverter(from: b.format, to: target) }
        guard let converter else { return }
        let cap = AVAudioFrameCount(Double(b.frameLength) * target.sampleRate / b.format.sampleRate) + 32
        guard let o = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: cap) else { return }
        var fed = false
        converter.convert(to: o, error: nil) { _, s in
            if fed { s.pointee = .noDataNow; return nil }
            fed = true; s.pointee = .haveData; return b
        }
        if o.frameLength > 0 { out.yield(AnalyzerInput(buffer: o)) }
    }

    // ponytail: copie float32 seulement (format demandé à la capture) ; autre format = tampon ignoré.
    private static func copy(_ b: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let s = b.floatChannelData, let c = AVAudioPCMBuffer(pcmFormat: b.format, frameCapacity: b.frameLength),
              let d = c.floatChannelData else { return nil }
        c.frameLength = b.frameLength
        for ch in 0..<Int(b.format.channelCount) { d[ch].update(from: s[ch], count: Int(b.frameLength)) }
        return c
    }
}

/// Capture du micro par AVCaptureSession : choisit le micro indépendamment de la sortie audio.
/// (AVAudioEngine partage une seule unité audio entre entrée et sortie : forcer le micro du Mac avec un casque Bluetooth en sortie
/// faisait lever des exceptions ObjC fatales — -10868, « format.sampleRate == inputHWFormat.sampleRate ».)
/// Tout passe par une file série : startRunning peut bloquer sur CoreAudio, jamais sur le main.
@available(macOS 26.0, *)
final class MicCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "boringnotch.dictation.audio", qos: .userInitiated)
    private let feed: AudioFeed
    private let meter: LevelMeter

    init(feed: AudioFeed, meter: LevelMeter) { self.feed = feed; self.meter = meter }

    /// mic nil = micro du système.
    func start(_ mic: MicDevice?) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            queue.async { c.resume(with: Result { try self.open(mic) }) }
        }
    }

    func stop() { queue.async { self.session.stopRunning() } }

    private func open(_ mic: MicDevice?) throws {
        guard let device = mic.flatMap({ AVCaptureDevice(uniqueID: $0.uid) }) ?? AVCaptureDevice.default(for: .audio) else { throw DictationError.noInput }
        let output = AVCaptureAudioDataOutput()
        output.audioSettings = [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32,
                                AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: true]
        output.setSampleBufferDelegate(self, queue: queue)
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        session.inputs.forEach(session.removeInput); session.outputs.forEach(session.removeOutput)
        guard session.canAddInput(input), session.canAddOutput(output) else { session.commitConfiguration(); throw DictationError.noInput }
        session.addInput(input); session.addOutput(output)
        session.commitConfiguration()
        session.startRunning()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sb: CMSampleBuffer, from connection: AVCaptureConnection) {
        let n = CMSampleBufferGetNumSamples(sb)
        guard n > 0, let fd = CMSampleBufferGetFormatDescription(sb),
              let buf = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(cmAudioFormatDescription: fd), frameCapacity: AVAudioFrameCount(n)) else { return }
        buf.frameLength = AVAudioFrameCount(n)
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sb, at: 0, frameCount: Int32(n), into: buf.mutableAudioBufferList) == noErr,
              let ch = buf.floatChannelData?[0] else { return }
        var sum: Float = 0
        for i in 0..<n { sum += ch[i] * ch[i] }
        let rms = (sum / Float(n)).squareRoot()
        meter.push(min(1, rms * 6), rms: rms) // gain visuel ×6 pour la bulle, RMS brut pour le filtre de silence
        feed.push(buf)
    }
}

@available(macOS 26.0, *)
@MainActor
final class Dictation: ObservableObject {
    static let shared = Dictation()

    enum Phase { case idle, listening, processing }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var partial = ""
    @Published private(set) var error: String?
    @Published private(set) var justDone = false
    @Published private(set) var offer: String?   // règle apprise proposée dans la notch (reste dans les réglages après)
    private var offerTask: Task<Void, Never>?
    private(set) var startedAt = Date()
    let meter = LevelMeter()

    private lazy var capture = MicCapture(feed: feed, meter: meter)
    private var analyzer: SpeechAnalyzer?
    private let feed = AudioFeed()
    private var startTask: Task<Void, Never>?        // préparation en cours : stop() l'attend au lieu de la jeter
    private var tail = ""                            // texte encore volatil (pas finalisé) : récupéré si la finalisation échoue
    private var results: Task<Void, Error>?
    private var chunks: [Task<String, Never>] = []
    private var raws: [String] = []
    private var warm: LanguageModelSession?   // préchauffée pendant que tu parles
    private var flashTask: Task<Void, Never>?
    private var limitTask: Task<Void, Never>?
    private var selection: String?            // texte sélectionné au déclenchement : remplacé, ou transformé par une commande
    private var generation = 0                // invalide un start() resté en attente après un abandon (cancel / erreur)
    private let log = Logger(subsystem: "theboringteam.boringnotch", category: "dictation")

    // MARK: raccourci

    func keyDown() {
        switch (Defaults[.dictationHold], phase) {
        case (_, .idle): startTask = Task { await start() }
        case (false, .listening): Task { await stop() }
        default: break
        }
    }

    func keyUp() {
        if Defaults[.dictationHold], phase == .listening { Task { await stop() } }
    }

    // MARK: cycle

    private func start() async {
        guard phase == .idle else { return }
        phase = .listening; partial = ""; tail = ""; error = nil; justDone = false
        startedAt = .now; meter.reset(); chunks = []; raws = []; selection = nil
        generation += 1
        let g = generation
        let stale = { [self] in generation != g } // seul un abandon invalide : relâcher la touche n'annule plus la préparation
        do {
            guard await AVCaptureDevice.requestAccess(for: .audio) else { throw DictationError.micDenied }
            if stale() { return }
            // Le micro écoute AVANT tout le reste : ce qui est dit pendant la préparation est gardé (AudioFeed) puis rejoué.
            feed.reset()
            let mic = Microphones.resolve(Defaults[.dictationMic])
            try await capture.start(mic)
            if stale() { capture.stop(); return }
            log.info("micro « \((mic ?? Microphones.systemDefault())?.name ?? "?", privacy: .public) » ouvert après \(Int(Date().timeIntervalSince(self.startedAt) * 1000)) ms")

            selection = await TextInserter.selectedText().map { String($0.prefix(4000)) }
            if stale() { return }
            if Defaults[.dictationCleanup] { warm = TextCleanup.warmSession() } // charge le modèle pendant la prise de parole

            let wanted = Locale(identifier: Defaults[.dictationLocale])
            // Réglage expérimental : le modèle de dictée tient compte du vocabulaire (SpeechTranscriber l'ignore).
            var guided = Defaults[.dictationGuidedRecognition]
            let guidedLocale = guided ? await DictationTranscriber.supportedLocale(equivalentTo: wanted) : nil
            if guided, guidedLocale == nil { log.info("langue non gérée par la reconnaissance guidée : repli sur SpeechTranscriber"); guided = false }
            let module: any SpeechModule
            let updates: any AsyncSequence<(String, Bool), any Error> & Sendable // (texte, isFinal), quel que soit le module
            if guided, let locale = guidedLocale {
                // .punctuation : contrairement à SpeechTranscriber, ce module ne ponctue pas par défaut.
                let t = DictationTranscriber(locale: locale, contentHints: [], transcriptionOptions: [.punctuation], reportingOptions: [.volatileResults], attributeOptions: [])
                module = t; updates = t.results.map { (String($0.text.characters), $0.isFinal) }
            } else {
                guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: wanted) else { throw DictationError.unsupported }
                let t = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
                module = t; updates = t.results.map { (String($0.text.characters), $0.isFinal) }
            }
            log.info("reconnaissance : \(guided ? "DictationTranscriber (guidée)" : "SpeechTranscriber", privacy: .public)")
            // Première utilisation : télécharge le modèle de la langue (géré par le système).
            if let req = try await AssetInventory.assetInstallationRequest(supporting: [module]) { try await req.downloadAndInstall() }
            if stale() { return }

            // whileInUse : le modèle de reconnaissance est libéré dès la fin de la dictée (pas de RAM résiduelle).
            let analyzer = SpeechAnalyzer(modules: [module], options: .init(priority: .userInitiated, modelRetention: .whileInUse))
            // Vocabulaire perso (dictionnaire + cibles des substitutions) : seul DictationTranscriber en tient compte.
            let vocab = TextCleanup.vocabulary()
            if !vocab.isEmpty {
                let ctx = AnalysisContext(); ctx.contextualStrings[.general] = vocab
                do { try await analyzer.setContext(ctx) } catch { log.error("vocabulaire non transmis à la reconnaissance : \(error.localizedDescription, privacy: .public)") }
            }
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else { throw DictationError.unsupported }
            try? await analyzer.prepareToAnalyze(in: format) // charge le modèle maintenant, pas au premier mot
            if stale() { return }
            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            self.analyzer = analyzer

            results = Task { [weak self, log] in
                var done = ""
                do {
                    for try await (s, isFinal) in updates {
                        if isFinal { done += s; await self?.finalized(s, partial: done) } else { await self?.setPartial(done + s, tail: s) }
                    }
                } catch { log.error("flux de résultats interrompu : \(error.localizedDescription, privacy: .public)"); throw error }
            }
            try await analyzer.start(inputSequence: stream)
            if stale() { continuation.finish(); await analyzer.cancelAndFinishNow(); return }
            let replayed = feed.attach(format, continuation)
            log.info("analyseur prêt après \(Int(Date().timeIntervalSince(self.startedAt) * 1000)) ms, \(replayed) tampons rejoués")
            // Garde-fou : un micro oublié en mode « basculer » s'arrête seul.
            // ponytail: 3 min en dur.
            limitTask = Task { try? await Task.sleep(for: .seconds(180)); if !Task.isCancelled { await stop() } }
        } catch {
            if stale() { return } // abandonnée entre-temps : ne pas écraser une dictée plus récente
            await fail(error)
        }
    }

    private func stopCapture() { capture.stop() }

    /// Un segment est figé : on le nettoie tout de suite, en série, pendant que la suite est dictée.
    private func finalized(_ s: String, partial p: String) {
        partial = p; tail = ""
        raws.append(s)
        let session = warm ?? (Defaults[.dictationCleanup] ? TextCleanup.warmSession() : nil)
        warm = nil
        let prev = chunks.last
        let locale = Defaults[.dictationLocale]
        chunks.append(Task { _ = await prev?.value; return await TextCleanup.cleanChunk(s, session: session, locale: locale) })
    }

    private func stop() async {
        guard phase == .listening else { return }
        phase = .processing
        limitTask?.cancel(); limitTask = nil
        let g = generation // pas de generation += 1 ici : seul un abandon (clic, erreur) invalide cette dictée
        // Traîne : on relâche la touche un peu avant la fin de la dernière syllabe, et le micro livre par blocs.
        // ponytail: 300 ms en dur.
        try? await Task.sleep(for: .milliseconds(300))
        // Relâché avant la fin de la préparation (dictée courte) : l'audio est déjà en mémoire, on attend l'analyseur.
        let setup = startTask
        let ready = await withDeadline(20) { () async -> Bool? in await setup?.value; return true }
        guard generation == g else { return }          // abandonnée par un clic ou une erreur pendant l'attente
        guard ready != nil else { await fail(DictationError.notReady); return }
        stopCapture()
        feed.finish()

        // Chaque attente est bornée : la dictée ne reste jamais bloquée sur « traitement ».
        let a = analyzer, r = results
        let finished = await withDeadline(6) { () async -> Bool? in
            do { try await a?.finalizeAndFinishThroughEndOfInput(); try await r?.value; return true } catch { return false }
        }
        guard generation == g else { return }          // annulée par un clic pendant l'attente
        if finished != true { r?.cancel(); await a?.cancelAndFinishNow() }
        analyzer = nil; results = nil
        // Finalisation ratée ou trop lente : le dernier bout encore volatil serait perdu, on le garde.
        let unfinalized = finished == true ? "" : tail
        log.info("fin d'écoute : \(self.raws.count) segments, finalisation \(finished == true ? "ok" : "échouée"), reste volatil \(unfinalized.count) car.")

        let all = chunks
        let parts = await withDeadline(12) { () async -> [String]? in
            var out: [String] = []
            for c in all { out.append(await c.value) }
            return out
        }
        guard generation == g else { return }
        // Délai dépassé ou erreur : on colle ce qui a été entendu (règles seulement, sans modèle) plutôt que rien.
        let locale = Defaults[.dictationLocale]
        // Le reste volatil et le texte de secours passent aussi par l'anti-récitation : c'est là que la reconnaissance invente sur un blanc.
        let vocab = TextCleanup.vocabulary()
        let rest = TextCleanup.spoken(TextCleanup.removeFillers(DictationGuards.dropRecitation(unfinalized, vocabulary: vocab)), locale: locale)
        var pieces = parts ?? [TextCleanup.spoken(TextCleanup.removeFillers(
            DictationGuards.dropRecitation((raws + [unfinalized]).joined(separator: " "), vocabulary: vocab)), locale: locale)]
        if parts != nil { pieces.append(rest) }
        var text = TextCleanup.finish(pieces)
        // Prise muette : tout texte serait inventé (rien collé, rien dans l'historique, pas de commande).
        // ponytail: seuil −50 dBFS en dur (Hex) ; réglage si un micro faible est jeté.
        if meter.peak < DictationGuards.silenceRMS {
            log.info("prise muette (pic \(Int(20 * log10(max(self.meter.peak, 1e-6)))) dBFS) : rien collé")
            text = ""
        }
        let sel = selection; selection = nil
        if let sel, !text.isEmpty {
            log.info("sélection \(sel.count) car., premier mot « \(text.split(separator: " ").first.map(String.init) ?? "", privacy: .public) », commande : \(TextCleanup.isCommand(text))")
            if TextCleanup.isCommand(text) {
                // Commande vocale sur la sélection (« raccourcis », « traduis en anglais »…) : le modèle réécrit la sélection.
                let out = await TextCleanup.command(text, on: sel)
                guard generation == g else { return }
                guard let out else { await fail(DictationError.commandFailed); return }
                text = out
            } else {
                if let word = TextCleanup.spelledWord(text) { text = word } // mot épelé → collé d'un bloc
                if let rule = TextCleanup.learn(from: sel, to: text) { propose(rule) } // mot sélectionné puis redicté
            }
        }
        if !text.isEmpty {
            await TextInserter.insert(text)
            if Defaults[.dictationKeepHistory] {
                var h = Defaults[.dictationHistory]
                h.insert(DictationEntry(text: text, raw: (raws + [unfinalized]).joined(separator: " ")), at: 0)
                Defaults[.dictationHistory] = Array(h.prefix(200))
            }
            flash()
        }
        guard generation == g else { return }
        phase = .idle; partial = ""; tail = ""; chunks = []; raws = []; warm = nil
    }

    /// Abandonne tout (clic pendant le traitement) : rien n'est collé.
    func cancel() {
        generation += 1; limitTask?.cancel(); limitTask = nil
        stopCapture(); feed.finish(); results?.cancel(); results = nil
        chunks.forEach { $0.cancel() }; chunks = []; raws = []; warm = nil; selection = nil
        let a = analyzer; analyzer = nil
        Task { await a?.cancelAndFinishNow() }
        phase = .idle; partial = ""
    }

    private func propose(_ rule: String) {
        offer = rule
        offerTask?.cancel()
        // ponytail: 12 s dans la notch ; ensuite la règle reste dans Réglages > Dictée.
        offerTask = Task { try? await Task.sleep(for: .seconds(12)); if !Task.isCancelled { offer = nil } }
    }

    func answerOffer(accept: Bool) {
        guard let rule = offer else { return }
        accept ? TextCleanup.accept(rule) : TextCleanup.dismiss(rule)
        offerTask?.cancel(); offer = nil
    }

    private func flash() {
        justDone = true
        flashTask?.cancel()
        flashTask = Task { try? await Task.sleep(for: .seconds(1.2)); if !Task.isCancelled { justDone = false } }
    }

    private func fail(_ e: Error) async {
        generation += 1; limitTask?.cancel(); limitTask = nil
        stopCapture(); feed.finish(); results?.cancel(); results = nil
        chunks.forEach { $0.cancel() }; chunks = []; raws = []; warm = nil; selection = nil
        await analyzer?.cancelAndFinishNow(); analyzer = nil
        error = (e as? DictationError)?.message ?? e.localizedDescription
        phase = .idle; partial = ""
        flashTask?.cancel()
        flashTask = Task { try? await Task.sleep(for: .seconds(4)); if !Task.isCancelled { error = nil } }
    }

    /// Clic sur la bulle : terminer la dictée en cours.
    func stopNow() {
        switch phase { case .listening: Task { await stop() }; case .processing: cancel(); default: break }
    }

    fileprivate func setPartial(_ s: String, tail t: String) { partial = s; tail = t }

}

enum DictationError: Error {
    case micDenied, unsupported, commandFailed, noInput, notReady
    var message: String {
        switch self {
        case .micDenied: "Accès au micro refusé (Réglages Système > Confidentialité)"
        case .unsupported: "Langue non prise en charge par la dictée Apple"
        case .noInput: "Aucun micro disponible"
        case .notReady: "Modèle de langue encore en préparation, réessaie dans un instant"
        case .commandFailed: "Commande impossible (modèle indisponible ou trop lent)"
        }
    }
}

struct DictationEntry: Codable, Identifiable, Hashable, Defaults.Serializable {
    var id = UUID()
    var date = Date()
    var text: String
    var raw: String
}

// MARK: pastille autour de la notch fermée

@available(macOS 26.0, *)
extension Dictation {
    func activity(height: CGFloat) -> Activity? {
        guard Defaults[.activityDictation] else { return nil }
        if error != nil || phase != .idle || justDone {
            return Activity(id: "dictation", priority: 100, view: AnyView(DictationPill(height: height)))
        }
        if let offer { return Activity(id: "dictation-offer", priority: 90, view: AnyView(DictationOffer(height: height, rule: offer))) }
        return nil
    }
}

/// Bulle ronde (comme celle des agents) : un petit personnage dont la bouche suit ta voix.
/// - écoute : anneau rouge qui pulse avec le niveau + point « REC », il cligne des yeux
/// - traitement : il regarde à gauche et à droite, anneau orange qui tourne
/// - fini : sourire vert qui rebondit
/// - erreur : jaune, « ! »
/// Un clic termine l'écoute, ou abandonne le traitement s'il traîne.
/// Remplace la pastille « micro utilisé » le temps de la dictée (voir PrivacyMonitor).
@available(macOS 26.0, *)
struct DictationPill: View {
    let height: CGFloat
    @ObservedObject private var d = Dictation.shared

    private enum Mood { case listening, thinking, happy, oops }
    private var mood: Mood { d.error != nil ? .oops : d.phase == .listening ? .listening : d.phase == .processing ? .thinking : .happy }
    private var tint: Color {
        switch mood { case .listening: .white; case .thinking: .orange; case .happy: .green; case .oops: .yellow }
    }
    private var diameter: CGFloat { max(height - 8, 18) }

    var body: some View {
        Button { d.stopNow() } label: {
            TimelineView(.animation(minimumInterval: 1.0 / 20)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let level = CGFloat(d.meter.value)
                ZStack {
                    Circle().fill(.black)
                    ring(t: t, level: level)
                    Face(mood: mood == .listening ? .listening(level: level) : mood == .thinking ? .thinking
                         : mood == .happy ? .happy : .oops, color: tint, t: t)
                }
                .frame(width: diameter, height: diameter)
                .scaleEffect(mood == .happy ? 1.12 : 1)
                .overlay(alignment: .topTrailing) { badge(t: t) }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
        .animation(.spring(response: 0.35, dampingFraction: 0.55), value: mood)
        .help(d.error ?? (d.phase == .listening ? "Dictée en cours — cliquer pour terminer" : d.phase == .processing ? "Traitement — cliquer pour annuler" : "Dictée"))
    }

    @ViewBuilder private func ring(t: Double, level: CGFloat) -> some View {
        switch mood {
        case .listening:
            Circle().stroke(Color.red.opacity(0.45 + 0.55 * level), lineWidth: 1.2 + 1.8 * level)
        case .thinking:
            Circle().trim(from: 0, to: 0.3).stroke(Color.orange, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .rotationEffect(.degrees(t * 360 * 1.4))
        case .happy:
            Circle().stroke(Color.green.opacity(0.7), lineWidth: 1.5)
        case .oops:
            Circle().stroke(Color.yellow.opacity(0.8), lineWidth: 1.5)
        }
    }

    @ViewBuilder private func badge(t: Double) -> some View {
        // y ≥ 0 : le haut de la notch rogne tout ce qui dépasse.
        switch mood {
        case .listening:
            Circle().fill(Color.red).frame(width: 7, height: 7)
                .opacity(0.6 + 0.4 * abs(sin(t * 3)))
                .overlay(Circle().stroke(.black, lineWidth: 1.2)).offset(x: 2, y: 1)
        case .oops:
            Text("!").font(.system(size: 7, weight: .heavy)).foregroundStyle(.black)
                .frame(width: 11, height: 11).background(Circle().fill(Color.yellow))
                .overlay(Circle().stroke(.black, lineWidth: 1.5)).offset(x: 3, y: 1)
        default: EmptyView()
        }
    }

    /// Visage en pixels, dans le style de la mascotte des agents.
    private struct Face: View {
        enum Kind { case listening(level: CGFloat), thinking, happy, oops }
        let mood: Kind, color: Color, t: Double
        private let px: CGFloat = 2.1

        // Grille 9 × 7 ; (colonne, ligne)
        private var pixels: [(Int, Int)] {
            var p: [(Int, Int)] = []
            func rect(_ c: ClosedRange<Int>, _ r: ClosedRange<Int>) { for y in r { for x in c { p.append((x, y)) } } }
            switch mood {
            case .listening(let level):
                let blink = t.truncatingRemainder(dividingBy: 3.4) < 0.12
                blink ? rect(2...2, 2...2) : rect(2...2, 1...2)
                blink ? rect(6...6, 2...2) : rect(6...6, 1...2)
                switch level {                         // la bouche s'ouvre avec la voix
                case ..<0.10: rect(3...5, 5...5)
                case ..<0.28: rect(3...5, 4...5)
                case ..<0.55: rect(2...6, 4...5)
                default:      rect(2...6, 4...6)
                }
            case .thinking:
                let look = Int(t / 0.4) % 2 == 0 ? 0 : 2   // regarde à gauche, puis à droite
                rect((1 + look)...(1 + look), 1...2); rect((5 + look)...(5 + look), 1...2)
                rect(4...4, 5...5)
            case .happy:
                p += [(1, 2), (2, 1), (3, 2), (5, 2), (6, 1), (7, 2)]   // yeux ^ ^
                p += [(2, 4), (6, 4)]; rect(3...5, 5...5)                // sourire
            case .oops:
                rect(2...2, 1...2); rect(6...6, 1...2)
                p += [(2, 5), (3, 4), (4, 5), (5, 4), (6, 5)]            // bouche ondulée
            }
            return p
        }

        var body: some View {
            Canvas { ctx, _ in
                for (x, y) in pixels {
                    ctx.fill(Path(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: px, height: px)), with: .color(color))
                }
            }
            .frame(width: px * 9, height: px * 7)
        }
    }
}

/// Règle « avant → après » ou mot seul appris, sur une ligne, pastille verte (valider) et rouge (ignorer). Même gabarit que les autres pastilles.
@available(macOS 26.0, *)
struct DictationOffer: View {
    let height: CGFloat
    let rule: String
    @State private var pop = false

    var body: some View {
        ActivityPill(height: height, help: rule.contains("=>") ? "Règle apprise : l'ajouter aux substitutions ?" : "Mot appris : l'ajouter au dictionnaire ?") {
            Image(systemName: "sparkles").foregroundStyle(.yellow).symbolEffect(.pulse)
            Text(rule.replacingOccurrences(of: " => ", with: " → "))
                .lineLimit(1).truncationMode(.middle).frame(maxWidth: 260)
            tile("checkmark", .green, accept: true)
            tile("xmark", .red, accept: false)
        }
        .scaleEffect(pop ? 1 : 0.85)
        .onAppear { withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) { pop = true } }
    }

    private func tile(_ icon: String, _ color: Color, accept: Bool) -> some View {
        Button { Dictation.shared.answerOffer(accept: accept) } label: {
            Image(systemName: icon).font(.system(size: 8, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 16, height: 16).background(Circle().fill(color))
        }
        .buttonStyle(.plain)
    }
}
