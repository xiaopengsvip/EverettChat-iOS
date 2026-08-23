import SwiftUI

/// 全局浮窗聊天（AI 助手 / 好友会话 / Hermes 设备）
/// 可拖动位置、切换大小（小/中/大）、收起为悬浮球、随时回复
struct FloatingChatView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var manager = FloatingChatManager.shared
    @StateObject private var deviceStore = DeviceLinkStore.shared

    // AI 流式
    @StateObject private var aiClient = ChatApiClient()
    @State private var aiInput = ""
    @State private var isAiStreaming = false
    @State private var aiStreamBuf = ""

    // 对端会话
    @State private var peerInput = ""

    // Hermes 设备
    @State private var deviceInput = ""
    @State private var isDeviceSending = false
    @State private var deviceStatus = ""

    private var directSession: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 180
        return URLSession(configuration: config)
    }

    // 浮窗尺寸（基于屏幕）
    private var windowWidth: CGFloat {
        UIScreen.main.bounds.width * manager.size.rawValue
    }
    private var windowHeight: CGFloat {
        UIScreen.main.bounds.height * (manager.size == .small ? 0.42 : manager.size == .medium ? 0.6 : 0.85)
    }
    private var minimizedSize: CGFloat { 64 }

    var body: some View {
        ZStack {
            if manager.isShowing {
                if manager.isMinimized {
                    minimizedBubble
                        .frame(width: minimizedSize, height: minimizedSize)
                        .position(floatingPosition)
                        .gesture(dragGesture)
                        .onTapGesture { manager.expand() }
                        .transition(.scale.combined(with: .opacity))
                } else {
                    fullWindow
                        .frame(width: windowWidth, height: windowHeight)
                        .position(floatingPosition)
                        .gesture(dragGesture)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: manager.isMinimized)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: manager.size)
    }

    // MARK: - 悬浮位置（屏幕内约束）
    private var floatingPosition: CGPoint {
        let screen = UIScreen.main.bounds
        let w = manager.isMinimized ? minimizedSize : windowWidth
        let h = manager.isMinimized ? minimizedSize : windowHeight
        let baseX = screen.width - w / 2 - 12
        let baseY = screen.height - h / 2 - 60   // 底部避让 TabBar
        let x = min(max(baseX + manager.offset.width + manager.dragOffset.width, w / 2), screen.width - w / 2)
        let y = min(max(baseY + manager.offset.height + manager.dragOffset.height, h / 2 + 40), screen.height - h / 2 - 20)
        return CGPoint(x: x, y: y)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { v in
                manager.dragOffset = v.translation
            }
            .onEnded { v in
                manager.offset.width += v.translation.width
                manager.offset.height += v.translation.height
                manager.dragOffset = .zero
            }
    }

    // MARK: - 悬浮球（收起态）
    private var minimizedBubble: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
            Image(systemName: manager.icon)
                .font(.system(size: 22))
                .foregroundColor(Theme.primary)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                manager.close()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .background(Circle().fill(.background))
            }
            .offset(x: 6, y: -6)
        }
    }

    // MARK: - 完整浮窗
    private var fullWindow: some View {
        VStack(spacing: 0) {
            header
            Divider()
            chatContent
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
    }

    // MARK: - 标题栏
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: manager.icon)
                .font(.system(size: 15))
                .foregroundColor(Theme.primary)
            Text(manager.title)
                .font(.headline)
                .lineLimit(1)
            Spacer()

            // 大小切换（小/中/大）
            Button { manager.cycleSize() } label: {
                Image(systemName: sizeIcon)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("切换大小")

            // 收起
            Button { manager.minimize() } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            // 关闭
            Button { manager.close() } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var sizeIcon: String {
        switch manager.size {
        case .small: return "arrow.up.left.and.arrow.down.right"
        case .medium: return "arrow.up.left.and.arrow.down.right"
        case .large: return "arrow.down.right.and.arrow.up.left"
        }
    }

    // MARK: - 聊天内容（按目标切换）
    @ViewBuilder
    private var chatContent: some View {
        switch manager.target {
        case .ai:
            aiChat
        case .peer:
            peerChat
        case .device:
            deviceChat
        }
    }

    // MARK: - AI 会话
    private var aiChat: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(appState.aiMessages) { msg in
                            miniBubble(msg: msg)
                                .id(msg.id)
                        }
                        // 流式占位（固定 id，避免闪烁）
                        if isAiStreaming {
                            miniBubble(msg: ChatMessage(role: "ai", text: aiStreamBuf, senderId: ""))
                                .id("streaming")
                        }
                    }
                    .padding(10)
                }
                .onChange(of: appState.aiMessages.count) { _ in
                    withAnimation { proxy.scrollTo(appState.aiMessages.last?.id, anchor: .bottom) }
                }
                .onChange(of: aiStreamBuf) { _ in
                    withAnimation { proxy.scrollTo("streaming", anchor: .bottom) }
                }
            }

            // 输入区
            HStack(spacing: 8) {
                TextField("输入消息...", text: $aiInput)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                Button {
                    sendAI()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(Theme.primary)
                }
                .buttonStyle(.plain)
                .disabled(aiInput.trimmingCharacters(in: .whitespaces).isEmpty || isAiStreaming)
            }
            .padding(10)
        }
    }

    private func sendAI() {
        let text = aiInput.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !isAiStreaming else { return }
        aiInput = ""
        let userMsg = ChatMessage(role: "user", text: text, senderId: "")
        appState.aiMessages.append(userMsg)
        isAiStreaming = true
        aiStreamBuf = ""

        let history = appState.aiMessages
            .filter { $0.role == "user" || $0.role == "ai" }
            .map { (role: $0.role == "user" ? "user" : "assistant", content: $0.text) }
            .dropLast()

        Task {
            let reply = await aiClient.sendMessage(
                history: Array(history),
                userMessage: text,
                model: ApiConfig.model
            ) { delta, isReasoning in
                DispatchQueue.main.async {
                    aiStreamBuf += delta
                }
            }
            await MainActor.run {
                isAiStreaming = false
                if let reply, !reply.isEmpty {
                    appState.aiMessages.append(ChatMessage(role: "ai", text: reply, senderId: ""))
                }
                aiStreamBuf = ""
            }
        }
    }

    // MARK: - 对端会话
    private var peerChat: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        let peerId = peerTargetId
                        let msgs = appState.peerMessages.filter { $0.senderId == peerId }
                        ForEach(msgs) { msg in
                            miniBubble(msg: msg)
                                .id(msg.id)
                        }
                    }
                    .padding(10)
                }
                .onChange(of: appState.peerMessages.count) { _ in
                    withAnimation {
                        let last = appState.peerMessages.last(where: { $0.senderId == peerTargetId })
                        proxy.scrollTo(last?.id, anchor: .bottom)
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("回复 \(manager.title)...", text: $peerInput)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                Button {
                    sendPeer()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(Theme.primary)
                }
                .buttonStyle(.plain)
                .disabled(peerInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(10)
        }
    }

    /// 当前浮窗对端会话 id（不依赖主聊天页状态）
    private var peerTargetId: String {
        if case .peer(let id, _) = manager.target { return id }
        return ""
    }

    private func sendPeer() {
        let id = peerTargetId
        guard !id.isEmpty else { return }
        let text = peerInput.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        peerInput = ""
        // 与 ChatView 一致：自己的消息 senderId 用对端 id，保证会话过滤可见
        let msg = ChatMessage(role: "user", text: text, senderId: id)
        appState.peerMessages.append(msg)
        appState.conn.sendText(text, target: id, messageId: msg.id)
    }

    // MARK: - Hermes 设备会话
    private var deviceChat: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(deviceStore.messages) { msg in
                            HStack {
                                if msg.isUser { Spacer(minLength: 24) }
                                Text(msg.content)
                                    .font(.footnote)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(msg.isUser ? Color.accentColor.opacity(0.15) : Color(.tertiarySystemFill))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                if !msg.isUser { Spacer(minLength: 24) }
                            }
                            .id(msg.id)
                        }
                        if isDeviceSending {
                            HStack {
                                ProgressView().scaleEffect(0.6)
                                Text("Hermes 思考中...").font(.caption2).foregroundColor(.secondary)
                            }
                            .id("dstreaming")
                        }
                    }
                    .padding(10)
                }
                .onChange(of: deviceStore.messages.count) { _ in
                    withAnimation { proxy.scrollTo(deviceStore.messages.last?.id, anchor: .bottom) }
                }
            }

            HStack(spacing: 8) {
                TextField("问 Hermes...", text: $deviceInput)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                Button {
                    sendDevice()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(Theme.primary)
                }
                .buttonStyle(.plain)
                .disabled(deviceInput.trimmingCharacters(in: .whitespaces).isEmpty || isDeviceSending)
            }
            .padding(10)

            if !deviceStatus.isEmpty {
                Text(deviceStatus)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
            }
        }
    }

    private func sendDevice() {
        let text = deviceInput.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !isDeviceSending else { return }
        deviceInput = ""
        deviceStore.messages.append(ChatMsg(content: text, isUser: true))
        deviceStore.lastMessageTime = Date()
        isDeviceSending = true
        deviceStatus = ""

        let payload: [String: Any] = [
            "model": "hermes-agent",
            "messages": deviceStore.messages.map { ["role": $0.isUser ? "user" : "assistant", "content": $0.content] }
        ]
        guard let url = URL(string: "http://\(deviceStore.host):\(deviceStore.port)/v1/chat/completions"),
              let body = try? JSONSerialization.data(withJSONObject: payload) else {
            isDeviceSending = false
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue("Bearer \(deviceStore.apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 120

        directSession.dataTask(with: req) { data, _, error in
            DispatchQueue.main.async {
                isDeviceSending = false
                if let error = error {
                    deviceStatus = "请求失败: \(error.localizedDescription)"
                    return
                }
                guard let data = data,
                      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let msg = choices.first?["message"] as? [String: Any],
                      let content = msg["content"] as? String, !content.isEmpty else {
                    deviceStatus = "响应解析失败"
                    return
                }
                deviceStore.messages.append(ChatMsg(content: content, isUser: false))
                deviceStore.lastMessageTime = Date()
                deviceStore.save()
            }
        }.resume()
    }

    // MARK: - 迷你气泡
    private func miniBubble(msg: ChatMessage) -> some View {
        let isMine = msg.role == "user"
        return HStack {
            if isMine { Spacer(minLength: 28) }
            Text(msg.text)
                .font(.footnote)
                .foregroundColor(isMine ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(isMine ? Theme.primary : Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            if !isMine { Spacer(minLength: 28) }
        }
    }
}
