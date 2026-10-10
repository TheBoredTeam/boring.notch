// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

import CryptoKit
import Darwin
import Foundation

/// A serial delegate queue owns all mutable transfer state. Cancellation is
/// enqueued on that same queue, including cancellation before the task starts.
/// URLSession delivers bounded chunks; package bytes are never accumulated in RAM.
final class ExtensionStoreTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    enum Destination: Sendable { case memory, file(URL) }
    struct Validators: Codable, Equatable, Sendable {
        let etag: String?
        let lastModified: String?

        init(etag: String? = nil, lastModified: String? = nil) {
            self.etag = Self.validHeader(etag, maximum: 1_024)
            self.lastModified = Self.validHeader(lastModified, maximum: 128)
        }

        var isEmpty: Bool { etag == nil && lastModified == nil }

        var sanitized: Self { Self(etag: etag, lastModified: lastModified) }

        func merging(_ previous: Self) -> Self {
            Self(etag: etag ?? previous.etag, lastModified: lastModified ?? previous.lastModified)
        }

        private static func validHeader(_ value: String?, maximum: Int) -> String? {
            guard let value, !value.isEmpty, value.utf8.count <= maximum,
                  value.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
            return value
        }
    }

    struct Result: Sendable {
        let data: Data
        let sha256: String
        let byteCount: Int
        let notModified: Bool
        let validators: Validators
    }

    private let url: URL
    private let maximumBytes: Int
    private let destination: Destination
    private let configuration: URLSessionConfiguration
    private let progress: @Sendable (Double?) -> Void
    private let queue: OperationQueue
    private let validators: Validators

    // Access only on queue.
    private var continuation: CheckedContinuation<Result, Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var file: FileHandle?
    private var ownsDestination = false
    private var data = Data()
    private var hasher = SHA256()
    private var byteCount = 0
    private var expectedBytes: Int64 = -1
    private var lastProgressPercent = -1
    private var cancelled = false
    private var completed = false
    private var notModified = false
    private var responseValidators = Validators()

    init(
        url: URL, maximumBytes: Int, destination: Destination,
        configuration: URLSessionConfiguration? = nil,
        validators: Validators = Validators(),
        progress: @escaping @Sendable (Double?) -> Void = { _ in }
    ) {
        self.url = url
        self.maximumBytes = maximumBytes
        self.destination = destination
        self.validators = validators.sanitized
        let configuration = (configuration?.copy() as? URLSessionConfiguration) ?? .ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        configuration.waitsForConnectivity = false
        self.configuration = configuration
        self.progress = progress
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        queue.name = "name.theboring.extension-store-transfer"
        super.init()
    }

    func run() async throws -> Result {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                queue.addOperation { self.start(continuation) }
            }
        } onCancel: {
            self.queue.addOperation {
                self.cancelled = true
                self.finish(.failure(CancellationError()))
            }
        }
    }

    private func start(_ continuation: CheckedContinuation<Result, Error>) {
        guard !cancelled else { continuation.resume(throwing: CancellationError()); return }
        guard self.continuation == nil, !completed else {
            continuation.resume(throwing: ExtensionStoreError.invalidResponse)
            return
        }
        self.continuation = continuation
        guard maximumBytes > 0, ExtensionCatalogURL.isSafeHTTPS(url) else {
            finish(.failure(ExtensionStoreError.unsafeURL))
            return
        }
        if case .file(let destination) = destination {
            let descriptor = destination.withUnsafeFileSystemRepresentation { path in
                path.map { Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600) } ?? -1
            }
            guard descriptor >= 0 else { finish(.failure(CocoaError(.fileWriteUnknown))); return }
            ownsDestination = true
            file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.setValue("BoringNotch-ExtensionStore/1", forHTTPHeaderField: "User-Agent")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if case .memory = destination {
            request.setValue(validators.etag, forHTTPHeaderField: "If-None-Match")
            request.setValue(validators.lastModified, forHTTPHeaderField: "If-Modified-Since")
        }
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        self.session = session
        let task = session.dataTask(with: request)
        self.task = task
        task.resume()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, ExtensionCatalogURL.isSafeHTTPS(url) else {
            completionHandler(nil)
            finish(.failure(ExtensionStoreError.unsafeURL))
            return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard !completed, let response = response as? HTTPURLResponse,
              let url = response.url, ExtensionCatalogURL.isSafeHTTPS(url) else {
            completionHandler(.cancel)
            finish(.failure(ExtensionStoreError.invalidResponse))
            return
        }
        responseValidators = Validators(etag: response.value(forHTTPHeaderField: "ETag"),
                                        lastModified: response.value(forHTTPHeaderField: "Last-Modified"))
        if response.statusCode == 304, case .memory = destination, !validators.isEmpty {
            notModified = true
            completionHandler(.allow)
            return
        }
        guard response.statusCode == 200 else {
            completionHandler(.cancel)
            finish(.failure(ExtensionStoreError.invalidResponse))
            return
        }
        guard response.expectedContentLength <= maximumBytes else {
            completionHandler(.cancel)
            finish(.failure(ExtensionStoreError.downloadTooLarge))
            return
        }
        let encoding = response.value(forHTTPHeaderField: "Content-Encoding")?.lowercased()
        expectedBytes = encoding == nil || encoding == "identity" ? response.expectedContentLength : -1
        progress(expectedBytes > 0 ? 0 : nil)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard !completed else { return }
        guard !notModified else {
            finish(.failure(ExtensionStoreError.invalidResponse))
            return
        }
        guard chunk.count <= maximumBytes - byteCount else {
            finish(.failure(ExtensionStoreError.downloadTooLarge))
            return
        }
        do {
            if let file { try file.write(contentsOf: chunk) }
            else { data.append(chunk) }
            hasher.update(data: chunk)
            byteCount += chunk.count
            if expectedBytes > 0 {
                let value = min(1, Double(byteCount) / Double(expectedBytes))
                let percent = Int(value * 100)
                if percent != lastProgressPercent {
                    lastProgressPercent = percent
                    progress(value)
                }
            }
        } catch { finish(.failure(error)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !completed else { return }
        if let error { finish(.failure(cancelled ? CancellationError() : error)); return }
        if notModified {
            finish(.success(Result(data: Data(), sha256: "", byteCount: 0, notModified: true,
                                   validators: responseValidators.merging(validators))))
            return
        }
        guard byteCount > 0 else { finish(.failure(ExtensionStoreError.emptyDownload)); return }
        if expectedBytes >= 0, byteCount != expectedBytes {
            finish(.failure(ExtensionStoreError.invalidResponse))
            return
        }
        let checksum = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        finish(.success(Result(data: data, sha256: checksum, byteCount: byteCount, notModified: false,
                               validators: responseValidators)))
    }

    private func finish(_ result: Swift.Result<Result, Error>) {
        guard !completed, let continuation else { return }
        completed = true
        self.continuation = nil
        var result = result
        do { try file?.close() } catch { result = .failure(error) }
        file = nil
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        if case .failure = result, case .file(let destination) = destination, ownsDestination {
            try? FileManager.default.removeItem(at: destination)
        }
        continuation.resume(with: result)
    }
}
