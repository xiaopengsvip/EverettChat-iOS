import SwiftUI

/// 聊天页（AI / 对端，Document Style + 思考折叠 + 模型选择）
struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @State private var input = ""
    @State private var isStreaming = false
    @State private var showModelSheet = false
    @State private var selectedModel = ApiConfig.model
    @State private var showReasoning = false
    @State private var messages: [ChatMessage] = []
    @State private var scrollProxy: ScrollViewProxy?
    @State private var showInfoSheet = false

    private var isAI: Bool { appState.chatMode == "ai" }
    private let apiClient = ChatApiClient()

    var body: some View {
        VStack(spacing: 0) {
            // 顶栏：返回 + 标题 + 副标题（模型名/ID）+ ℹ️
            HStack(spacing: Spacing.sm) {
                Button {
                    appState.showChat = false
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(Theme.textPrimary)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(isAI ? "AI 助手" : appState.chatPeerName)
                        .font(.headline)
                        .foregroundColor(Theme.textPrimary)
                    Text(isAI ? currentModelName : "ID: \(String(appState.chatPeerId.prefix(8)))")
                        .font(.caption2)
                        .foregroundColor(Theme.textTertiary)
                }
                Spacer()
                Button {
                    showInfoSheet = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 18))
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)

            Divider().overlay(Theme.surfaceHigh)

            // 消息列表
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        // 顶部提示
                        Text(isAI ? "🤖 与 AI 助手对话 · 经云端中继" : "🔐 端到端加密 · 消息仅双方可见")
                            .font(.caption2)
                            .foregroundColor(Theme.textTertiary)
                            .padding(.vertical, 4)

                        ForEach(messages) { msg in
                            MessageBubble(
                                msg: msg,
                                isMine: msg.role == "user",
                                isAI: msg.role == "ai",
                                deviceName: appState.deviceName
                            )
                            .id(msg.id)
                        }
                        if isStreaming {
                            MessageBubble(
                                msg: ChatMessage(role: "ai", text: streamContent, reasoning: streamReasoning),
                                isMine: false, isAI: true, deviceName: appState.deviceName
                            )
                            .id("streaming")
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                }
                .onChange(of: messages.count) { _ in
                    withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
                }
                .onChange(of: streamContent) { _ in
                    withAnimation { proxy.scrollTo("streaming", anchor: .bottom) }
                }
            }

            // 输入区
            VStack(spacing: 0) {
                if isAI {
                    HStack(spacing: Spacing.sm) {
                        Button {
                            showModelSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Text("\(currentModelIcon) \(currentModelName) ▾")
                                    .font(.caption)
                                    .foregroundColor(Theme.primary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Theme.primary.opacity(0.15))
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.primary.opacity(0.35), lineWidth: 1))
                            )
                        }
                        Text("切换模型")
                            .font(.caption2)
                            .foregroundColor(Theme.textTertiary)
                        Spacer()
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, 4)
                }

                HStack(spacing: Spacing.sm) {
                    Button {
                        // 附件
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18))
                            .foregroundColor(Theme.textSecondary)
                            .frame(width: 40, height: 40)
                    }
                    TextField(isAI ? "向 AI 提问..." : "加密消息给 \(appState.chatPeerName)...", text: $input)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 20).fill(Theme.surfaceHigh))
                        .submitLabel(.send)
                        .onSubmit { send() }
                    Button {
                        send()
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(input.isEmpty ? Theme.surfaceAlt : Theme.primary))
                    }
                    .disabled(input.isEmpty)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
            }
            .background(Theme.glass)
        }
        .background(Theme.bg)
        .sheet(isPresented: $showModelSheet) { ModelPickerSheet(selected: $selectedModel) }
        .sheet(isPresented: $showInfoSheet) { ChatInfoSheet(isAI: isAI) }
        .onAppear {
            messages = isAI ? appState.aiMessages : appState.peerMessages
        }
        .onDisappear {
            if isAI { appState.aiMessages = messages } else { appState.peerMessages = messages }
        }
    }

    private var currentModel: ApiConfig.ModelInfo {
        ApiConfig.models.first { $0.id == selectedModel } ?? ApiConfig.models[0]
    }
    private var currentModelName: String { currentModel.name }
    private var currentModelIcon: String { currentModel.vision ? "👁" : "🤖" }
    private var streamContent: String { apiClient.streamText }
    private var streamReasoning: String { apiClient.reasoningText }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        input = ""

        let userMsg = ChatMessage(role: "user", text: text)
        messages.append(userMsg)

        if isAI {
            sendAI(text)
        } else {
            // 对端加密发送
            appState.transport.sendText(text, target: appState.chatPeerId)
        }
    }

    private func sendAI(_ text: String) {
        isStreaming = true
        let history = messages.dropLast().map { (role: $0.role == "user" ? "user" : "assistant", content: $0.text) }
        Task {
            let result = await apiClient.sendMessage(
                history: history,
                userMessage: text,
                model: selectedModel,
                onDelta: { delta, isReasoning in
                    Task { @MainActor in
                        if isReasoning {
                            // 思考过程（暂不显示在气泡，折叠用）
                        } else {
                            // 流式追加
                            if let last = messages.last, last.role == "ai" {
                                messages[messages.count - 1] = ChatMessage(
                                    id: last.id, role: "ai", text: last.text + delta,
                                    reasoning: last.reasoning
                                )
                            } else {
                                messages.append(ChatMessage(role: "ai", text: delta))
                            }
                        }
                    }
                }
            )
            isStreaming = false
            if result == nil || result?.isEmpty == true {
                messages.append(ChatMessage(role: "ai", text: "（无回复）", isError: true))
            }
        }
    }
}

/// 消息气泡
struct MessageBubble: View {
    let msg: ChatMessage
    let isMine: Bool
    let isAI: Bool
    let deviceName: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // 左头像列（对方）
            if !isMine {
                Circle()
                    .fill(isAI ? Theme.primaryDim : Theme.surfaceAlt)
                    .frame(width: 36, height: 36)
                    .overlay(Text(isAI ? "🤖" : "👤").font(.system(size: 18)))
            } else {
                Color.clear.frame(width: 44, height: 44)
            }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 3) {
                if isMine {
                    Text("我 · \(deviceName)")
                        .font(.caption2)
                        .foregroundColor(Theme.textTertiary)
                } else {
                    Text(isAI ? "AI 助手" : msg.senderName)
                        .font(.caption2)
                        .foregroundColor(isAI ? Theme.info : Theme.textTertiary)
                }

                // 气泡内容
                if isAI {
                    VStack(alignment: .leading, spacing: 4) {
                        if !msg.reasoning.isEmpty {
                            Text("🤔 思考过程 ▸")
                                .font(.caption2)
                                .foregroundColor(Theme.textTertiary)
                        }
                        Text(msg.text)
                            .font(.body)
                            .foregroundColor(Theme.textPrimary)
                            .textSelection(.enabled)
                    }
                    .padding(10)
                    .frame(maxWidth: 320, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.medium)
                            .fill(Theme.bubbleAi)
                    )
                } else {
                    Text(msg.text)
                        .font(.body)
                        .foregroundColor(isMine ? .white : Theme.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(isMine ? Theme.bubbleMine : Theme.bubblePeer)
                        )
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)

            // 右头像列（自己）
            if isMine {
                Circle()
                    .fill(Theme.surfaceAlt)
                    .frame(width: 36, height: 36)
                    .overlay(Text("👤").font(.system(size: 18)))
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
    }
}

/// 模型选择 Sheet
struct ModelPickerSheet: View {
    @Binding var selected: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("选择模型")
                .font(.headline)
                .padding(Spacing.xl)
            ForEach(ApiConfig.models) { m in
                Button {
                    selected = m.id
                    dismiss()
                } label: {
                    HStack(spacing: 14) {
                        Text(m.vision ? "👁" : "🤖").font(.title3)
                        VStack(alignment: .leading) {
                            Text(m.name)
                                .font(.body.weight(selected == m.id ? .semibold : .regular))
                                .foregroundColor(selected == m.id ? Theme.primary : Theme.textPrimary)
                            Text(m.desc)
                                .font(.caption)
                                .foregroundColor(Theme.textTertiary)
                        }
                        Spacer()
                        if selected == m.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Theme.primary)
                        }
                    }
                    .padding(Spacing.lg)
                }
                Divider().overlay(Theme.surfaceHigh).padding(.leading, 56)
            }
            Spacer()
        }
        .background(Theme.surface)
        .presentationDetents([.height(260)])
    }
}

/// 会话信息 Sheet
struct ChatInfoSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let isAI: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Circle()
                    .fill(isAI ? Theme.primaryDim : Theme.surfaceAlt)
                    .frame(width: 52, height: 52)
                    .overlay(Text(isAI ? "🤖" : "👤").font(.title3))
                VStack(alignment: .leading) {
                    Text(isAI ? "AI 助手" : appState.chatPeerName)
                        .font(.headline)
                        .foregroundColor(Theme.textPrimary)
                    Text(isAI ? "云端 AI · 非端到端加密" : "ID: \(appState.chatPeerId)")
                        .font(.caption2.monospaced())
                        .foregroundColor(Theme.textTertiary)
                }
                Spacer()
            }
            .padding(Spacing.xl)

            Divider().overlay(Theme.surfaceHigh)

            if isAI {
                InfoRow(icon: "🤖", title: "当前模型", subtitle: "DeepSeek V4")
                InfoRow(icon: "🔐", title: "加密说明", subtitle: "AI 对话经云端中继代理，非端到端加密")
                Button {
                    appState.aiMessages.removeAll()
                    dismiss()
                } label: {
                    InfoRow(icon: "🧹", title: "清除对话", subtitle: "清空当前 AI 会话历史")
                }
            } else {
                InfoRow(icon: "🔗", title: "连接状态", subtitle: "中继连接")
                InfoRow(icon: "🔐", title: "加密说明", subtitle: "端到端加密 · 消息仅双方可见")
            }
            Spacer()
        }
        .background(Theme.surface)
        .presentationDetents([.height(320)])
    }
}

struct InfoRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Text(icon).font(.body)
            VStack(alignment: .leading) {
                Text(title).font(.body).foregroundColor(Theme.textPrimary)
                Text(subtitle).font(.caption).foregroundColor(Theme.textTertiary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(Theme.textTertiary)
        }
        .padding(Spacing.lg)
    }
}
