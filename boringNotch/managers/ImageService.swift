// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

//
//  ImageService.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-13.
//

import Foundation
import Defaults

protocol ImageServiceProtocol {
    func fetchImageData(from url: URL) async throws -> Data
}

final class ImageService: ImageServiceProtocol {
    static let shared = ImageService()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.urlCache = Self.makeArtworkCache()
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.httpShouldSetCookies = false
        self.session = URLSession(configuration: config)

        performLegacyCacheCleanupIfNeeded()
    }

    private static func makeArtworkCache() -> URLCache {
        let memoryCapacity = 50 * 1024 * 1024
        do {
            // LaunchServices starts apps with cwd=/; a relative diskPath
            // cannot create its database there. Use the native user cache root.
            let root = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
            let directory = root
                .appendingPathComponent(Bundle.main.bundleIdentifier ?? "theboringteam.boringnotch", isDirectory: true)
                .appendingPathComponent("artwork_cache", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return URLCache(memoryCapacity: memoryCapacity, diskCapacity: 100 * 1024 * 1024,
                            directory: directory)
        } catch {
            // A read-only or unavailable home should not prevent artwork loads.
            return URLCache(memoryCapacity: memoryCapacity, diskCapacity: 0, directory: nil)
        }
    }

    private func performLegacyCacheCleanupIfNeeded() {
        if !Defaults[.didClearLegacyURLCacheV1] {
            URLCache.shared.removeAllCachedResponses()
            Defaults[.didClearLegacyURLCacheV1] = true
        }
    }

    func fetchImageData(from url: URL) async throws -> Data {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw URLError(.unsupportedURL)
        }
        let (data, _) = try await session.data(from: url)
        return data
    }
}
