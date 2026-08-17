import AppKit
import Defaults
import Foundation
import SwiftUI

@MainActor
final class CodexNotificationManager: ObservableObject {
    static let shared = CodexNotificationManager()
    private static let maximumEncodedPayloadCharacters = (
        (CodexHookEventParser.maximumPayloadBytes + 2) / 3
    ) * 4
    private static let authenticatedPayloadLifetime: TimeInterval = 120

    @Published private(set) var state = CodexNotificationState()
    @Published private(set) var presentedNotification: CodexJobNotification?
    @Published private(set) var lastError: String?
    @Published private(set) var accessibilityAuthorizationRequired = false
    @Published private(set) var submittingNotificationIDs: Set<String> = []
    @Published private(set) var expandedPermissionNotificationID: String?

    private var presentationTransitionTask: Task<Void, Never>?
    private var passivePresentationTask: Task<Void, Never>?
    private var passiveDismissalTransitionTask: Task<Void, Never>?
    private var passivePresentationToken: CodexNotificationPresentationToken?
    private var passivePresentationSurfaces = CodexNotificationPresentationSurfaces()
    private var nativePermissionObservationTask: Task<Void, Never>?
    private var observedNativePermissionToken: CodexNotificationPresentationToken?
    private var eventIngestionTask: Task<Void, Never>?
    private var acceptedPayloads: [String: Date] = [:]

    var visibleNotification: CodexJobNotification? {
        presentedNotification
    }

    var presentedNotificationToken: CodexNotificationPresentationToken? {
        presentedNotification.map(CodexNotificationPresentationToken.init)
    }

    var expandedPermissionNotification: CodexJobNotification? {
        guard let expandedPermissionNotificationID else { return nil }
        return state.notifications.first(where: {
            $0.id == expandedPermissionNotificationID
                && $0.status == .needsAction(.permission)
        })
    }

    func start() {
        synchronizePresentedNotification()
        synchronizeNativePermissionObservation()
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
        nativePermissionObservationTask?.cancel()
        nativePermissionObservationTask = nil
        observedNativePermissionToken = nil
        eventIngestionTask?.cancel()
        eventIngestionTask = nil
        presentedNotification = nil
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
        guard await XPCHelperClient.shared.isAuthenticCodexNotificationPayload(
            encodedPayload,
            signature: signature
        ), let payload = Self.decodeBase64URL(encodedPayload) else {
            return
        }
        let now = Date()
        acceptedPayloads = acceptedPayloads.filter {
            now.timeIntervalSince($0.value) <= Self.authenticatedPayloadLifetime
        }
        guard acceptedPayloads[encodedPayload] == nil else { return }
        acceptedPayloads[encodedPayload] = now

        do {
            let event = try CodexHookEventParser.parse(payload)
            if case .permissionRequest(_, _, _, _, let control, _, _) = event,
               control != .accessibility {
                return
            }
            var updatedState = state
            updatedState.reduce(event)
            state = updatedState
            lastError = nil
            accessibilityAuthorizationRequired = false
            clearExpandedPermissionIfNeeded()
            synchronizePresentedNotification()
            synchronizeNativePermissionObservation()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func dismissVisibleNotification() {
        guard let visibleNotification else { return }
        dismiss(notification: visibleNotification)
    }

    func presentPermissionDetail(for notification: CodexJobNotification) {
        guard notification.status == .needsAction(.permission),
              state.notifications.contains(where: {
                  $0.id == notification.id
                      && $0.status == .needsAction(.permission)
              }) else {
            return
        }
        lastError = nil
        expandedPermissionNotificationID = notification.id
    }

    func dismissPermissionDetail() {
        expandedPermissionNotificationID = nil
    }

    @discardableResult
    func submitPermissionDecision(
        _ decision: CodexPermissionDecision,
        for notification: CodexJobNotification
    ) async -> Bool {
        guard notification.status == .needsAction(.permission),
              notification.permissionControl == .accessibility,
              state.notifications.contains(where: {
                  $0.id == notification.id
                      && $0.status == .needsAction(.permission)
                      && $0.permissionControl == .accessibility
              }),
              !submittingNotificationIDs.contains(notification.id) else {
            return false
        }

        lastError = nil
        submittingNotificationIDs.insert(notification.id)
        defer { submittingNotificationIDs.remove(notification.id) }

        guard await XPCHelperClient.shared.isAccessibilityAuthorized() else {
            accessibilityAuthorizationRequired = true
            lastError = "Accessibility access is required to answer the Codex prompt from Boring Notch."
            return false
        }
        accessibilityAuthorizationRequired = false

        let nativeDecision = await XPCHelperClient.shared
            .performCodexPermissionDecision(
                decision,
                matchingChatTitle: notification.chatTitle,
                request: permissionMatchRequest(for: notification)
        )
        if case .failure(let error) = nativeDecision {
            accessibilityAuthorizationRequired = !(
                await XPCHelperClient.shared.isAccessibilityAuthorized()
            )
            lastError = error.localizedDescription
            return false
        }
        guard state.notifications.contains(where: {
            $0.id == notification.id
                && $0.status == .needsAction(.permission)
                && $0.permissionControl == .accessibility
        }) else {
            return false
        }
        var updatedState = state
        updatedState.dismiss(notification.id)
        state = updatedState
        lastError = nil
        accessibilityAuthorizationRequired = false
        clearExpandedPermissionIfNeeded()
        synchronizePresentedNotification()
        synchronizeNativePermissionObservation()
        return true
    }

    func openCodex(for notification: CodexJobNotification? = nil) {
        let bundleIdentifier = "com.openai.codex"

        if let notification,
           let threadURL = codexThreadURL(for: notification),
           NSWorkspace.shared.open(threadURL) {
            return
        }

        if let application = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first {
            application.activate(options: [.activateAllWindows])
        } else if let applicationURL = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: bundleIdentifier) {
            NSWorkspace.shared.openApplication(
                at: applicationURL,
                configuration: NSWorkspace.OpenConfiguration()
            )
        }
    }

    func openCodexAndDismiss() {
        openCodex()
        dismissVisibleNotification()
    }

    func openCodexAndDismiss(_ notification: CodexJobNotification) {
        openCodex(for: notification)
        dismiss(notification: notification)
    }

    private func codexThreadURL(for notification: CodexJobNotification) -> URL? {
        guard !notification.sessionID.isEmpty else { return nil }
        let allowedCharacters = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-_")
        )
        guard let encodedSessionID = notification.sessionID.addingPercentEncoding(
            withAllowedCharacters: allowedCharacters
        ) else {
            return nil
        }
        return URL(string: "codex://threads/\(encodedSessionID)")
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
        passivePresentationTask?.cancel()
        passivePresentationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard let self,
                  self.presentedNotificationToken == token,
                  self.passivePresentationToken == token,
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
              presentedNotificationToken == token else {
            return
        }

        let transitionDuration = CodexNotificationTiming.transitionDuration(
            animationSpeedMultiplier: Defaults[.animationSpeedMultiplier],
            animationsEnabled: Defaults[.enableOpeningAnimation]
        )
        withAnimation(StandardAnimations.open) {
            presentedNotification = nil
        }

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
            var updatedState = self.state
            updatedState.dismiss(token.id)
            self.state = updatedState
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

    private func dismiss(notification: CodexJobNotification) {
        var updatedState = state
        updatedState.dismiss(notification.id)
        state = updatedState
        clearExpandedPermissionIfNeeded()
        synchronizePresentedNotification()
        synchronizeNativePermissionObservation()
    }

    private func synchronizePresentedNotification() {
        let nextNotification = state.visibleNotification()
        let nextToken = nextNotification.map(CodexNotificationPresentationToken.init)
        guard nextToken != presentedNotificationToken else { return }

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

            guard nextToken == self.state.visibleNotification().map(CodexNotificationPresentationToken.init) else {
                self.synchronizePresentedNotification()
                self.synchronizeNativePermissionObservation()
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

    private func clearExpandedPermissionIfNeeded() {
        guard expandedPermissionNotificationID != nil,
              expandedPermissionNotification == nil else {
            return
        }
        expandedPermissionNotificationID = nil
    }

    private func synchronizeNativePermissionObservation() {
        let permission = state.nativePermissionNotification()
        let token = permission.map(CodexNotificationPresentationToken.init)
        guard token != observedNativePermissionToken else { return }

        nativePermissionObservationTask?.cancel()
        nativePermissionObservationTask = nil
        observedNativePermissionToken = token
        guard let permission else { return }
        let request = permissionMatchRequest(for: permission)

        nativePermissionObservationTask = Task { [weak self] in
            var hasObservedNativePrompt = false
            let appearanceDeadline = Date().addingTimeInterval(
                CodexNotificationTiming.nativePermissionAppearanceTimeout
            )

            while !Task.isCancelled {
                let status = await XPCHelperClient.shared.codexPermissionPromptStatus(
                    matchingChatTitle: permission.chatTitle,
                    request: request
                )
                guard !Task.isCancelled, let self else { return }

                guard self.state.notifications.contains(where: {
                    $0.id == permission.id && $0.createdAt == permission.createdAt
                }) else {
                    return
                }

                if !status.inspected {
                    guard Date() < appearanceDeadline else {
                        self.dismiss(notification: permission)
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(250))
                    continue
                }

                if status.visible {
                    if !hasObservedNativePrompt,
                       !permission.nativePermissionConfirmed {
                        var updatedState = self.state
                        updatedState.confirmNativePermission(permission.id)
                        self.state = updatedState
                        self.synchronizePresentedNotification()
                    }
                    hasObservedNativePrompt = true
                } else if hasObservedNativePrompt || Date() >= appearanceDeadline {
                    self.dismiss(notification: permission)
                    return
                }

                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func permissionMatchRequest(
        for notification: CodexJobNotification
    ) -> String {
        var candidates = notification.permissionDetails?.accessibilityMatchCandidates ?? []
        if candidates.isEmpty {
            candidates.append(notification.resultSummary)
        }
        return candidates.joined(separator: "\u{001F}")
    }
}

struct CodexNotificationPresentationToken: Equatable {
    let id: String
    let createdAt: Date

    init(_ notification: CodexJobNotification) {
        id = notification.id
        createdAt = notification.createdAt
    }
}
