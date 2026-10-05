//
//  GitHubAPIService.swift
//  boringNotch
//
//  Thin client for GitHub's official REST + GraphQL APIs. Features:
//  - Bearer auth from the Keychain (token never logged)
//  - In-memory ETag cache (conditional requests don't count against rate limits)
//  - Rate-limit tracking (X-RateLimit-*, Retry-After)
//

import Foundation

enum GitHubAPIError: Error, Equatable {
    case notAuthenticated
    case unauthorized               // token rejected / revoked
    case rateLimited(resetAt: Date?)
    case offline
    case forbidden                  // e.g. missing token scope
    case server(Int)
    case decoding
}

actor GitHubAPIService {
    static let shared = GitHubAPIService()

    private let session: URLSession
    private let decoder: JSONDecoder
    private var etagCache: [String: (etag: String, data: Data)] = [:]
    private(set) var rateLimitResetAt: Date?
    private(set) var rateLimitRemaining: Int?

    private init() {
        let config = URLSessionConfiguration.ephemeral   // no on-disk cache of private data
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func clearCache() { etagCache.removeAll() }

    // MARK: - Snapshot

    /// Fetches everything the HUD may display. Optional sections fail soft.
    func fetchSnapshot(wants: GitHubSections) async throws -> GitHubSnapshot {
        let user: GitHubUser = try await get("/user")
        var snapshot = GitHubSnapshot(user: user)
        let login = user.login

        // Auth/rate-limit/offline errors abort the whole refresh; anything else
        // (e.g. 403 on a single repo) only drops that section.
        func soft<T>(_ body: () async throws -> T) async throws -> T? {
            do { return try await body() }
            catch GitHubAPIError.forbidden { return nil }
            catch GitHubAPIError.server { return nil }
            catch GitHubAPIError.decoding { return nil }
        }

        if wants.contains(.notifications) {
            snapshot.notifications = try await soft { try await self.get("/notifications", query: ["per_page": "50"]) as [GitHubNotification] } ?? []
        }
        if wants.contains(.pullRequests) {
            snapshot.assignedPRs = try await soft { try await self.search("is:pr is:open assignee:\(login) archived:false") }
        }
        if wants.contains(.reviewRequests) {
            snapshot.reviewRequests = try await soft { try await self.search("is:pr is:open review-requested:\(login) archived:false") }
        }
        if wants.contains(.issues) {
            snapshot.assignedIssues = try await soft { try await self.search("is:issue is:open assignee:\(login) archived:false") }
        }
        if wants.contains(.activity) || wants.contains(.actions) {
            let events: [GitHubEvent] = try await soft {
                try await self.get("/users/\(login)/events", query: ["per_page": "30"])
            } ?? []
            snapshot.events = Array(events.prefix(10))

            if wants.contains(.actions) {
                var seen = Set<String>()
                let repos = events.map(\.repo.name).filter { seen.insert($0).inserted }.prefix(3)
                for repo in repos {
                    if let resp: GitHubWorkflowRunsResponse = try await soft({
                        try await self.get("/repos/\(repo)/actions/runs", query: ["per_page": "1"])
                    }), var run = resp.workflowRuns.first {
                        run.repoName = repo
                        snapshot.workflowRuns.append(run)
                    }
                }
            }
        }
        if wants.contains(.contributions) {
            snapshot.contributions = try await soft { try await self.fetchContributions() }
        }
        snapshot.fetchedAt = Date()
        return snapshot
    }

    // MARK: - Requests

    private func search(_ q: String) async throws -> GitHubSearchResponse {
        try await get("/search/issues", query: ["q": q, "per_page": "5", "sort": "updated"])
    }

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = path
        if !query.isEmpty { components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = components.url else { throw GitHubAPIError.decoding }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let key = url.absoluteString
        if let cached = etagCache[key] { request.setValue(cached.etag, forHTTPHeaderField: "If-None-Match") }

        let data = try await send(request, cacheKey: key)
        do { return try decoder.decode(T.self, from: data) } catch { throw GitHubAPIError.decoding }
    }

    private func fetchContributions() async throws -> GitHubContributions {
        let query = """
        { viewer { contributionsCollection {
            totalCommitContributions totalPullRequestContributions
            totalPullRequestReviewContributions totalIssueContributions
            contributionCalendar { totalContributions weeks { contributionDays { date contributionCount } } }
        } } }
        """
        var request = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])
        let data = try await send(request, cacheKey: nil)

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let viewer = (root["data"] as? [String: Any])?["viewer"] as? [String: Any],
              let cc = viewer["contributionsCollection"] as? [String: Any],
              let cal = cc["contributionCalendar"] as? [String: Any],
              let weeks = cal["weeks"] as? [[String: Any]] else { throw GitHubAPIError.decoding }

        let days: [GitHubContributionDay] = weeks
            .flatMap { ($0["contributionDays"] as? [[String: Any]]) ?? [] }
            .compactMap { d in
                guard let date = d["date"] as? String, let c = d["contributionCount"] as? Int else { return nil }
                return GitHubContributionDay(date: date, count: c)
            }
        return GitHubContributions(
            total: cal["totalContributions"] as? Int ?? 0,
            commits: cc["totalCommitContributions"] as? Int ?? 0,
            pullRequests: cc["totalPullRequestContributions"] as? Int ?? 0,
            reviews: cc["totalPullRequestReviewContributions"] as? Int ?? 0,
            issues: cc["totalIssueContributions"] as? Int ?? 0,
            recentDays: Array(days.suffix(14)))
    }

    private func send(_ original: URLRequest, cacheKey: String?) async throws -> Data {
        guard let token = GitHubAuthService.loadToken() else { throw GitHubAPIError.notAuthenticated }
        if let reset = rateLimitResetAt, rateLimitRemaining == 0, reset > Date() {
            throw GitHubAPIError.rateLimited(resetAt: reset)
        }
        var request = original
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
                                           .cannotConnectToHost, .dnsLookupFailed, .timedOut].contains(error.code) {
            throw GitHubAPIError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw GitHubAPIError.server(0) }

        if let remaining = http.value(forHTTPHeaderField: "X-RateLimit-Remaining").flatMap(Int.init) { rateLimitRemaining = remaining }
        if let reset = http.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(TimeInterval.init) {
            rateLimitResetAt = Date(timeIntervalSince1970: reset)
        }

        switch http.statusCode {
        case 200..<300:
            if let cacheKey, let etag = http.value(forHTTPHeaderField: "ETag") { etagCache[cacheKey] = (etag, data) }
            return data
        case 304:
            if let cacheKey, let cached = etagCache[cacheKey] { return cached.data }
            throw GitHubAPIError.server(304)
        case 401:
            throw GitHubAPIError.unauthorized
        case 403, 429:
            if http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" || http.statusCode == 429 {
                let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init).map { Date().addingTimeInterval($0) }
                let reset = retry ?? rateLimitResetAt ?? Date().addingTimeInterval(60)
                rateLimitResetAt = reset; rateLimitRemaining = 0
                throw GitHubAPIError.rateLimited(resetAt: reset)
            }
            throw GitHubAPIError.forbidden
        default:
            throw GitHubAPIError.server(http.statusCode)
        }
    }
}

struct GitHubSections: OptionSet {
    let rawValue: Int
    static let notifications = GitHubSections(rawValue: 1 << 0)
    static let pullRequests = GitHubSections(rawValue: 1 << 1)
    static let reviewRequests = GitHubSections(rawValue: 1 << 2)
    static let issues = GitHubSections(rawValue: 1 << 3)
    static let activity = GitHubSections(rawValue: 1 << 4)
    static let actions = GitHubSections(rawValue: 1 << 5)
    static let contributions = GitHubSections(rawValue: 1 << 6)
}
