import AppKit
import CryptoKit
import Defaults
import Foundation
import OSLog
import SwiftUI

@MainActor
final class CodexNotificationManager: ObservableObject {
    static let shared = CodexNotificationManager()
    private static let logger = Logger(
        subsystem: "theboringteam.boringnotch",
        category: "CodexNotifications"
    )
    private static let maximumEncodedPayloadCharacters = (
        (CodexHookEventParser.maximumPayloadBytes + 2) / 3
    ) * 4
    private static let authenticatedPayloadLifetime: TimeInterval = 120

    @Published private(set) var state = CodexNotificationState()
    @Published private(set) var presentedNotification: CodexJobNotification?
    @Published private(set) var lastError: String?
    @Published private(set) var submittingNotificationIDs: Set<String> = []
    @Published private var detailPresentation = CodexNotificationDetailPresentation()
    @Published private(set) var replyState = CodexReplyState()
    private var replyNotification: CodexJobNotification?
    private var replyTasks: [UUID: Task<Void, Never>] = [:]

    var expandedNotificationToken: CodexNotificationPresentationToken? { detailPresentation.token }
    var expandedDetailSurfaceIDs: Set<String> { detailPresentation.surfaceIDs }

    private var presentationTransitionTask: Task<Void, Never>?
    private var passivePresentationTask: Task<Void, Never>?
    private var passiveDismissalTransitionTask: Task<Void, Never>?
    private var passivePresentationToken: CodexNotificationPresentationToken?
    private var passivePresentationSurfaces = CodexNotificationPresentationSurfaces()
    private var passivePresentationPolicy = CodexPassivePresentationPolicy()
    private var permissionExpirationTask: Task<Void, Never>?
    private var eventIngestionTask: Task<Void, Never>?
    private var replayGuard = CodexNotificationReplayGuard(
        lifetime: CodexNotificationManager.authenticatedPayloadLifetime
    )
    private let applicationLauncher = CodexApplicationLauncher(
        workspace: NSWorkspaceCodexApplicationWorkspace()
    )

    var visibleNotification: CodexJobNotification? {
        presentedNotification
    }

    var presentedNotificationToken: CodexNotificationPresentationToken? {
        presentedNotification.map(CodexNotificationPresentationToken.init)
    }

    var expandedNotification: CodexJobNotification? {
        guard let expandedNotificationToken else { return nil }
        if let replyNotification, expandedNotificationToken.matches(replyNotification) {
            return replyNotification
        }
        return state.notifications.first(where: {
            expandedNotificationToken.matches($0)
        })
    }

    func start() {
        schedulePermissionExpiration()
        synchronizePresentedNotification()
    }

    func stop() {
        presentationTransitionTask?.cancel()
        presentationTransitionTask = nil
        passivePresentationTask?.cancel()
        passivePresentationTask = nil
        passiveDismissalTransitionTask?.cancel()
        passiveDismissalTransitionTask = nil
        passivePresentationToken = nil
        passivePresentationSurfaces.reset()
        passivePresentationPolicy.reset()
        permissionExpirationTask?.cancel()
        permissionExpirationTask = nil
        eventIngestionTask?.cancel()
        eventIngestionTask = nil
        replyTasks.values.forEach { $0.cancel() }
        replyTasks.removeAll()
        replyState.reset()
        replyNotification = nil
        presentedNotification = nil
        detailPresentation.reset()
    }

    @discardableResult
    func handle(url: URL) -> Bool {
        guard url.scheme == "boringnotch",
              url.host == "codex-event",
              let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let encodedPayload = queryItems.first(where: { $0.name == "payload" })?.value,
              let signature = queryItems.first(where: { $0.name == "signature" })?.value,
              !encodedPayload.isEmpty,
              signature.count == 43,
              encodedPayload.count <= Self.maximumEncodedPayloadCharacters else {
            Self.logger.error("Rejected a malformed Codex notification URL")
            return false
        }

        let previousTask = eventIngestionTask
        eventIngestionTask = Task { [weak self] in
            _ = await previousTask?.result
            guard !Task.isCancelled, let self else { return }
            await self.ingest(encodedPayload: encodedPayload, signature: signature)
        }
        return true
    }

    private func ingest(encodedPayload: String, signature: String) async {
        let isAuthentic = await XPCHelperClient.shared.isAuthenticCodexNotificationPayload(
            encodedPayload,
            signature: signature
        )
        guard isAuthentic else {
            Self.logger.error("Rejected a Codex notification with invalid authentication")
            return
        }
        guard let payload = Self.decodeBase64URL(encodedPayload) else {
            Self.logger.error("Rejected a Codex notification with invalid payload encoding")
            return
        }
        // Retain only a digest for replay suppression, never the response body.
        let payloadDigest = SHA256.hash(data: Data(encodedPayload.utf8)).description
        guard replayGuard.accept(payloadDigest) else {
            Self.logger.error("Rejected a replayed Codex notification")
            return
        }

        do {
            let event = try CodexHookEventParser.parse(payload)
            if case .permissionRequest(let sessionID, let turnID, _, _, let details, let callback, _, _) = event {
                guard let callback, !details.isAutoReviewed else { return }
                do {
                    if state.hasEndedTurn(sessionID: sessionID, turnID: turnID) {
                        try await CodexPermissionRelay.submit(.reviewInCodex, callback: callback)
                        return
                    }
                    try await CodexPermissionRelay.acknowledge(callback: callback)
                    // Ingestion can resume after an Interrupt/Stop was received during the await.
                    if state.hasEndedTurn(sessionID: sessionID, turnID: turnID) {
                        try await CodexPermissionRelay.submit(.reviewInCodex, callback: callback)
                        return
                    }
                } catch {
                    Self.logger.error(
                        "Could not acknowledge a Codex permission notification: \(error.localizedDescription, privacy: .public)"
                    )
                    return
                }
            }
            var updatedState = state
            updatedState.reduce(event)
            state = updatedState
            releaseAcceptedReplyIfResponseArrived()
            lastError = nil
            clearExpandedDetailIfNeeded()
            schedulePermissionExpiration()
            synchronizePresentedNotification()
            Self.logger.notice("Accepted a Codex notification for presentation")
        } catch {
            lastError = error.localizedDescription
            Self.logger.error("Failed to parse a Codex notification: \(error.localizedDescription, privacy: .public)")
        }
    }

    func dismissVisibleNotification() {
        guard let visibleNotification else { return }
        dismiss(notification: visibleNotification)
    }

    func presentDetail(for notification: CodexJobNotification, surfaceID: String) {
        let token = CodexNotificationPresentationToken(notification)
        guard notification.status == .permissionRequired || notification.responsePreview != nil,
              presentedNotificationToken == token,
              containsPresentation(token) else {
            return
        }
        lastError = nil
        detailPresentation.present(token, surfaceID: surfaceID)
        passivePresentationTask?.cancel()
        passivePresentationTask = nil
    }

    func dismissDetail(for token: CodexNotificationPresentationToken, surfaceID: String) {
        guard detailPresentation.dismiss(token, surfaceID: surfaceID) else { return }
        if let token = passivePresentationToken {
            if passivePresentationPolicy.compactLaunchError(for: token) != nil {
                passivePresentationPolicy.discardCompactLaunch(for: token)
            }
            schedulePassiveDismissal(for: token, after: CodexNotificationTiming.passiveDwellDuration)
        }
    }

    @discardableResult
    func submitPermissionDecision(
        _ decision: CodexPermissionDecision,
        for notification: CodexJobNotification
    ) async -> Bool {
        guard notification.status == .permissionRequired,
              let callback = notification.permissionCallback,
              state.notifications.contains(where: {
                  $0.id == notification.id
                      && $0.status == .permissionRequired
                      && $0.permissionCallback == callback
              }),
              !submittingNotificationIDs.contains(notification.id) else {
            return false
        }

        lastError = nil
        submittingNotificationIDs.insert(notification.id)
        defer { submittingNotificationIDs.remove(notification.id) }

        do {
            if decision == .reviewInCodex {
                let threadURL = CodexApplicationRoute.threadURL(
                    sessionID: notification.sessionID
                )
                try await CodexPermissionReviewHandoff.perform(
                    openCodex: {
                        try await self.applicationLauncher.open(threadURL)
                    },
                    handOffPermission: {
                        try await CodexPermissionRelay.submit(decision, callback: callback)
                    }
                )
            } else {
                try await CodexPermissionRelay.submit(decision, callback: callback)
            }
        } catch {
            lastError = error.localizedDescription
            return false
        }
        guard state.notifications.contains(where: {
            $0.id == notification.id
                && $0.status == .permissionRequired
                && $0.permissionCallback == callback
        }) else {
            return false
        }
        var updatedState = state
        updatedState.dismiss(notification.id)
        state = updatedState
        lastError = nil
        clearExpandedDetailIfNeeded()
        schedulePermissionExpiration()
        synchronizePresentedNotification()
        return true
    }

    @discardableResult
    func openCodex(for notification: CodexJobNotification? = nil) async -> Bool {
        await openCodex(
            at: notification.flatMap {
                CodexApplicationRoute.threadURL(sessionID: $0.sessionID)
            }
        )
    }

    @discardableResult
    func openCodex(at url: URL?) async -> Bool {
        do {
            try await applicationLauncher.open(url)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func selectCompactActivity(for notification: CodexJobNotification) {
        let token = CodexNotificationPresentationToken(notification)
        guard !notification.status.isPersistent,
              presentedNotificationToken == token,
              passivePresentationToken == token,
              containsPresentation(token),
              passivePresentationPolicy.beginCompactLaunch(for: token) else {
            return
        }

        lastError = nil
        passivePresentationTask?.cancel()
        passivePresentationTask = nil

        Task { [weak self] in
            guard let self, self.presentedNotificationToken == token,
                  self.containsPresentation(token) else { return }
            let didOpen = await self.openCodex(for: notification)
            guard self.passivePresentationPolicy.preventsAutomaticDismissal(
                of: token
            ) else {
                return
            }

            guard self.containsPresentation(token) else {
                self.passivePresentationPolicy.discardCompactLaunch(for: token)
                return
            }

            if didOpen {
                self.expireReply(for: token)
                self.passivePresentationPolicy.recordCompactLaunchSuccess(for: token)
                var updatedState = self.state
                updatedState.dismiss(token)
                self.state = updatedState
                self.synchronizePresentedNotification()
            } else {
                self.passivePresentationPolicy.recordCompactLaunchFailure(
                    self.lastError ?? "The official Codex app could not be opened.",
                    for: token
                )
                if self.passivePresentationPolicy.shouldCancelPassiveDismissalTask(
                    for: token,
                    activePresentationToken: self.passivePresentationToken
                ) {
                    self.passivePresentationTask?.cancel()
                    self.passivePresentationTask = nil
                }
            }
        }
    }

    func compactLaunchError(for notification: CodexJobNotification) -> String? {
        passivePresentationPolicy.compactLaunchError(
            for: CodexNotificationPresentationToken(notification)
        )
    }

    func editReply(_ text: String, for notification: CodexJobNotification) {
        replyState.edit(text, for: notification)
        if replyState.drafts[notification.sessionID]?.retainsNotification == true {
            replyNotification = notification
            passivePresentationTask?.cancel()
            passivePresentationTask = nil
        } else if replyNotification?.sessionID == notification.sessionID {
            replyNotification = nil
        }
        synchronizePresentedNotification()
    }

    func discardReply(for notification: CodexJobNotification) {
        replyState.discard(sessionID: notification.sessionID)
        guard replyState.drafts[notification.sessionID] == nil else { return }
        if replyNotification?.sessionID == notification.sessionID { replyNotification = nil }
        synchronizePresentedNotification()
    }

    func replyMessage(for notification: CodexJobNotification) -> String? {
        switch replyState.drafts[notification.sessionID]?.delivery {
        case .sending: "Sending…"
        case .failed: "Reply could not be sent. Your draft is saved. Open in Codex or retry."
        case .uncertain: "Delivery could not be confirmed. Check this chat in Codex before sending again."
        default: nil
        }
    }

    func sendReply(for notification: CodexJobNotification) {
        guard let request = replyState.begin(sessionID: notification.sessionID) else { return }
        replyNotification = notification
        passivePresentationTask?.cancel()
        passivePresentationTask = nil
        replyTasks[request.id] = Task { [weak self] in
            let outcome = await XPCHelperClient.shared.sendCodexReply(
                sessionID: request.sessionID, turnID: request.turnID, message: request.text
            )
            guard let self else { return }
            defer { self.replyTasks[request.id] = nil }
            guard !Task.isCancelled else { return }
            let delivery: CodexReplyState.Delivery
            switch outcome {
            case .queued: delivery = .queued
            case .queuedNeedsOpen: delivery = .queuedNeedsOpen
            case .failed, .unavailable: delivery = .failed
            case .uncertain: delivery = .uncertain
            }
            guard self.replyState.finish(request, with: delivery) else { return }
            self.releaseAcceptedReplyIfResponseArrived()
            self.synchronizePresentedNotification()
        }
    }

    private func containsPresentation(_ token: CodexNotificationPresentationToken) -> Bool {
        state.notifications.contains(where: token.matches)
            || replyNotification.map(token.matches) == true
    }

    private func releaseAcceptedReplyIfResponseArrived() {
        guard let notification = replyNotification,
              let draft = replyState.drafts[notification.sessionID],
              draft.delivery == .queued || draft.delivery == .queuedNeedsOpen,
              state.notifications.contains(where: {
                  $0.sessionID == draft.sessionID && $0.responsePreview != nil
                      && $0.turnID != draft.turnID && $0.createdAt > draft.origin.createdAt
              }) else { return }
        replyState.discard(sessionID: draft.sessionID)
        state.dismiss(CodexNotificationPresentationToken(notification))
        replyNotification = nil
    }

    func setPassivePresentationHovered(
        _ isHovered: Bool,
        for notification: CodexJobNotification,
        surfaceID: String
    ) {
        let token = CodexNotificationPresentationToken(notification)
        guard passivePresentationToken == token,
              presentedNotificationToken == token else {
            return
        }

        passivePresentationSurfaces.setHovered(isHovered, surfaceID: surfaceID)
        if passivePresentationSurfaces.isPassiveDismissalPaused {
            passivePresentationTask?.cancel()
            passivePresentationTask = nil
            return
        }

        schedulePassiveDismissal(
            for: token,
            after: CodexNotificationTiming.passiveDwellDuration
        )
    }

    func endPassivePresentation(
        for notification: CodexJobNotification,
        surfaceID: String
    ) {
        let token = CodexNotificationPresentationToken(notification)
        guard passivePresentationToken == token,
              presentedNotificationToken == token else {
            return
        }

        passivePresentationSurfaces.end(surfaceID: surfaceID)
        guard !passivePresentationSurfaces.isPassiveDismissalPaused else {
            passivePresentationTask?.cancel()
            passivePresentationTask = nil
            return
        }

        schedulePassiveDismissal(
            for: token,
            after: CodexNotificationTiming.passiveDwellDuration
        )
    }

    func beginPassivePresentation(
        for notification: CodexJobNotification,
        surfaceID: String
    ) {
        let token = CodexNotificationPresentationToken(notification)
        guard !notification.status.isPersistent,
              presentedNotificationToken == token else {
            return
        }

        startPassivePresentationTimer(for: notification)
        passivePresentationSurfaces.begin(surfaceID: surfaceID)
    }

    private func startPassivePresentationTimer(for notification: CodexJobNotification) {
        let token = CodexNotificationPresentationToken(notification)
        guard !notification.status.isPersistent,
              presentedNotificationToken == token else {
            return
        }

        if passivePresentationToken != token {
            passivePresentationTask?.cancel()
            passivePresentationTask = nil
            passivePresentationToken = token
            passivePresentationSurfaces.reset()
        }

        guard !passivePresentationSurfaces.isPassiveDismissalPaused,
              passivePresentationTask == nil else {
            return
        }

        let transitionDuration = CodexNotificationTiming.transitionDuration(
            animationSpeedMultiplier: Defaults[.animationSpeedMultiplier],
            animationsEnabled: Defaults[.enableOpeningAnimation]
        )
        schedulePassiveDismissal(
            for: token,
            after: transitionDuration + CodexNotificationTiming.passiveDwellDuration
        )
    }

    private func schedulePassiveDismissal(
        for token: CodexNotificationPresentationToken,
        after delay: TimeInterval
    ) {
        guard expandedNotificationToken != token,
              !passivePresentationPolicy.preventsAutomaticDismissal(of: token) else {
            passivePresentationTask?.cancel()
            passivePresentationTask = nil
            return
        }

        passivePresentationTask?.cancel()
        passivePresentationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard let self,
                  !Task.isCancelled,
                  self.presentedNotificationToken == token,
                  self.passivePresentationToken == token,
                  self.expandedNotificationToken != token,
                  !self.passivePresentationSurfaces.isPassiveDismissalPaused else {
                return
            }
            self.dismissPassivePresentation(for: token)
        }
    }

    private func dismissPassivePresentation(
        for token: CodexNotificationPresentationToken
    ) {
        guard passivePresentationToken == token,
              presentedNotificationToken == token,
              expandedNotificationToken != token,
              !passivePresentationPolicy.preventsAutomaticDismissal(
                  of: token
              ) else {
            return
        }

        let transitionDuration = CodexNotificationTiming.transitionDuration(
            animationSpeedMultiplier: Defaults[.animationSpeedMultiplier],
            animationsEnabled: Defaults[.enableOpeningAnimation]
        )
        expireReply(for: token)
        withAnimation(StandardAnimations.open) {
            presentedNotification = nil
        }

        var updatedState = state
        passivePresentationPolicy.consumeBeforeFade(token, from: &updatedState)
        state = updatedState

        passivePresentationTask = nil
        passiveDismissalTransitionTask?.cancel()
        passiveDismissalTransitionTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(transitionDuration))
            } catch {
                return
            }
            guard let self, self.passivePresentationToken == token else { return }

            self.passiveDismissalTransitionTask = nil
            self.passivePresentationToken = nil
            self.passivePresentationSurfaces.reset()
            self.synchronizePresentedNotification()
        }
    }

    private static func decodeBase64URL(_ encoded: String) -> Data? {
        var base64 = encoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: base64)
    }

    private func expireReply(for token: CodexNotificationPresentationToken) {
        replyState.expire(token)
        if replyNotification.map(token.matches) == true { replyNotification = nil }
    }

    private func dismiss(notification: CodexJobNotification) {
        expireReply(for: CodexNotificationPresentationToken(notification))
        passivePresentationPolicy.discardCompactLaunch(
            for: CodexNotificationPresentationToken(notification)
        )
        var updatedState = state
        updatedState.dismiss(notification.id)
        state = updatedState
        clearExpandedDetailIfNeeded()
        schedulePermissionExpiration()
        synchronizePresentedNotification()
    }

    private func synchronizePresentedNotification() {
        let nextNotification = replyState.visibleNotification(in: state, retaining: replyNotification)
        let nextToken = nextNotification.map(CodexNotificationPresentationToken.init)
        guard nextToken != presentedNotificationToken else { return }
        detailPresentation.retainOnly(nextToken)

        presentationTransitionTask?.cancel()
        passivePresentationTask?.cancel()
        passivePresentationTask = nil
        passiveDismissalTransitionTask?.cancel()
        passiveDismissalTransitionTask = nil
        passivePresentationToken = nil
        passivePresentationSurfaces.reset()

        let transitionDuration = CodexNotificationTiming.transitionDuration(
            animationSpeedMultiplier: Defaults[.animationSpeedMultiplier],
            animationsEnabled: Defaults[.enableOpeningAnimation]
        )
        presentationTransitionTask = Task { [weak self] in
            guard let self else { return }

            if self.presentedNotification != nil {
                withAnimation(StandardAnimations.open) {
                    self.presentedNotification = nil
                }
                do {
                    try await Task.sleep(for: .seconds(transitionDuration))
                } catch {
                    return
                }
            } else {
                await Task.yield()
                guard !Task.isCancelled else { return }
            }

            let current = self.replyState.visibleNotification(in: self.state, retaining: self.replyNotification)
            guard nextToken == current.map(CodexNotificationPresentationToken.init) else {
                self.synchronizePresentedNotification()
                return
            }

            withAnimation(StandardAnimations.open) {
                self.presentedNotification = nextNotification
            }
            if let nextNotification {
                self.startPassivePresentationTimer(for: nextNotification)
            }
            self.presentationTransitionTask = nil
        }
    }

    private func clearExpandedDetailIfNeeded() {
        guard expandedNotificationToken != nil,
              expandedNotification == nil else {
            return
        }
        detailPresentation.reset()
    }

    private func schedulePermissionExpiration() {
        permissionExpirationTask?.cancel()
        permissionExpirationTask = nil

        var updatedState = state
        updatedState.removeExpiredPermissionRequests()
        if updatedState != state {
            state = updatedState
            clearExpandedDetailIfNeeded()
            synchronizePresentedNotification()
        }

        let expirations: [Date] = state.notifications.compactMap { notification -> Date? in
            guard notification.status == .permissionRequired else {
                return nil
            }
            return notification.permissionCallback?.expiresAt
        }
        guard let expiration = expirations.min() else {
            return
        }

        permissionExpirationTask = Task { [weak self] in
            do {
                try await Task.sleep(
                    for: .seconds(max(0, expiration.timeIntervalSinceNow))
                )
            } catch {
                return
            }
            guard let self else { return }
            self.permissionExpirationTask = nil
            var updatedState = self.state
            updatedState.removeExpiredPermissionRequests()
            self.state = updatedState
            self.clearExpandedDetailIfNeeded()
            self.synchronizePresentedNotification()
            self.schedulePermissionExpiration()
        }
    }
}

@MainActor
private final class NSWorkspaceCodexApplicationWorkspace: CodexApplicationWorkspace {
    private let workspace = NSWorkspace.shared

    func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL? {
        workspace.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    func open(_ url: URL?, withApplicationAt applicationURL: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            let completion: @Sendable (NSRunningApplication?, Error?) -> Void = { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }

            if let url {
                workspace.open(
                    [url],
                    withApplicationAt: applicationURL,
                    configuration: configuration,
                    completionHandler: completion
                )
            } else {
                workspace.openApplication(
                    at: applicationURL,
                    configuration: configuration,
                    completionHandler: completion
                )
            }
        }
    }
}
