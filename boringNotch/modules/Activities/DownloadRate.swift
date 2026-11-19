//
//  DownloadRate.swift
//  boringNotch
//
//  Taille reçue et débit lissé d'un téléchargement dont le pourcentage est inconnu (Firefox .part, Chrome .crdownload).
//  Jamais de pourcentage ni de durée restante : on n'a pas la taille totale.
//

import Foundation

struct DownloadRate: Equatable {
    private struct Sample: Equatable { var bytes: Int64; var at: Date }

    private(set) var bytes: Int64 = 0
    private var samples: [Sample] = []      // les 4 dernières mesures = 3 intervalles
    private var lastGrowth = Date.distantPast

    /// Ajoute une mesure ; ignore un intervalle < 0,2 s ; taille plus petite = remise à zéro.
    mutating func sample(bytes: Int64, at: Date) {
        if let last = samples.last {
            // Même seconde (événement dossier + minuteur) : on ignore, pas de division par ~0.
            guard at.timeIntervalSince(last.at) >= 0.2 else { return }
            // Fichier recréé ou tronqué : nouvelle mesure, jamais de débit négatif.
            if bytes < last.bytes { samples = []; lastGrowth = at }
        }
        if samples.isEmpty { lastGrowth = at }
        else if bytes > self.bytes { lastGrowth = at }
        self.bytes = bytes
        samples.append(Sample(bytes: bytes, at: at))
        if samples.count > 4 { samples.removeFirst() }
    }

    /// Octets/s lissés sur les 3 derniers intervalles ; nil tant qu'il n'y a pas d'intervalle.
    var perSecond: Double? {
        guard let first = samples.first, let last = samples.last, samples.count > 1 else { return nil }
        // ponytail: total sur la fenêtre (= moyenne pondérée par la durée) ; intervalle >= 0,2 s garanti, donc diviseur > 0.
        return Double(last.bytes - first.bytes) / last.at.timeIntervalSince(first.at)
    }

    /// Vrai si la taille n'a pas augmenté depuis au moins 10 s.
    func isPaused(now: Date) -> Bool {
        !samples.isEmpty && now.timeIntervalSince(lastGrowth) >= 10
    }

    /// « 12 Mo · 3,4 Mo/s », « 12 Mo · en pause », « 12 Mo » (sans débit encore).
    func label(now: Date) -> String {
        let size = Self.format(bytes)
        if isPaused(now: now) { return "\(size) · en pause" }
        guard let rate = perSecond, rate > 0 else { return size }
        return "\(size) · \(Self.rateText(rate))"
    }

    static func rateText(_ perSecond: Double) -> String { format(Int64(perSecond)) + "/s" }

    private static func format(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}
