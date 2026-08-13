//
//  AIWeatherViews.swift
//  boringNotch
//
//  Created by Codex on 2026-06-06.
//

import AppKit
import Defaults
import SwiftUI
import UniformTypeIdentifiers

private struct AgentAttachedFile: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let path: String
    let content: String
    let byteCount: Int
}

private enum AgentInspectorMode: String, Identifiable {
    case plugins
    case skills
    case memory
    case knowledge

    var id: String { rawValue }

    var windowTitle: String {
        switch self {
        case .plugins: return "蛋神 · 插件总览"
        case .skills: return "蛋神 · Skills 总览"
        case .memory: return "蛋神 · 记忆系统"
        case .knowledge: return "蛋神 · 本地知识库"
        }
    }

    var savedPanelSize: CGSize {
        switch self {
        case .plugins:
            return .init(width: Defaults[.aiPluginPanelWidth], height: Defaults[.aiPluginPanelHeight])
        case .skills:
            return .init(width: Defaults[.aiSkillsPanelWidth], height: Defaults[.aiSkillsPanelHeight])
        case .memory:
            return .init(width: Defaults[.aiMemoryPanelWidth], height: Defaults[.aiMemoryPanelHeight])
        case .knowledge:
            return .init(width: Defaults[.aiKnowledgePanelWidth], height: Defaults[.aiKnowledgePanelHeight])
        }
    }

    func savePanelSize(_ size: CGSize) {
        switch self {
        case .plugins:
            Defaults[.aiPluginPanelWidth] = size.width
            Defaults[.aiPluginPanelHeight] = size.height
        case .skills:
            Defaults[.aiSkillsPanelWidth] = size.width
            Defaults[.aiSkillsPanelHeight] = size.height
        case .memory:
            Defaults[.aiMemoryPanelWidth] = size.width
            Defaults[.aiMemoryPanelHeight] = size.height
        case .knowledge:
            Defaults[.aiKnowledgePanelWidth] = size.width
            Defaults[.aiKnowledgePanelHeight] = size.height
        }
    }
}

@MainActor
private final class AgentInspectorWindowController: NSObject, NSWindowDelegate {
    static let shared = AgentInspectorWindowController()

    private var inspectorWindow: NSWindow?
    private var currentMode: AgentInspectorMode?

    var isVisible: Bool {
        inspectorWindow?.isVisible == true
    }

    func show(mode: AgentInspectorMode) {
        if currentMode != mode {
            persistCurrentSize()
        }
        currentMode = mode

        let isNewWindow = inspectorWindow == nil
        let targetSize = resolvedContentSize(mode.savedPanelSize)
        let window = inspectorWindow ?? makeWindow()

        window.title = mode.windowTitle
        window.contentView = NSHostingView(
            rootView: AgentInventoryPanel(mode: mode)
                .id(mode)
                .onExitCommand { [weak self] in
                    self?.close()
                }
        )
        window.setContentSize(targetSize)

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        AppWindowPresentationCoordinator.shared.present(window)

        if isNewWindow {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        persistCurrentSize()
        inspectorWindow?.close()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: CGSize(width: 760, height: 460)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("DanShenAgentInspectorWindow")
        window.contentMinSize = NSSize(width: 520, height: 340)
        window.collectionBehavior = [.managed, .participatesInCycle, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.isExcludedFromWindowsMenu = false
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.animationBehavior = .documentWindow
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .windowBackgroundColor
        window.level = .normal
        window.delegate = self
        inspectorWindow = window
        return window
    }

    private func resolvedContentSize(_ requested: CGSize) -> CGSize {
        let visibleSize = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame.size
            ?? CGSize(width: 1440, height: 900)
        let maximum = CGSize(
            width: max(520, visibleSize.width - 80),
            height: max(340, visibleSize.height - 80)
        )
        return CGSize(
            width: min(max(requested.width, 520), maximum.width),
            height: min(max(requested.height, 340), maximum.height)
        )
    }

    private func persistCurrentSize() {
        guard let currentMode, let inspectorWindow else { return }
        currentMode.savePanelSize(inspectorWindow.contentLayoutRect.size)
    }

    func windowDidResize(_ notification: Notification) {
        persistCurrentSize()
    }

    func windowWillClose(_ notification: Notification) {
        persistCurrentSize()
        if let inspectorWindow {
            AppWindowPresentationCoordinator.shared.dismiss(inspectorWindow)
        }
        AppWindowPresentationCoordinator.shared.relinquishApplicationFocusIfPossible()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let inspectorWindow {
            AppWindowPresentationCoordinator.shared.present(inspectorWindow)
        }
    }

    func windowDidMiniaturize(_ notification: Notification) {
        AppWindowPresentationCoordinator.shared.refresh()
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        if let inspectorWindow {
            AppWindowPresentationCoordinator.shared.present(inspectorWindow)
        }
    }
}

private enum AgentFileImportMode {
    case attach
    case knowledge
}

private enum AgentResizeAxis: Equatable {
    case horizontal
    case vertical
    case both
}

private let agentResizeHorizontalSensitivity: CGFloat = 0.52
private let agentResizeVerticalSensitivity: CGFloat = 0.56
private let agentPanelAnimation = NotchPanelAnimation.spring

@MainActor
private func prepareAgentOpenPanel(_ panel: NSOpenPanel) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    panel.hidesOnDeactivate = false
    panel.isFloatingPanel = false
    panel.level = .normal
    panel.collectionBehavior = [.managed, .participatesInCycle, .fullScreenAuxiliary]
}

private func agentPanelHostWindow() -> NSWindow? {
    if let keyWindow = NSApp.keyWindow, isAgentPanelHostWindow(keyWindow) {
        return keyWindow
    }

    return NSApp.windows.first { window in
        window.isVisible && isAgentPanelHostWindow(window)
    }
}

private func isAgentPanelHostWindow(_ window: NSWindow) -> Bool {
    window is BoringNotchWindow
        || window is BoringNotchSkyLightWindow
        || window.identifier?.rawValue == "DanShenAgentInspectorWindow"
}

@MainActor
func runAgentOpenPanel(_ panel: NSOpenPanel, completion: @escaping ([URL]) -> Void) {
    prepareAgentOpenPanel(panel)
    AppWindowPresentationCoordinator.shared.present(panel)

    let finish: (NSApplication.ModalResponse) -> Void = { response in
        DispatchQueue.main.async {
            AppWindowPresentationCoordinator.shared.dismiss(panel)
            AppWindowPresentationCoordinator.shared.relinquishApplicationFocusIfPossible()
            completion(response == .OK ? panel.urls : [])
        }
    }

    if let hostWindow = agentPanelHostWindow(),
       !(hostWindow is BoringNotchWindow),
       !(hostWindow is BoringNotchSkyLightWindow) {
        hostWindow.makeKeyAndOrderFront(nil)

        panel.beginSheetModal(for: hostWindow) { response in
            finish(response)
        }
        return
    }

    panel.begin { response in
        finish(response)
    }
}

private struct AgentSlashCommand: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbolName: String
}

struct AIChatView: View {
    @Default(.aiChatEnabled) private var aiChatEnabled
    @Default(.aiShowAgentTrace) private var aiShowAgentTrace

    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var manager = AIChatManager.shared
    @State private var draft: String = ""
    @State private var showsTrace: Bool = false
    @State private var attachedFiles: [AgentAttachedFile] = []
    @State private var fileError: String?
    @State private var resizeStartSize: CGSize?
    @State private var activeResizeAxis: AgentResizeAxis?
    @FocusState private var isComposerFocused: Bool

    private let slashCommands: [AgentSlashCommand] = [
        .init(id: "/new", title: "新对话", subtitle: "创建一个独立会话页", symbolName: "plus.bubble"),
        .init(id: "/chats", title: "会话", subtitle: "查看并切换多个对话页", symbolName: "rectangle.3.group.bubble"),
        .init(id: "/plugins", title: "插件", subtitle: "查看可用工具、权限和风险等级", symbolName: "puzzlepiece.extension"),
        .init(id: "/skills", title: "Skills", subtitle: "查看任务技能手册", symbolName: "sparkles"),
        .init(id: "/memory", title: "记忆", subtitle: "查看工作记忆和长期记忆", symbolName: "brain.head.profile"),
        .init(id: "/knowledge", title: "知识库", subtitle: "显示资料数量；add 导入文件；seed 导入 GitHub 示例", symbolName: "books.vertical"),
        .init(id: "/kb", title: "知识库", subtitle: "同 /knowledge，可输入 add、seed 或 clear", symbolName: "books.vertical"),
        .init(id: "/remember", title: "记住", subtitle: "把一句稳定偏好写入长期记忆", symbolName: "plus.circle"),
        .init(id: "/forget", title: "遗忘", subtitle: "按关键词删除长期记忆，留空则清空", symbolName: "minus.circle"),
        .init(id: "/file", title: "上传文件", subtitle: "支持文本、PDF（含扫描件 OCR）和图片 OCR", symbolName: "paperclip"),
        .init(id: "/web", title: "联网检索", subtitle: "搜索公开网页或 GitHub 仓库", symbolName: "globe"),
        .init(id: "/clear", title: "清空", subtitle: "清除当前会话消息和轨迹", symbolName: "trash"),
        .init(id: "/help", title: "帮助", subtitle: "生成命令、插件和 Skills 说明", symbolName: "questionmark.circle"),
    ]

    var body: some View {
        VStack(spacing: 10) {
            header

            if !aiChatEnabled {
                featureDisabledState(
                    title: "AI 已关闭",
                    subtitle: "请在 设置 > AI 中启用智能体。"
                )
            } else if !manager.hasConfiguredAPIKey {
                featureDisabledState(
                    title: "缺少 API Key",
                    subtitle: "请在 设置 > AI 中填写 Base URL、模型和 API Key。"
                )
            } else {
                conversationTabs
                messagesPanel
                if aiShowAgentTrace, let trace = manager.lastAgentTrace {
                    AgentTracePanel(trace: trace, isExpanded: $showsTrace)
                        .layoutPriority(0)
                }
                composer
                    .layoutPriority(2)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(resizeHandles)
        .onAppear {
            vm.preventAutoClose = true
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            manager.refreshPersistentState()

            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                isComposerFocused = true
            }
        }
        .onDisappear {
            vm.preventAutoClose = false
            isComposerFocused = false

            if SettingsWindowController.shared.window?.isVisible != true,
               !AgentInspectorWindowController.shared.isVisible {
                NSApp.setActivationPolicy(.accessory)
            }
        }
        .onChange(of: manager.isSending) { _, isSending in
            if isSending {
                showsTrace = false
            }
        }
        .onChange(of: manager.lastAgentTrace?.id) { _, _ in
            showsTrace = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            manager.refreshPersistentState()
        }
    }

    private var resizeHandles: some View {
        ZStack {
            HStack {
                Spacer()
                resizeEdge(axis: .horizontal, width: 12, height: nil)
            }

            VStack {
                Spacer()
                HStack {
                    Spacer(minLength: 40)
                    resizeEdge(axis: .vertical, width: nil, height: 12)
                    Spacer(minLength: 40)
                }
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    resizeCorner
                }
            }
        }
        .allowsHitTesting(true)
        .zIndex(20)
    }

    private func resizeEdge(axis: AgentResizeAxis, width: CGFloat?, height: CGFloat?) -> some View {
        Rectangle()
            .fill(activeResizeAxis == axis ? Color.effectiveAccent.opacity(0.28) : Color.white.opacity(0.001))
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .gesture(resizeGesture(axis: axis))
            .help(axis == .horizontal ? "拖拽调整宽度" : "拖拽调整高度")
    }

    private var resizeCorner: some View {
        ZStack(alignment: .bottomTrailing) {
            Rectangle()
                .fill(Color.white.opacity(0.001))
                .frame(width: 34, height: 34)
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(activeResizeAxis == .both ? Color.effectiveAccent : Color.white.opacity(0.38))
                .padding(7)
        }
        .contentShape(Rectangle())
        .gesture(resizeGesture(axis: .both))
        .help("拖拽调整宽高")
    }

    private func resizeGesture(axis: AgentResizeAxis) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { value in
                let startSize = resizeStartSize ?? vm.notchSize
                resizeStartSize = startSize
                activeResizeAxis = axis

                var nextWidth = startSize.width
                var nextHeight = startSize.height

                switch axis {
                case .horizontal:
                    nextWidth = startSize.width + value.translation.width * agentResizeHorizontalSensitivity
                case .vertical:
                    nextHeight = startSize.height + value.translation.height * agentResizeVerticalSensitivity
                case .both:
                    nextWidth = startSize.width + value.translation.width * agentResizeHorizontalSensitivity
                    nextHeight = startSize.height + value.translation.height * agentResizeVerticalSensitivity
                }

                vm.resizeAssistantPanel(
                    to: CGSize(
                        width: nextWidth,
                        height: nextHeight
                    ),
                    persist: false
                )
            }
            .onEnded { _ in
                vm.finishAssistantPanelResize()
                resizeStartSize = nil
                activeResizeAxis = nil
            }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("蛋神 Agent")
                    .font(.headline)
                Text(manager.displayedModelName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if manager.isSending {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                manager.clearConversation()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("清空当前会话")

            Button {
                collapseAssistantPanel()
            } label: {
                Text(">>")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("收回 AI 面板")
        }
    }

    private func collapseAssistantPanel() {
        showsTrace = false
        isComposerFocused = false
        vm.suppressHoverAutoOpen()

        withAnimation(agentPanelAnimation) {
            vm.close()
        }
    }

    private var conversationTabs: some View {
        HStack(spacing: 6) {
            Button {
                attachedFiles.removeAll()
                fileError = nil
                manager.startNewConversation()
                isComposerFocused = true
            } label: {
                Image(systemName: "plus.bubble")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.effectiveAccent)
            .help("新建对话")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(manager.conversations) { conversation in
                        ConversationTabButton(
                            conversation: conversation,
                            isActive: manager.activeConversationID == conversation.id,
                            canDelete: manager.conversations.count > 1,
                            onSelect: {
                                attachedFiles.removeAll()
                                fileError = nil
                                manager.selectConversation(conversation.id)
                                isComposerFocused = true
                            },
                            onDelete: {
                                manager.deleteConversation(conversation.id)
                            }
                        )
                    }
                }
            }

            Button {
                AgentInspectorWindowController.shared.show(mode: .knowledge)
            } label: {
                Image(systemName: "books.vertical")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("知识库")
        }
        .frame(height: 30)
    }

    private var messagesPanel: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    if manager.messages.isEmpty {
                        emptyConversationState
                    } else {
                        ForEach(manager.messages) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }
                    }

                    if let lastError = manager.lastError {
                        Label(lastError, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let persistenceError = manager.persistenceError {
                        Label(persistenceError, systemImage: "externaldrive.badge.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onChange(of: manager.messages.count) { _, _ in
                if let lastID = manager.messages.last?.id {
                    withAnimation(.smooth(duration: 0.2)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
        .layoutPriority(1)
    }

    private var emptyConversationState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("输入任务，或使用 / 调出命令。")
                .font(.subheadline.weight(.semibold))
            Text("上方可以切换多个会话页；知识库资料会跨会话检索，当前对话只保留自己的短期记忆。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !attachedFiles.isEmpty || fileError != nil {
                attachmentStrip
            }

            HStack(spacing: 8) {
                Button {
                    openFilePicker(mode: .attach)
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("上传文件作为上下文")

                TextField("输入问题，或输入 / 查看命令...", text: $draft)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .focused($isComposerFocused)
                    .onSubmit(sendDraft)

                Button(action: sendDraft) {
                    Image(systemName: manager.isSending ? "ellipsis.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(canSend ? .effectiveAccent : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.trailing, 24)
        }
        .overlay(alignment: .top) {
            if shouldShowSlashMenu {
                SlashCommandMenu(
                    commands: filteredSlashCommands,
                    onSelect: { command in
                        runSlashCommand(command, rawValue: draft)
                    }
                )
                .padding(.trailing, 24)
                .offset(
                    y: -SlashCommandMenu.preferredHeight(
                        for: filteredSlashCommands.count
                    ) - 8
                )
                .transition(.opacity)
            }
        }
        .zIndex(30)
    }

    private var shouldShowSlashMenu: Bool {
        isComposerFocused && draft.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/")
    }

    private var filteredSlashCommands: [AgentSlashCommand] {
        let rawQuery = draft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard rawQuery.count > 1 else { return slashCommands }
        let query = rawQuery.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? rawQuery
        if let exactCommand = slashCommands.first(where: { $0.id == query }) {
            return [exactCommand]
        }
        return slashCommands.filter { command in
            command.id.lowercased().contains(query)
                || command.title.lowercased().contains(query)
                || command.subtitle.lowercased().contains(query)
        }
    }

    private var attachmentStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !attachedFiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(attachedFiles) { file in
                            HStack(spacing: 6) {
                                Image(systemName: "doc.text")
                                    .font(.caption)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(file.name)
                                        .font(.caption2.weight(.semibold))
                                        .lineLimit(1)
                                    Text("\(file.byteCount / 1024 + 1) KB")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Button {
                                    attachedFiles.removeAll { $0.id == file.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
            }

            if let fileError {
                Label(fileError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var canSend: Bool {
        aiChatEnabled
            && !manager.isSending
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendDraft() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        if prompt.hasPrefix("/") {
            runSlashCommand(matching: prompt)
            return
        }

        let finalPrompt = promptWithAttachedFiles(prompt)
        let displayPrompt = displayPromptWithAttachedFiles(prompt)
        draft = ""
        attachedFiles.removeAll()
        showsTrace = false
        Task {
            await manager.send(prompt: finalPrompt, displayPrompt: displayPrompt)
        }
    }

    private func runSlashCommand(matching rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        let commandToken = lowered.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
        let command = slashCommands.first { $0.id == commandToken } ?? filteredSlashCommands.first
        if let command {
            runSlashCommand(command, rawValue: trimmed)
        }
    }

    private func runSlashCommand(_ command: AgentSlashCommand) {
        runSlashCommand(command, rawValue: command.id)
    }

    private func runSlashCommand(_ command: AgentSlashCommand, rawValue: String) {
        let argument = slashArgument(from: rawValue, commandID: command.id)
        switch command.id {
        case "/plugins":
            AgentInspectorWindowController.shared.show(mode: .plugins)
            draft = ""
        case "/skills":
            AgentInspectorWindowController.shared.show(mode: .skills)
            draft = ""
        case "/memory":
            if argument == "clear" {
                manager.clearLongTermMemory()
                manager.appendLocalAssistantMessage("已清空长期记忆。")
            } else if ["reveal", "open", "file"].contains(argument.lowercased()) {
                manager.revealLongTermMemoryFile()
                manager.appendLocalAssistantMessage("已在 Finder 中定位长期记忆文件。")
            } else {
                AgentInspectorWindowController.shared.show(mode: .memory)
            }
            draft = ""
        case "/remember":
            if argument.isEmpty {
                draft = "/remember "
                isComposerFocused = true
            } else if let record = manager.rememberMemory(argument) {
                AgentInspectorWindowController.shared.show(mode: .memory)
                draft = ""
                manager.appendLocalAssistantMessage("已写入长期记忆：[\(record.kind.displayName)] \(record.content)")
            }
        case "/forget":
            let removedCount = manager.forgetMemory(matching: argument)
            AgentInspectorWindowController.shared.show(mode: .memory)
            draft = ""
            if argument.isEmpty {
                manager.appendLocalAssistantMessage("已清空长期记忆，共删除 \(removedCount) 条。")
            } else {
                manager.appendLocalAssistantMessage("已删除 \(removedCount) 条匹配“\(argument)”的长期记忆。")
            }
        case "/file":
            draft = ""
            openFilePicker(mode: .attach)
        case "/web":
            draft = argument.isEmpty ? "请联网检索：" : "请联网检索：\(argument)"
            sendDraft()
        case "/knowledge", "/kb":
            if ["add", "import", "导入", "添加"].contains(argument.lowercased()) {
                draft = ""
                openFilePicker(mode: .knowledge)
            } else if ["seed", "demo", "github", "示例", "样例"].contains(argument.lowercased()) {
                let count = manager.installStarterKnowledgeBase()
                AgentInspectorWindowController.shared.show(mode: .knowledge)
                draft = ""
                manager.appendLocalAssistantMessage("已导入 \(count) 份 GitHub/官方文档启发的示例知识库。")
            } else if ["clear", "清空"].contains(argument.lowercased()) {
                manager.clearKnowledgeBase()
                AgentInspectorWindowController.shared.show(mode: .knowledge)
                draft = ""
                manager.appendLocalAssistantMessage("已清空本地知识库。")
            } else {
                AgentInspectorWindowController.shared.show(mode: .knowledge)
                draft = ""
                manager.refreshKnowledgeDocuments()
            }
        case "/new":
            draft = ""
            attachedFiles.removeAll()
            manager.startNewConversation()
        case "/chats":
            draft = ""
            attachedFiles.removeAll()
            isComposerFocused = true
        case "/clear":
            draft = ""
            attachedFiles.removeAll()
            manager.clearConversation()
        case "/help":
            draft = "请用中文说明你支持的 / 命令、插件和 Skills，并举 3 个示例任务。"
            sendDraft()
        default:
            break
        }
    }

    private func slashArgument(from rawValue: String, commandID: String) -> String {
        guard rawValue.lowercased().hasPrefix(commandID) else { return "" }
        return rawValue
            .dropFirst(commandID.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func openFilePicker(mode: AgentFileImportMode) {
        fileError = nil
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = agentAllowedImportTypes()

        runAgentOpenPanel(panel) { urls in
            Task { @MainActor in
                await importSelectedFiles(urls, mode: mode)
            }
        }
    }

    @MainActor
    private func importSelectedFiles(_ urls: [URL], mode: AgentFileImportMode) async {
        guard !urls.isEmpty else { return }

        var importedKnowledgeTitles: [String] = []
        let maxFiles = mode == .knowledge ? 8 : 4

        for url in urls.prefix(maxFiles) {
            do {
                let file = try await Task.detached(priority: .userInitiated) {
                    try readAgentImportableFile(at: url)
                }.value

                switch mode {
                case .attach:
                    attachedFiles.append(
                        AgentAttachedFile(
                            name: url.lastPathComponent,
                            path: url.path,
                            content: file.content,
                            byteCount: file.byteCount
                        )
                    )
                case .knowledge:
                    if let document = manager.addKnowledgeDocument(
                        name: url.lastPathComponent,
                        path: url.path,
                        content: file.content,
                        byteCount: file.byteCount
                    ) {
                        importedKnowledgeTitles.append(document.title)
                    }
                }
            } catch {
                fileError = "\(url.lastPathComponent) 读取失败：\(error.localizedDescription)"
            }
        }

        if mode == .knowledge {
            AgentInspectorWindowController.shared.show(mode: .knowledge)
            if !importedKnowledgeTitles.isEmpty {
                manager.appendLocalAssistantMessage("已导入知识库：\(importedKnowledgeTitles.joined(separator: "、"))")
            }
        }
    }

    private func appendKnowledgeStatusMessage() {
        manager.refreshKnowledgeDocuments()
        let enabledText = Defaults[.aiKnowledgeRetrievalEnabled] ? "已开启" : "已关闭"
        let limit = Defaults[.aiKnowledgeRetrievalLimit]
        manager.appendLocalAssistantMessage(
            "本地知识库当前有 \(manager.knowledgeDocuments.count) 份资料，自动检索\(enabledText)，每次最多注入 Top-\(limit)。使用 /knowledge add 导入资料，/knowledge seed 导入示例，/knowledge clear 清空。"
        )
    }

    private func promptWithAttachedFiles(_ prompt: String) -> String {
        guard !attachedFiles.isEmpty else { return prompt }

        let fileBlocks = attachedFiles.map { file in
            """
            [file: \(file.name)]
            path: \(file.path)
            content:
            \(file.content)
            """
        }.joined(separator: "\n\n")

        return """
        用户问题：
        \(prompt)

        本地文件上下文：
        \(fileBlocks)
        """
    }

    private func displayPromptWithAttachedFiles(_ prompt: String) -> String {
        guard !attachedFiles.isEmpty else { return prompt }
        return "\(prompt)\n\n已附加文件：\(attachedFiles.map(\.name).joined(separator: "、"))"
    }

    private func featureDisabledState(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("打开设置") {
                SettingsWindowController.shared.showWindow()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SlashCommandMenu: View {
    let commands: [AgentSlashCommand]
    let onSelect: (AgentSlashCommand) -> Void

    private static let rowHeight: CGFloat = 42
    private static let verticalPadding: CGFloat = 10
    private static let maximumHeight: CGFloat = 262

    static func preferredHeight(for commandCount: Int) -> CGFloat {
        let visibleRows = max(commandCount, 1)
        return min(
            CGFloat(visibleRows) * rowHeight + verticalPadding,
            maximumHeight
        )
    }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                if commands.isEmpty {
                    Label("没有匹配的命令", systemImage: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
                        .padding(.horizontal, 10)
                } else {
                    ForEach(commands) { command in
                        Button {
                            onSelect(command)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: command.symbolName)
                                    .font(.system(size: 13, weight: .semibold))
                                    .frame(width: 18)
                                    .foregroundStyle(Color.effectiveAccent)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(command.id)  \(command.title)")
                                        .font(.caption.weight(.semibold))
                                    Text(command.subtitle)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: Self.rowHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .scrollIndicators(.visible)
        .padding(.vertical, Self.verticalPadding / 2)
        .frame(height: Self.preferredHeight(for: commands.count))
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.98))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 12, y: 5)
    }
}

private struct ConversationTabButton: View {
    let conversation: AgentChatConversation
    let isActive: Bool
    let canDelete: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isActive ? "bubble.left.and.bubble.right.fill" : "bubble.left")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isActive ? Color.effectiveAccent : .secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(conversation.title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                Text("\(conversation.messages.count) 条")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if canDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("删除会话")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isActive ? Color.effectiveAccent.opacity(0.18) : Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .frame(maxWidth: 170)
    }
}

private struct AgentInventoryPanel: View {
    let mode: AgentInspectorMode
    @ObservedObject private var manager = AIChatManager.shared
    @Default(.aiKnowledgeRetrievalEnabled) private var aiKnowledgeRetrievalEnabled
    @Default(.aiKnowledgeRetrievalLimit) private var aiKnowledgeRetrievalLimit
    @State private var selectedSkillCategory: String = "全部"
    @State private var knowledgeImportError: String?
    @State private var selectedMemoryKind: String = "all"
    @State private var memorySearchText: String = ""
    @State private var editingMemoryID: UUID?
    @State private var memoryDraft: String = ""
    @State private var memoryDraftKind: AgentMemoryRecord.Kind = .fact
    @State private var memoryFeedback: String?
    @State private var showsClearMemoryConfirmation = false
    private let columns = [GridItem(.adaptive(minimum: 250, maximum: 360), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(panelTitle, systemImage: panelIcon)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(panelCount)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ScrollView(showsIndicators: true) {
                switch mode {
                case .plugins:
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(manager.availablePlugins) { plugin in
                            PluginInventoryCard(plugin: plugin)
                        }
                    }
                case .skills:
                    VStack(alignment: .leading, spacing: 8) {
                        skillCategoryPicker
                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(filteredSkills) { skill in
                                SkillInventoryCard(skill: skill)
                            }
                        }
                    }
                case .memory:
                    memoryPanel
                case .knowledge:
                    knowledgePanel
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            manager.refreshPersistentState()
        }
    }

    private var skillCategoryPicker: some View {
        HStack(spacing: 6) {
            ForEach(skillCategories, id: \.self) { category in
                Button {
                    selectedSkillCategory = category
                } label: {
                    Text(category)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            selectedSkillCategory == category
                            ? Color.effectiveAccent.opacity(0.26)
                            : Color.white.opacity(0.05)
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var skillCategories: [String] {
        let categories = manager.availableSkills.map(\.category)
        return ["全部"] + Array(Set(categories)).sorted()
    }

    private var filteredSkills: [AgentSkillDescriptor] {
        guard selectedSkillCategory != "全部" else {
            return manager.availableSkills
        }
        return manager.availableSkills.filter { $0.category == selectedSkillCategory }
    }

    private var panelTitle: String {
        switch mode {
        case .plugins: return "插件总览"
        case .skills: return "Skills 总览"
        case .memory: return "记忆系统"
        case .knowledge: return "本地知识库"
        }
    }

    private var panelIcon: String {
        switch mode {
        case .plugins: return "puzzlepiece.extension"
        case .skills: return "sparkles"
        case .memory: return "brain.head.profile"
        case .knowledge: return "books.vertical"
        }
    }

    private var panelCount: String {
        switch mode {
        case .plugins: return "\(manager.availablePlugins.count) 个插件"
        case .skills: return "\(filteredSkills.count)/\(manager.availableSkills.count) 个技能"
        case .memory: return "\(manager.longTermMemories.count) 条长期记忆"
        case .knowledge: return "\(manager.knowledgeDocuments.count) 份资料"
        }
    }

    private var memoryPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: columns, spacing: 6) {
                MemoryLayerCard(
                    title: "短期记忆",
                    value: "\(min(manager.messages.count, 6)) 条",
                    detail: "最近会话窗口，直接进入上下文",
                    symbolName: "text.bubble"
                )
                MemoryLayerCard(
                    title: "工作记忆",
                    value: manager.lastAgentTrace?.workingMemory == nil ? "待生成" : "已生成",
                    detail: "当前目标、进度、实体和待澄清问题",
                    symbolName: "list.clipboard"
                )
                MemoryLayerCard(
                    title: "长期记忆",
                    value: "\(manager.longTermMemories.count) 条",
                    detail: "显式写入，本地检索后按需注入",
                    symbolName: "externaldrive"
                )
            }

            if let workingMemory = manager.lastAgentTrace?.workingMemory {
                VStack(alignment: .leading, spacing: 4) {
                    Text("工作记忆")
                        .font(.caption2.weight(.semibold))
                    Text(workingMemory.contextText)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索记忆内容或关键词", text: $memorySearchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                Button {
                    beginCreatingMemory()
                } label: {
                    Label("新增", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Picker("记忆类型", selection: $selectedMemoryKind) {
                Text("全部").tag("all")
                ForEach(AgentMemoryRecord.Kind.allCases, id: \.rawValue) { kind in
                    Text(kind.displayName).tag(kind.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if editingMemoryID != nil {
                memoryEditor
            }

            HStack {
                Text("长期记忆")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("显示 \(filteredMemories.count) / \(manager.longTermMemories.count) 条")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            if filteredMemories.isEmpty {
                Text(manager.longTermMemories.isEmpty
                     ? "还没有长期记忆。点击“新增”，或用 /remember 写入稳定信息。"
                     : "没有符合当前搜索和类型筛选的记忆。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                LazyVStack(spacing: 6) {
                    ForEach(filteredMemories) { memory in
                        MemoryInventoryCard(
                            memory: memory,
                            onEdit: { beginEditingMemory(memory) },
                            onDelete: {
                                if manager.deleteMemory(id: memory.id) {
                                    if editingMemoryID == memory.id {
                                        cancelMemoryEditing()
                                    }
                                    memoryFeedback = "已删除这条长期记忆。"
                                }
                            }
                        )
                    }
                }
            }

            if let memoryFeedback {
                Text(memoryFeedback)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button("定位记忆文件") {
                    manager.revealLongTermMemoryFile()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)

                Button("清空长期记忆") {
                    showsClearMemoryConfirmation = true
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.red)
            }
        }
        .alert("清空全部长期记忆？", isPresented: $showsClearMemoryConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                manager.clearLongTermMemory()
                cancelMemoryEditing()
                memoryFeedback = "已清空全部长期记忆。"
            }
        } message: {
            Text("此操作会删除本地保存的全部长期记忆，无法撤销。")
        }
    }

    private var filteredMemories: [AgentMemoryRecord] {
        let query = memorySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return manager.longTermMemories.filter { memory in
            let kindMatches = selectedMemoryKind == "all" || memory.kind.rawValue == selectedMemoryKind
            let queryMatches = query.isEmpty
                || memory.content.localizedCaseInsensitiveContains(query)
                || memory.keywords.contains(where: { $0.localizedCaseInsensitiveContains(query) })
            return kindMatches && queryMatches
        }
    }

    private var memoryEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(editingMemoryID == AgentMemoryEditor.newRecordID ? "新增长期记忆" : "编辑长期记忆",
                      systemImage: "square.and.pencil")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button(action: cancelMemoryEditing) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("取消编辑")
            }

            Picker("类型", selection: $memoryDraftKind) {
                ForEach(AgentMemoryRecord.Kind.allCases, id: \.rawValue) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            TextEditor(text: $memoryDraft)
                .font(.caption)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: 72, maxHeight: 110)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            HStack {
                Text("保存后将参与跨会话检索。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消", action: cancelMemoryEditing)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("保存", action: saveMemoryDraft)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(memoryDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(9)
        .background(Color.effectiveAccent.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func beginCreatingMemory() {
        editingMemoryID = AgentMemoryEditor.newRecordID
        memoryDraft = ""
        memoryDraftKind = .fact
        memoryFeedback = nil
    }

    private func beginEditingMemory(_ memory: AgentMemoryRecord) {
        editingMemoryID = memory.id
        memoryDraft = memory.content
        memoryDraftKind = memory.kind
        memoryFeedback = nil
    }

    private func cancelMemoryEditing() {
        editingMemoryID = nil
        memoryDraft = ""
        memoryDraftKind = .fact
    }

    private func saveMemoryDraft() {
        let content = memoryDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, let editingMemoryID else { return }

        let saved: Bool
        if editingMemoryID == AgentMemoryEditor.newRecordID {
            saved = manager.createMemory(content, kind: memoryDraftKind) != nil
        } else {
            saved = manager.updateMemory(id: editingMemoryID, content: content, kind: memoryDraftKind)
        }
        memoryFeedback = saved ? "长期记忆已保存。" : "保存失败，请检查本地存储权限。"
        if saved {
            cancelMemoryEditing()
        }
    }

    private var knowledgePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: columns, spacing: 6) {
                MemoryLayerCard(
                    title: "资料数量",
                    value: "\(manager.knowledgeDocuments.count) 份",
                    detail: "跨会话检索，不属于某一个聊天页",
                    symbolName: "books.vertical"
                )
                MemoryLayerCard(
                    title: "检索方式",
                    value: aiKnowledgeRetrievalEnabled ? "Hybrid" : "关闭",
                    detail: "关键词 + 语义词 + 时间权重 Top-\(aiKnowledgeRetrievalLimit) 注入",
                    symbolName: "magnifyingglass"
                )
                MemoryLayerCard(
                    title: "存储",
                    value: "JSON",
                    detail: manager.knowledgeStorageLocation.lastPathComponent,
                    symbolName: "externaldrive"
                )
            }

            if manager.knowledgeDocuments.isEmpty {
                Text("还没有导入资料。使用 /knowledge add，或点击下面的“导入资料”按钮导入文本、Markdown、JSON、CSV、PDF（含扫描件 OCR）或带文字的图片。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                ForEach(manager.knowledgeDocuments) { document in
                    KnowledgeInventoryCard(document: document) {
                        manager.removeKnowledgeDocument(id: document.id)
                    }
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 8)], alignment: .leading, spacing: 6) {
                Button("导入 GitHub 示例") {
                    let count = manager.installStarterKnowledgeBase()
                    manager.appendLocalAssistantMessage("已导入 \(count) 份 GitHub/官方文档启发的示例知识库。")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)

                Button("导入资料") {
                    openKnowledgeImporter()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)

                Button("刷新") {
                    manager.refreshKnowledgeDocuments()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)

                Button("定位文件") {
                    manager.revealKnowledgeBaseFile()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)

                Button("清空知识库") {
                    manager.clearKnowledgeBase()
                    manager.appendLocalAssistantMessage("已清空本地知识库。")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.red)
            }

            if let knowledgeImportError {
                Label(knowledgeImportError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            if let persistenceError = manager.persistenceError {
                Label(persistenceError, systemImage: "externaldrive.badge.exclamationmark")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func openKnowledgeImporter() {
        knowledgeImportError = nil
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = agentAllowedImportTypes()

        runAgentOpenPanel(panel) { urls in
            Task { @MainActor in
                await importKnowledgeFiles(urls)
            }
        }
    }

    @MainActor
    private func importKnowledgeFiles(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }

        var imported: [String] = []
        for url in urls.prefix(8) {
            do {
                let file = try await Task.detached(priority: .userInitiated) {
                    try readAgentImportableFile(at: url)
                }.value
                if let document = manager.addKnowledgeDocument(
                    name: url.lastPathComponent,
                    path: url.path,
                    content: file.content,
                    byteCount: file.byteCount
                ) {
                    imported.append(document.title)
                }
            } catch {
                knowledgeImportError = "\(url.lastPathComponent) 读取失败：\(error.localizedDescription)"
            }
        }

        if !imported.isEmpty {
            manager.appendLocalAssistantMessage("已导入知识库：\(imported.joined(separator: "、"))")
        }
    }
}

private struct MemoryLayerCard: View {
    let title: String
    let value: String
    let detail: String
    let symbolName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: symbolName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.effectiveAccent)
                Text(title)
                    .font(.caption2.weight(.semibold))
                Spacer()
                Text(value)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private enum AgentMemoryEditor {
    static let newRecordID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
}

private struct MemoryInventoryCard: View {
    let memory: AgentMemoryRecord
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var showsDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(memory.kind.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.effectiveAccent)
                Spacer()
                Text(memory.updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("编辑记忆")
                Button {
                    showsDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .help("删除记忆")
            }
            Text(memory.content)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            HStack(spacing: 6) {
                Text("重要 \(Int((memory.importance * 100).rounded()))%")
                Text("置信 \(Int((memory.confidence * 100).rounded()))%")
                Text("访问 \(memory.accessCount)")
                if let score = memory.retrievalScore {
                    Text("命中 \(Int((score * 100).rounded()))%")
                }
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            if let reason = memory.retrievalReason {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(memory.keywords.prefix(8).joined(separator: ", "))
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .alert("删除这条长期记忆？", isPresented: $showsDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive, action: onDelete)
        } message: {
            Text(memory.content)
        }
    }
}

private struct KnowledgeInventoryCard: View {
    let document: AgentKnowledgeDocument
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(document.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(document.updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("移出知识库")
            }
            Text(document.summary.isEmpty ? "无摘要" : document.summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Text(document.sourcePath)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text("\(document.byteCount / 1024 + 1) KB")
                Text(document.keywords.prefix(6).joined(separator: ", "))
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct PluginInventoryCard: View {
    let plugin: AgentPluginDescriptor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(plugin.name)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(plugin.riskLevel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(plugin.riskLevel == "中" ? .orange : .green)
            }
            Text(plugin.summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 4) {
                ForEach(plugin.typeTags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.effectiveAccent.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            Text(plugin.toolNames.joined(separator: ", "))
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(plugin.permission)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SkillInventoryCard: View {
    let skill: AgentSkillDescriptor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(skill.name)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(skill.riskLevel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(skill.riskLevel == "中" ? .orange : .green)
            }
            Text(skill.summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(skill.category)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.effectiveAccent.opacity(0.16))
                    .clipShape(Capsule())
                Text(skill.source == "built-in" ? "内置" : skill.source)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(skill.workflowSteps.joined(separator: " -> "))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(skill.requiredTools.joined(separator: ", "))
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct AgentTracePanel: View {
    let trace: AgentRunTrace
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.smooth(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .frame(width: 10)
                    Text("智能体轨迹")
                        .font(.caption.weight(.semibold))
                    statusPill(trace.status)
                    metricChip("路由", "\(Int((trace.routeConfidence * 100).rounded()))%")
                    metricChip("工具", "\(trace.selectedToolNames.count)")
                    Spacer()
                    Text(trace.routeName)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)

            if isExpanded, trace.routeKind == "general_chat" {
                compactGeneralTrace
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if isExpanded {
                ScrollView(showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            metricChip("Skills", "\(trace.selectedSkills.count)")
                            metricChip("记忆", "\(trace.retrievedMemories.count)")
                            if trace.requiresConfirmation {
                                metricChip("风险", "写入")
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("任务理解")
                                .font(.caption2.weight(.semibold))
                            Text("\(trace.taskUnderstanding.taskType) / \(trace.taskUnderstanding.complexity) / \(trace.reasoningProfile.mode)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        if !trace.discoveredPlugins.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Tool Discovery")
                                    .font(.caption2.weight(.semibold))
                                ForEach(trace.discoveredPlugins.prefix(4)) { match in
                                    discoveryRow(match)
                                }
                            }
                        }

                        if !trace.selectedPlugins.isEmpty {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                                ForEach(trace.selectedPlugins) { plugin in
                                    pluginChip(plugin)
                                }
                            }
                        }

                        if !trace.selectedSkills.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Skills")
                                    .font(.caption2.weight(.semibold))
                                ForEach(trace.selectedSkills) { skill in
                                    skillChip(skill)
                                }
                            }
                        }

                        if let workingMemory = trace.workingMemory {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Working Memory")
                                    .font(.caption2.weight(.semibold))
                                Text(workingMemory.contextText)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(5)
                            }
                        }

                        if !trace.retrievedMemories.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Long-Term Memory")
                                    .font(.caption2.weight(.semibold))
                                ForEach(trace.retrievedMemories.prefix(3)) { memory in
                                    Text("[\(memory.kind.displayName)] \(memory.content) \(memory.retrievalReason ?? "")")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }

                        if !trace.planSteps.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Plan")
                                    .font(.caption2.weight(.semibold))
                                ForEach(trace.planSteps.prefix(4)) { step in
                                    Text("\(step.order). \(step.title)：\(step.status)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }

                        if !trace.recoveryStrategies.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Recovery")
                                    .font(.caption2.weight(.semibold))
                                ForEach(trace.recoveryStrategies.prefix(2)) { strategy in
                                    Text("\(strategy.trigger) -> \(strategy.strategy)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(trace.steps.suffix(5)) { step in
                                HStack(alignment: .top, spacing: 6) {
                                    Circle()
                                        .fill(statusColor(step.status))
                                        .frame(width: 6, height: 6)
                                        .padding(.top, 5)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(step.title)
                                            .font(.caption2.weight(.semibold))
                                        Text(step.detail)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.trailing, 6)
                }
                .frame(maxHeight: 210)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var compactGeneralTrace: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("普通对话：轻量轨迹")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            ForEach(trace.steps.suffix(3)) { step in
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor(step.status))
                        .frame(width: 6, height: 6)
                    Text(step.title)
                        .font(.caption2.weight(.semibold))
                    Text(step.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func statusPill(_ status: String) -> some View {
        Text(status)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(statusColor(status))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor(status).opacity(0.14))
            .clipShape(Capsule())
    }

    private func metricChip(_ title: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
        }
        .font(.caption2)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.05))
        .clipShape(Capsule())
    }

    private func pluginChip(_ plugin: AgentPluginDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(plugin.name)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(plugin.riskLevel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(plugin.category)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.effectiveAccent)
                .lineLimit(1)
            Text(plugin.toolNames.joined(separator: ", "))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func discoveryRow(_ match: AgentPluginMatch) -> some View {
        HStack(spacing: 6) {
            Image(systemName: match.selected ? "checkmark.circle.fill" : "circle")
                .font(.caption2)
                .foregroundStyle(match.selected ? Color.effectiveAccent : .secondary)
            Text(match.pluginName)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
            Text("\(Int((match.score * 100).rounded()))%")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(match.reason)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private func skillChip(_ skill: AgentSkillDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(skill.name)
                .font(.caption2.weight(.semibold))
            Text(skill.workflowSteps.joined(separator: " -> "))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "done", "completed", "已完成":
            return .green
        case "prepared", "已准备":
            return Color.effectiveAccent
        case "fallback", "skipped":
            return .orange
        case "error", "failed":
            return .red
        default:
            return .secondary
        }
    }
}

private struct ChatBubble: View {
    let message: AIChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 36) }

            VStack(alignment: .leading, spacing: 3) {
                Text(message.role == .user ? "你" : "助手")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                MarkdownMessageText(content: message.content)
                    .font(.caption)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                message.role == .user
                    ? Color.effectiveAccentBackground
                    : Color.white.opacity(0.06)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .frame(
                maxWidth: message.role == .user ? 420 : 640,
                alignment: message.role == .user ? .trailing : .leading
            )

            if message.role == .assistant { Spacer(minLength: 36) }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        .padding(.horizontal, 10)
    }
}

private struct MarkdownMessageText: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inlineMarkdown(text))
                .font(level <= 2 ? .subheadline.weight(.semibold) : .caption.weight(.semibold))
        case .paragraph(let text):
            Text(inlineMarkdown(text))
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•")
                    .foregroundStyle(Color.effectiveAccent)
                Text(inlineMarkdown(text))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .numbered(let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(marker)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.effectiveAccent)
                    .frame(minWidth: 18, alignment: .trailing)
                Text(inlineMarkdown(text))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .quote(let text):
            HStack(alignment: .top, spacing: 7) {
                Rectangle()
                    .fill(Color.effectiveAccent.opacity(0.65))
                    .frame(width: 2)
                Text(inlineMarkdown(text))
                    .foregroundStyle(.secondary)
            }
        case .code(let text):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
                    .padding(7)
            }
            .background(Color.black.opacity(0.24))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private var blocks: [MarkdownBlock] {
        MarkdownBlock.parse(content)
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

private enum MarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(String)
    case numbered(marker: String, text: String)
    case quote(String)
    case code(String)

    static func parse(_ source: String) -> [MarkdownBlock] {
        let lines = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        var result: [MarkdownBlock] = []
        var paragraphLines: [String] = []
        var codeLines: [String] = []
        var isInCodeFence = false

        func flushParagraph() {
            let text = paragraphLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                result.append(.paragraph(text))
            }
            paragraphLines.removeAll(keepingCapacity: true)
        }

        func flushCode() {
            let text = codeLines.joined(separator: "\n")
                .trimmingCharacters(in: .newlines)
            if !text.isEmpty {
                result.append(.code(text))
            }
            codeLines.removeAll(keepingCapacity: true)
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                flushParagraph()
                if isInCodeFence {
                    flushCode()
                }
                isInCodeFence.toggle()
                continue
            }

            if isInCodeFence {
                codeLines.append(rawLine)
                continue
            }

            guard !line.isEmpty else {
                flushParagraph()
                continue
            }

            let headingLevel = line.prefix { $0 == "#" }.count
            if headingLevel > 0,
               headingLevel <= 6,
               line.dropFirst(headingLevel).first == " "
            {
                flushParagraph()
                result.append(.heading(
                    level: headingLevel,
                    text: String(line.dropFirst(headingLevel)).trimmingCharacters(in: .whitespaces)
                ))
                continue
            }

            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraph()
                result.append(.bullet(String(line.dropFirst(2))))
                continue
            }

            if let markerRange = line.range(of: #"^\d+[\.)]\s+"#, options: .regularExpression) {
                flushParagraph()
                let marker = String(line[..<markerRange.upperBound]).trimmingCharacters(in: .whitespaces)
                result.append(.numbered(
                    marker: marker,
                    text: String(line[markerRange.upperBound...])
                ))
                continue
            }

            if line.hasPrefix("> ") {
                flushParagraph()
                result.append(.quote(String(line.dropFirst(2))))
                continue
            }

            if line.contains("|") && line.filter({ $0 == "|" }).count >= 2 {
                let cells = line
                    .split(separator: "|", omittingEmptySubsequences: true)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                let isSeparator = !cells.isEmpty && cells.allSatisfy { cell in
                    cell.replacingOccurrences(of: "-", with: "")
                        .replacingOccurrences(of: ":", with: "")
                        .isEmpty
                }
                if !isSeparator {
                    flushParagraph()
                    result.append(.bullet(cells.joined(separator: " · ")))
                }
                continue
            }

            paragraphLines.append(rawLine)
        }

        if isInCodeFence {
            flushCode()
        } else {
            flushParagraph()
        }
        return result.isEmpty ? [.paragraph(source)] : result
    }
}
