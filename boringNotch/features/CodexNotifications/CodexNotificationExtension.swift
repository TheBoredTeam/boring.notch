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

            return [ClosedNotchExtensionActivity(
                id: activityID,
                priority: notification.status.notchPriority,
                updatedAt: notification.createdAt,
                metrics: .init(
                    exclusionWidth: notchWidth,
                    leadingWidth: 0,
                    trailingWidth: promptWidth,
                    leadingExclusionMargin: 0,
                    trailingExclusionMargin: 0,
                    horizontalChromeInset: cornerRadiusInsets.closed.bottom,
                    height: height
                ),
                content: AnyView(CodexClosedNotchPrompt(
                    notification: notification,
                    presentationSurfaceID: context.surfaceID,
                    notchWidth: notchWidth,
                    height: height
                )),
                opensNotchOnHover: isPermissionRequest,
                opensNotchOnTap: false,
                onSelect: {
                    if notification.status == .needsAction(.systemPermission) {
                        CodexNotificationManager.shared.openCodexAndDismiss(notification)
                    } else {
                        CodexNotificationManager.shared.openCodex(for: notification)
                    }
                }
            )]
        }
    )
}

private extension CodexJobStatus {
    var notchPriority: ClosedNotchPresentationPriority {
        switch self {
        case .needsAction(.permission), .needsAction(.systemPermission),
             .needsAction(.decision), .failed:
            .critical
        case .needsAction(.manualCheck):
            .system
        case .succeeded:
            .activity
        }
    }

    var icon: String {
        switch self {
        case .needsAction(.permission): "lock.shield.fill"
        case .needsAction(.systemPermission): "gearshape.fill"
        case .needsAction(.decision): "questionmark.circle.fill"
        case .needsAction(.manualCheck): "hand.tap.fill"
        case .failed: "xmark.circle.fill"
        case .succeeded: "checkmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .needsAction(.permission), .needsAction(.systemPermission),
             .needsAction(.decision): .orange
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
            Image(systemName: status.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(status.tint)
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
    let notchWidth: CGFloat
    let height: CGFloat

    private var isPermissionRequest: Bool {
        notification.status == .needsAction(.permission)
    }

    var body: some View {
        promptContainer
            .id("\(notification.id):\(notification.createdAt.timeIntervalSinceReferenceDate)")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(notification.jobTitle)
            .accessibilityValue(
                isPermissionRequest
                    ? "Permission required. Hover to review, or click to open Codex."
                    : "\(notification.status.title). \(notification.projectName)"
            )
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
                .frame(width: notchWidth, height: height)
                .accessibilityHidden(true)

            prompt
                .frame(width: 236, height: height, alignment: .leading)
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
        HStack(spacing: 8) {
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

            Circle()
                .fill(notification.status.tint)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
        }
        .padding(.leading, 17)
        .padding(.trailing, 7)
    }

    private var summary: String {
        "\(notification.status.title) · \(notification.projectName)"
    }
}

struct CodexPermissionApprovalView: View {
    private static let disclosureCharacterLimit = 140
    private static let viewportHeight = max(0, openNotchSize.height - 12)

    let notification: CodexJobNotification
    let onDismiss: () -> Void

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

    private var toolDisplayName: String {
        details.toolName == "Bash" ? "Terminal" : details.toolName
    }

    private var requestDescription: String {
        details.description
            ?? "Codex is requesting permission to use \(toolDisplayName)."
    }

    private var canRespondInNotch: Bool {
        notification.permissionControl == .accessibility
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: toolIcon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text(toolDisplayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Collapse permission request")
            }

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
                                    title: details.toolName == "apply_patch" ? "Files" : "Command",
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

            if let error = manager.lastError {
                VStack(alignment: .leading, spacing: 4) {
                    Text(error)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.red)
                        .lineLimit(2)

                    if manager.accessibilityAuthorizationRequired {
                        Button {
                            XPCHelperClient.shared.openAccessibilitySettings()
                        } label: {
                            Label("Open Accessibility Settings", systemImage: "accessibility")
                        }
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel("Open macOS Accessibility settings")
                    }
                }
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

    @ViewBuilder
    private var permissionActions: some View {
        if canRespondInNotch {
            HStack(spacing: 8) {
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

                Spacer()

                if isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Sending decision to Codex")
                }
            }
        } else {
            Text("Respond in Codex to continue.")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.orange.opacity(0.95))
        }
    }

    private func submit(_ decision: CodexPermissionDecision) {
        Task {
            await manager.submitPermissionDecision(decision, for: notification)
        }
    }

    private var toolIcon: String {
        details.toolName == "Bash" ? "terminal" : "lock.shield"
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
