//
//  GitHubModels.swift
//  boringNotch
//

import Foundation

struct GitHubUser: Codable, Equatable {
    let login: String
    let avatarURL: URL?
    let name: String?

    enum CodingKeys: String, CodingKey { case login, name; case avatarURL = "avatar_url" }
}

struct GitHubNotification: Codable, Equatable, Identifiable {
    struct Subject: Codable, Equatable { let title: String; let type: String }
    struct Repository: Codable, Equatable { let fullName: String
        enum CodingKeys: String, CodingKey { case fullName = "full_name" } }
    let id: String
    let unread: Bool
    let reason: String
    let subject: Subject
    let repository: Repository
}

/// An issue or pull request returned by the search API.
struct GitHubIssueItem: Codable, Equatable, Identifiable {
    let id: Int
    let number: Int
    let title: String
    let htmlURL: URL
    let repositoryURL: URL
    let updatedAt: Date?

    var repoName: String { repositoryURL.pathComponents.suffix(2).joined(separator: "/") }

    enum CodingKeys: String, CodingKey {
        case id, number, title
        case htmlURL = "html_url", repositoryURL = "repository_url", updatedAt = "updated_at"
    }
}

struct GitHubSearchResponse: Codable { let totalCount: Int; let items: [GitHubIssueItem]
    enum CodingKeys: String, CodingKey { case totalCount = "total_count", items } }

struct GitHubEvent: Codable, Equatable, Identifiable {
    struct Repo: Codable, Equatable { let name: String }
    struct Payload: Codable, Equatable {
        struct Commit: Codable, Equatable { let message: String }
        let commits: [Commit]?
        let action: String?
        let ref: String?
    }
    let id: String
    let type: String
    let repo: Repo
    let createdAt: Date?
    let payload: Payload?

    enum CodingKeys: String, CodingKey { case id, type, repo, payload; case createdAt = "created_at" }

    /// Human readable one-liner for the activity list.
    var summary: String {
        switch type {
        case "PushEvent":
            if let first = payload?.commits?.first?.message.split(separator: "\n").first { return String(first) }
            return "Pushed to \(payload?.ref?.replacingOccurrences(of: "refs/heads/", with: "") ?? "branch")"
        case "PullRequestEvent": return "Pull request \(payload?.action ?? "updated")"
        case "IssuesEvent": return "Issue \(payload?.action ?? "updated")"
        case "IssueCommentEvent": return "Commented on an issue"
        case "PullRequestReviewEvent": return "Reviewed a pull request"
        case "CreateEvent": return "Created \(payload?.ref ?? "repository")"
        case "WatchEvent": return "Starred"
        case "ForkEvent": return "Forked"
        default: return type.replacingOccurrences(of: "Event", with: "")
        }
    }

    var icon: String {
        switch type {
        case "PushEvent": return "arrow.up.circle.fill"
        case "PullRequestEvent", "PullRequestReviewEvent": return "arrow.triangle.pull"
        case "IssuesEvent", "IssueCommentEvent": return "exclamationmark.circle.fill"
        case "WatchEvent": return "star.fill"
        default: return "circle.fill"
        }
    }
}

struct GitHubWorkflowRun: Codable, Equatable, Identifiable {
    let id: Int
    let name: String?
    let status: String
    let conclusion: String?
    let headBranch: String?
    let htmlURL: URL
    var repoName: String = ""

    enum CodingKeys: String, CodingKey {
        case id, name, status, conclusion
        case headBranch = "head_branch", htmlURL = "html_url"
    }

    enum Outcome { case running, success, failure, other }
    var outcome: Outcome {
        if status != "completed" { return .running }
        switch conclusion {
        case "success": return .success
        case "failure", "timed_out", "startup_failure": return .failure
        default: return .other
        }
    }
}

struct GitHubWorkflowRunsResponse: Codable {
    let workflowRuns: [GitHubWorkflowRun]
    enum CodingKeys: String, CodingKey { case workflowRuns = "workflow_runs" }
}

struct GitHubContributionDay: Equatable { let date: String; let count: Int }

struct GitHubContributions: Equatable {
    var total: Int
    var commits: Int
    var pullRequests: Int
    var reviews: Int
    var issues: Int
    var recentDays: [GitHubContributionDay]
}

/// Everything the HUD renders, fetched in one refresh.
struct GitHubSnapshot: Equatable {
    var user: GitHubUser
    var notifications: [GitHubNotification] = []
    var assignedPRs: GitHubSearchResponse?
    var reviewRequests: GitHubSearchResponse?
    var assignedIssues: GitHubSearchResponse?
    var events: [GitHubEvent] = []
    var workflowRuns: [GitHubWorkflowRun] = []
    var contributions: GitHubContributions?
    var fetchedAt: Date = Date()
}

extension GitHubSearchResponse: Equatable {}
