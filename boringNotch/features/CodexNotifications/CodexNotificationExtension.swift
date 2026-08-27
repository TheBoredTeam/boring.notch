import Combine
import SwiftUI

@MainActor
enum CodexNotificationExtension {
    static let activityID = "codex.notification"

    static let descriptor = NotchExtensionDescriptor(
        id: "codex.notifications",
        updates: CodexNotificationManager.shared.objectWillChange
            .map { _ in () }
            .eraseToAnyPublisher(),
        start: { CodexNotificationManager.shared.start() },
        stop: { CodexNotificationManager.shared.stop() },
        closedActivities: { context in
            guard let notification = CodexNotificationManager.shared.presentedNotification else {
                return []
            }

            let height = max(32, context.displayHeight)
            let notchWidth = context.closedNotchWidth + 10
            let promptWidth: CGFloat = 236
            let isPermissionRequest = notification.status == .needsAction(.permission)
            let tapRouting = CodexClosedActivityTapRouting(status: notification.status)
            let metrics = ClosedNotchLayoutMetrics(
                exclusionWidth: notchWidth,
                leadingWidth: 0,
                trailingWidth: promptWidth,
                leadingExclusionMargin: 0,
                trailingExclusionMargin: 0,
                horizontalChromeInset: cornerRadiusInsets.closed.bottom,
                height: height
            )
            return [ClosedNotchExtensionActivity(
                id: activityID,
                priority: notification.status.notchPriority,
                updatedAt: notification.createdAt,
                metrics: metrics,
                content: AnyView(CodexClosedNotchPrompt(
                    notification: notification,
                    presentationSurfaceID: context.surfaceID,
                    metrics: metrics
                )),
                opensNotchOnHover: isPermissionRequest,
                opensNotchOnTap: tapRouting == .expandNotch,
                onSelect: tapRouting == .openCodex ? {
                    CodexNotificationManager.shared.selectCompactActivity(
                        for: notification
                    )
                } : nil
            )]
        }
    )
}

private extension CodexJobStatus {
    var notchIconAssetName: String? {
        if case .needsAction(.permission) = self {
            return "codexPermissionShield"
        }
        return nil
    }

    var notchPriority: ClosedNotchPresentationPriority {
        switch self {
        case .needsAction(.permission), .needsAction(.decision), .failed:
            .critical
        case .needsAction(.manualCheck):
            .system
        case .succeeded:
            .activity
        }
    }

    var tint: Color {
        switch self {
        case .needsAction(.permission): .orange
        case .needsAction(.decision): .purple
        case .needsAction(.manualCheck): .blue
        case .failed: .red
        case .succeeded: .green
        }
    }

    var pulses: Bool {
        if case .needsAction = self { return true }
        return false
    }
}

private struct CodexNotificationStatusIcon: View {
    let status: CodexJobStatus

    @State private var pulsing = false

    @ViewBuilder
    private var iconView: some View {
        if let assetName = status.notchIconAssetName {
            Image(assetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .foregroundStyle(status.tint)
        } else {
            Image(systemName: status.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(status.tint)
        }
    }

    var body: some View {
        ZStack {
            if status.pulses {
                Circle()
                    .fill(status.tint.opacity(0.28))
                    .frame(width: 27, height: 27)
                    .scaleEffect(pulsing ? 1.15 : 0.82)
                    .opacity(pulsing ? 0.15 : 0.8)
                    .accessibilityHidden(true)
            }
            iconView
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .onAppear {
            guard status.pulses else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }
}

private struct CodexClosedNotchPrompt: View {
    let notification: CodexJobNotification
    let presentationSurfaceID: String
    let metrics: ClosedNotchLayoutMetrics

    @ObservedObject private var manager = CodexNotificationManager.shared

    private var isPermissionRequest: Bool {
        notification.status == .needsAction(.permission)
    }

    private var launchError: String? {
        manager.compactLaunchError(for: notification)
    }

    private var accessibility: CodexClosedActivityAccessibility {
        CodexClosedActivityAccessibility(
            status: notification.status,
            projectName: notification.projectName,
            launchError: launchError
        )
    }

    var body: some View {
        promptContainer
            .id("\(notification.id):\(notification.createdAt.timeIntervalSinceReferenceDate)")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(notification.jobTitle)
            .accessibilityValue(accessibility.value)
            .accessibilityHint(accessibility.hint)
            .onAppear {
                CodexNotificationManager.shared.beginPassivePresentation(
                    for: notification,
                    surfaceID: presentationSurfaceID
                )
            }
            .onDisappear {
                CodexNotificationManager.shared.endPassivePresentation(
                    for: notification,
                    surfaceID: presentationSurfaceID
                )
            }
    }

    private var promptContainer: some View {
        VStack(alignment: .center, spacing: 0) {
            Color.clear
                .frame(width: metrics.exclusionWidth, height: metrics.height)
                .accessibilityHidden(true)

            prompt
                .frame(
                    width: metrics.trailingWidth,
                    height: metrics.height,
                    alignment: .leading
                )
                .contentShape(Rectangle())
                .onHover { isHovered in
                    CodexNotificationManager.shared.setPassivePresentationHovered(
                        isHovered,
                        for: notification,
                        surfaceID: presentationSurfaceID
                    )
                }
        }
    }

    private var prompt: some View {
        HStack(spacing: 10) {
            CodexNotificationStatusIcon(status: notification.status)
                .frame(width: 20, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(notification.chatTitle)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)

                Text(summary)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(notification.status.tint.opacity(0.95))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        }
        .padding(.leading, 10)
        .padding(.trailing, 7)
        .padding(.bottom, 7)
    }

    private var summary: String {
        if let launchError {
            return "\(launchError) · Click to retry"
        }
        return "\(notification.status.title) · \(notification.projectName)"
    }
}

struct CodexPermissionApprovalView: View {
    private static let disclosureCharacterLimit = 140
    private static let viewportHeight = max(0, openNotchSize.height - 12)

    let notification: CodexJobNotification

    @ObservedObject private var manager = CodexNotificationManager.shared
    @State private var isPromptExpanded = false
    @State private var isCommandExpanded = false

    private var isSubmitting: Bool {
        manager.submittingNotificationIDs.contains(notification.id)
    }

    private var details: CodexPermissionDetails {
        notification.permissionDetails
            ?? CodexPermissionDetails(toolName: "Codex")
    }

    private var normalizedToolName: String {
        details.toolName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var toolDisplayName: String {
        switch normalizedToolName {
        case "bash": "Terminal"
        case "apply_patch": "File changes"
        default: details.toolName
        }
    }

    private var requestDescription: String {
        details.description
            ?? "Codex is requesting permission to use \(toolDisplayName)."
    }

    private var canRespondInNotch: Bool {
        notification.permissionCallback?.isActive() == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            permissionHeader

            permissionDetails
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if let error = manager.lastError {
                Text(error)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            permissionActions
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: Self.viewportHeight, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Codex permission request")
    }

    private var permissionHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: toolIcon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(toolDisplayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

        }
    }

    private var permissionDetails: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 6) {
                expandablePrompt

                Text(requestDescription)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.94))
                    .fixedSize(horizontal: false, vertical: true)

                if details.command != nil || details.additionalInput != nil {
                    VStack(alignment: .leading, spacing: 5) {
                        if let command = details.command {
                            expandableDetailSection(
                                title: commandDetailTitle,
                                value: command
                            )
                        }
                        if let additionalInput = details.additionalInput {
                            detailSection(title: "Request input", value: additionalInput)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Permission request details")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var permissionActions: some View {
        HStack(spacing: 8) {
            if canRespondInNotch {
                Button("Deny") {
                    submit(.deny)
                }
                .buttonStyle(CodexPermissionButtonStyle(tint: .white.opacity(0.16)))
                .disabled(isSubmitting)
                .accessibilityLabel("Deny Codex permission")

                Button("Allow") {
                    submit(.allow)
                }
                .buttonStyle(CodexPermissionButtonStyle(tint: .green.opacity(0.9)))
                .disabled(isSubmitting)
                .accessibilityLabel("Allow Codex permission")
            }

            Spacer()

            if isSubmitting {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Sending decision to Codex")
            }

            Button("Review in Codex") {
                reviewInCodex()
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.blue)
            .buttonStyle(.plain)
            .disabled(isSubmitting)
            .accessibilityLabel("Review this permission in Codex")
        }
    }

    private func reviewInCodex() {
        if canRespondInNotch {
            submit(.reviewInCodex)
        } else {
            Task {
                await manager.openCodex(for: notification)
            }
        }
    }

    private func submit(_ decision: CodexPermissionDecision) {
        Task {
            await manager.submitPermissionDecision(decision, for: notification)
        }
    }

    private var toolIcon: String {
        switch normalizedToolName {
        case "bash": "terminal"
        case "browser": "globe"
        case "apply_patch": "doc.badge.plus"
        default: "lock.shield"
        }
    }

    private var commandDetailTitle: String {
        switch normalizedToolName {
        case "bash": "Command"
        case "apply_patch": "Files"
        default: "Tool input"
        }
    }

    private var expandablePrompt: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(notification.userPrompt)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(promptNeedsDisclosure && !isPromptExpanded ? 2 : nil)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)

            if promptNeedsDisclosure {
                Button(isPromptExpanded ? "Show less" : "Show more") {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isPromptExpanded.toggle()
                    }
                }
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.accentColor)
                .buttonStyle(.plain)
                .accessibilityLabel(isPromptExpanded ? "Show less user prompt" : "Show full user prompt")
            }
        }
    }

    private var promptNeedsDisclosure: Bool {
        notification.userPrompt.count > Self.disclosureCharacterLimit
    }

    private func expandableDetailSection(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(commandNeedsDisclosure(value) && !isCommandExpanded ? 2 : nil)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if commandNeedsDisclosure(value) {
                Button(isCommandExpanded ? "Show less" : "Show more") {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isCommandExpanded.toggle()
                    }
                }
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.accentColor)
                .buttonStyle(.plain)
                .accessibilityLabel(isCommandExpanded ? "Show less command" : "Show full command")
            }
        }
    }

    private func commandNeedsDisclosure(_ command: String) -> Bool {
        command.count > Self.disclosureCharacterLimit
    }

    private func detailSection(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}

private struct CodexPermissionButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background(
                Capsule()
                    .fill(tint.opacity(configuration.isPressed ? 0.72 : 1))
            )
            .contentShape(Capsule())
    }
}
