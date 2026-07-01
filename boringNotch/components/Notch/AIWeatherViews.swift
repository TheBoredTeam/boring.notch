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

private let agentResizeHorizontalSensitivity: CGFloat = 0.68
private let agentResizeVerticalSensitivity: CGFloat = 0.72
private let agentOpenPanelLevel = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 6)
private let agentPanelAnimation = NotchPanelAnimation.spring

private func prepareAgentOpenPanel(_ panel: NSOpenPanel) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    panel.level = agentOpenPanelLevel
}

private struct AgentSlashCommand: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbolName: String
}

struct AIChatView: View {
    @Default(.aiChatEnabled) private var aiChatEnabled

    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var manager = AIChatManager.shared
    @State private var draft: String = ""
    @State private var showsTrace: Bool = false
    @State private var inspectorMode: AgentInspectorMode?
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
        .init(id: "/knowledge", title: "知识库", subtitle: "查看资料；add 导入文件；seed 导入 GitHub 示例", symbolName: "books.vertical"),
        .init(id: "/kb", title: "知识库", subtitle: "同 /knowledge，可输入 add 或 seed", symbolName: "books.vertical"),
        .init(id: "/remember", title: "记住", subtitle: "把一句稳定偏好写入长期记忆", symbolName: "plus.circle"),
        .init(id: "/forget", title: "遗忘", subtitle: "按关键词删除长期记忆，留空则清空", symbolName: "minus.circle"),
        .init(id: "/file", title: "上传文件", subtitle: "把本地文本文件作为下一条消息上下文", symbolName: "paperclip"),
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
            } else if Defaults[.aiServiceAPIKey].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                featureDisabledState(
                    title: "缺少 API Key",
                    subtitle: "请在 设置 > AI 中填写 Base URL、模型和 API Key。"
                )
            } else {
                conversationTabs
                messagesPanel
                if let inspectorMode {
                    AgentInventoryPanel(mode: inspectorMode) {
                        self.inspectorMode = nil
                        isComposerFocused = true
                    }
                }
                if let trace = manager.lastAgentTrace {
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
        .onExitCommand {
            if inspectorMode != nil {
                inspectorMode = nil
                isComposerFocused = true
            }
        }
        .onAppear {
            vm.preventAutoClose = true
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)

            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                isComposerFocused = true
            }
        }
        .onDisappear {
            vm.preventAutoClose = false
            isComposerFocused = false

            if SettingsWindowController.shared.window?.isVisible != true {
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
                Text("Boring Notch Agent")
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
        inspectorMode = nil
        isComposerFocused = false
        vm.suppressHoverAutoOpen()

        withAnimation(agentPanelAnimation) {
            vm.close()
        }
    }

    private var conversationTabs: some View {
        HStack(spacing: 6) {
            Button {
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
                inspectorMode = inspectorMode == .knowledge ? nil : .knowledge
            } label: {
                Image(systemName: "books.vertical")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(inspectorMode == .knowledge ? Color.effectiveAccent : .secondary)
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
            if shouldShowSlashMenu {
                SlashCommandMenu(
                    commands: filteredSlashCommands,
                    onSelect: runSlashCommand
                )
            }

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
    }

    private var shouldShowSlashMenu: Bool {
        isComposerFocused && draft.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/")
    }

    private var filteredSlashCommands: [AgentSlashCommand] {
        let query = draft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard query.count > 1 else { return slashCommands }
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
        let command = slashCommands.first { lowered.hasPrefix($0.id) } ?? filteredSlashCommands.first
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
            inspectorMode = inspectorMode == .plugins ? nil : .plugins
            draft = ""
        case "/skills":
            inspectorMode = inspectorMode == .skills ? nil : .skills
            draft = ""
        case "/memory":
            if argument == "clear" {
                manager.clearLongTermMemory()
                manager.appendLocalAssistantMessage("已清空长期记忆。")
            } else if ["reveal", "open", "file"].contains(argument.lowercased()) {
                manager.revealLongTermMemoryFile()
                manager.appendLocalAssistantMessage("已在 Finder 中定位长期记忆文件。")
            } else {
                inspectorMode = inspectorMode == .memory ? nil : .memory
            }
            draft = ""
        case "/remember":
            if argument.isEmpty {
                draft = "/remember "
                isComposerFocused = true
            } else if let record = manager.rememberMemory(argument) {
                inspectorMode = .memory
                draft = ""
                manager.appendLocalAssistantMessage("已写入长期记忆：[\(record.kind.displayName)] \(record.content)")
            }
        case "/forget":
            let removedCount = manager.forgetMemory(matching: argument)
            inspectorMode = .memory
            draft = ""
            if argument.isEmpty {
                manager.appendLocalAssistantMessage("已清空长期记忆，共删除 \(removedCount) 条。")
            } else {
                manager.appendLocalAssistantMessage("已删除 \(removedCount) 条匹配“\(argument)”的长期记忆。")
            }
        case "/file":
            draft = ""
            openFilePicker(mode: .attach)
        case "/knowledge", "/kb":
            if ["add", "import", "导入", "添加"].contains(argument.lowercased()) {
                draft = ""
                openFilePicker(mode: .knowledge)
            } else if ["seed", "demo", "github", "示例", "样例"].contains(argument.lowercased()) {
                let count = manager.installStarterKnowledgeBase()
                inspectorMode = .knowledge
                draft = ""
                manager.appendLocalAssistantMessage("已导入 \(count) 份 GitHub/官方文档启发的示例知识库。")
            } else if ["clear", "清空"].contains(argument.lowercased()) {
                manager.clearKnowledgeBase()
                inspectorMode = .knowledge
                draft = ""
                manager.appendLocalAssistantMessage("已清空本地知识库。")
            } else {
                inspectorMode = inspectorMode == .knowledge ? nil : .knowledge
                draft = ""
            }
        case "/new":
            draft = ""
            attachedFiles.removeAll()
            inspectorMode = nil
            manager.startNewConversation()
        case "/chats":
            draft = ""
            attachedFiles.removeAll()
            inspectorMode = nil
            isComposerFocused = true
        case "/clear":
            draft = ""
            attachedFiles.removeAll()
            inspectorMode = nil
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
        prepareAgentOpenPanel(panel)

        guard panel.runModal() == .OK else { return }

        var importedKnowledgeTitles: [String] = []
        let maxFiles = mode == .knowledge ? 8 : 4

        for url in panel.urls.prefix(maxFiles) {
            do {
                let file = try readAgentImportableFile(at: url)

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
            inspectorMode = .knowledge
            if !importedKnowledgeTitles.isEmpty {
                manager.appendLocalAssistantMessage("已导入知识库：\(importedKnowledgeTitles.joined(separator: "、"))")
            }
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
    let onClose: () -> Void
    @ObservedObject private var manager = AIChatManager.shared
    @Default(.aiKnowledgeRetrievalEnabled) private var aiKnowledgeRetrievalEnabled
    @Default(.aiKnowledgeRetrievalLimit) private var aiKnowledgeRetrievalLimit
    @State private var selectedSkillCategory: String = "全部"
    @State private var knowledgeImportError: String?
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
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("关闭面板")
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
            .frame(maxHeight: 360)
        }
        .padding(10)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onAppear {
            if mode == .knowledge {
                manager.refreshKnowledgeDocuments()
            }
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

            if manager.longTermMemories.isEmpty {
                Text("还没有长期记忆。只有当用户明确说“记住/以后/我的偏好”等稳定信息时才会写入。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                ForEach(manager.longTermMemories.prefix(5)) { memory in
                    MemoryInventoryCard(memory: memory)
                }
            }

            HStack(spacing: 10) {
                Button("定位记忆文件") {
                    manager.revealLongTermMemoryFile()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)

                Button("清空长期记忆") {
                    manager.clearLongTermMemory()
                    manager.appendLocalAssistantMessage("已清空长期记忆。")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.red)
            }
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
                Text("还没有导入资料。使用 /knowledge add，或点击下面的“导入资料”按钮导入文本、Markdown、JSON、CSV 或 PDF。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                ForEach(manager.knowledgeDocuments.prefix(8)) { document in
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
        }
    }

    private func openKnowledgeImporter() {
        knowledgeImportError = nil
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = agentAllowedImportTypes()
        prepareAgentOpenPanel(panel)

        guard panel.runModal() == .OK else { return }

        var imported: [String] = []
        for url in panel.urls.prefix(8) {
            do {
                let file = try readAgentImportableFile(at: url)
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

private struct MemoryInventoryCard: View {
    let memory: AgentMemoryRecord

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
            .frame(maxWidth: 360, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant { Spacer(minLength: 36) }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        .padding(.horizontal, 10)
    }
}

private struct MarkdownMessageText: View {
    let content: String

    var body: some View {
        Text(attributedContent)
    }

    private var attributedContent: AttributedString {
        (try? AttributedString(markdown: content)) ?? AttributedString(content)
    }
}
