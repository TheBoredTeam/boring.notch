//
//  RatesManager.swift
//  boringNotch
//  Created by Maksymilian Wójcik on 2026-06-10.
//
//  Fetches currency and crypto exchange rates for the Widgets tab.
//  Fiat pairs come from frankfurter.dev (ECB data, no API key); crypto
//  prices from the public CoinGecko API (no key). Pairs are configured
//  in Settings as a comma-separated list, e.g. "USD/PLN, EUR/PLN, BTC/USD".
//

import Combine
import Defaults
import Foundation

struct Rate: Identifiable, Equatable {
    let pair: String
    let value: Double
    let isCrypto: Bool

    var id: String { pair }
}

@MainActor
final class RatesManager: ObservableObject {
    static let shared = RatesManager()

    @Published private(set) var rates: [Rate] = []
    @Published private(set) var statusMessage: String?

    private var timer: Timer?
    private var subscriberCount = 0
    private let session: URLSession

    /// Supported crypto tickers → CoinGecko ids.
    private static let cryptoIds: [String: String] = [
        "BTC": "bitcoin", "ETH": "ethereum", "SOL": "solana", "XRP": "ripple",
        "DOGE": "dogecoin", "ADA": "cardano", "LTC": "litecoin", "BNB": "binancecoin",
        "DOT": "polkadot", "AVAX": "avalanche-2",
    ]

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        session = URLSession(configuration: config)
    }

    /// Begins periodic refresh. Reference-counted across views.
    func start() {
        subscriberCount += 1
        Task { await refresh() }
        guard timer == nil else { return }
        let interval = max(300, Defaults[.ratesUpdateInterval])
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func stop() {
        subscriberCount = max(0, subscriberCount - 1)
        if subscriberCount == 0 {
            timer?.invalidate()
            timer = nil
        }
    }

    /// Forces an immediate refresh (e.g. after editing the pairs in settings).
    func refresh() async {
        let (fiat, crypto) = Self.parsePairs(Defaults[.ratesPairs])
        guard !fiat.isEmpty || !crypto.isEmpty else {
            rates = []
            statusMessage = "No valid pairs"
            return
        }

        var result: [Rate] = []
        // Fetch independently so one failing source doesn't blank the other.
        async let fiatRates = fetchFiat(fiat)
        async let cryptoRates = fetchCrypto(crypto)
        result.append(contentsOf: (try? await fiatRates) ?? [])
        result.append(contentsOf: (try? await cryptoRates) ?? [])

        // Preserve the configured order.
        let order = (fiat + crypto).map { "\($0.base)/\($0.quote)" }
        rates = result.sorted {
            (order.firstIndex(of: $0.pair) ?? 0) < (order.firstIndex(of: $1.pair) ?? 0)
        }
        statusMessage = rates.isEmpty ? "Rates unavailable" : nil
    }

    // MARK: - Pair parsing

    struct Pair { let base: String; let quote: String }

    /// Splits "USD/PLN, BTC/USD" into fiat and crypto pairs (by base ticker).
    static func parsePairs(_ raw: String) -> (fiat: [Pair], crypto: [Pair]) {
        var fiat: [Pair] = []
        var crypto: [Pair] = []
        for entry in raw.split(separator: ",") {
            let parts = entry.split(separator: "/")
                .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { continue }
            let pair = Pair(base: parts[0], quote: parts[1])
            if cryptoIds[pair.base] != nil {
                crypto.append(pair)
            } else if pair.base.count == 3 && pair.quote.count == 3 {
                fiat.append(pair)
            }
        }
        return (fiat, crypto)
    }

    // MARK: - Networking

    private func fetchFiat(_ pairs: [Pair]) async throws -> [Rate] {
        var result: [Rate] = []
        // frankfurter takes one base per request; group quotes by base.
        let byBase = Dictionary(grouping: pairs, by: { $0.base })
        for (base, group) in byBase {
            let quotes = group.map { $0.quote }.joined(separator: ",")
            guard let url = URL(
                string: "https://api.frankfurter.dev/v1/latest?base=\(base)&symbols=\(quotes)")
            else { continue }
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
            let decoded = try JSONDecoder().decode(FrankfurterResponse.self, from: data)
            for pair in group {
                if let value = decoded.rates[pair.quote] {
                    result.append(
                        Rate(pair: "\(pair.base)/\(pair.quote)", value: value, isCrypto: false))
                }
            }
        }
        return result
    }

    private func fetchCrypto(_ pairs: [Pair]) async throws -> [Rate] {
        guard !pairs.isEmpty else { return [] }
        let ids = Set(pairs.compactMap { Self.cryptoIds[$0.base] }).joined(separator: ",")
        let currencies = Set(pairs.map { $0.quote.lowercased() }).joined(separator: ",")
        guard let url = URL(
            string:
                "https://api.coingecko.com/api/v3/simple/price?ids=\(ids)&vs_currencies=\(currencies)"
        ) else { return [] }
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        let decoded = try JSONDecoder().decode([String: [String: Double]].self, from: data)
        return pairs.compactMap { pair in
            guard let id = Self.cryptoIds[pair.base],
                let value = decoded[id]?[pair.quote.lowercased()]
            else { return nil }
            return Rate(pair: "\(pair.base)/\(pair.quote)", value: value, isCrypto: true)
        }
    }

    private struct FrankfurterResponse: Decodable {
        let rates: [String: Double]
    }
}
