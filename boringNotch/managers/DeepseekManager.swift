//
//  DeepseekManager.swift
//  boringNotch
//
//  Created on 2026-06-21.
//

import Combine
import Defaults
import Foundation
import SwiftUI

enum DeepseekError: Error, LocalizedError {
    case missingAPIKey
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case decodingFailed
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "API key is missing"
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .decodingFailed:
            return "Failed to decode response"
        case .rateLimited:
            return "Rate limited. Please try again later."
        }
    }
}

final class DeepseekManager: ObservableObject {
    static let shared = DeepseekManager()

    @Published var balanceInfos: [BalanceInfo] = []
    @Published var isAvailable: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    private let baseURL = "https://api.deepseek.com"
    private let session: URLSession
    private static let decoder = JSONDecoder()

    private init() {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15

        self.session = URLSession(configuration: config)
    }

    func fetchBalance() async {
        let apiKey = Defaults[.deepseekAPIKey]

        guard !apiKey.isEmpty else {
            await MainActor.run {
                self.errorMessage = "API key is not configured"
                self.isAvailable = false
                self.balanceInfos = []
            }
            return
        }

        await MainActor.run {
            self.isLoading = true
            self.errorMessage = nil
        }

        do {
            guard let url = URL(string: "\(baseURL)/user/balance") else {
                throw DeepseekError.invalidURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw DeepseekError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200..<300:
                break
            case 429:
                throw DeepseekError.rateLimited
            case 401, 403:
                throw DeepseekError.httpError(httpResponse.statusCode)
            default:
                throw DeepseekError.httpError(httpResponse.statusCode)
            }

            let balanceResponse = try Self.decoder.decode(
                DeepseekBalanceResponse.self, from: data)

            await MainActor.run {
                self.isAvailable = balanceResponse.isAvailable
                self.balanceInfos = balanceResponse.balanceInfos
                self.isLoading = false
                self.errorMessage = nil
            }
        } catch let error as DeepseekError {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
                self.balanceInfos = []
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
                self.balanceInfos = []
            }
        }
    }
}
