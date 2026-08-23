import SwiftUI

/// 设备互联：连接本机 Hermes AI 助手（OpenAI 兼容 API）
struct DeviceLinkView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = DeviceLinkStore.shared
    @State private var host = ""
    @State private var port = ""
    @State private var apiKey = ""
    @State private var connecting = false
    @State private var statusText = ""
    @State private var input = ""
    @State private var isSending = false

    private var baseURL: String { "http://\(host):\(port)" }

    /// 禁用系统代理直连（局域网设备互联不受 VPN/HTTP 代理干扰）
    private var directSession: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 180
        return URLSession(configuration: config)
    }

    var body: some View {
        NavigationStack {
            List {
                // 连接配置
                Section("连接信息") {
                    HStack {
                        Text("地址")
                        Spacer()
                        TextField("IP 地址", text: $host)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.secondary)
                            .disabled(store.isConnected)
                        Text(":")
                            .foregroundColor(.secondary)
                        TextField("端口", text: $port)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.secondary)
                            .disabled(store.isConnected)
                    }
                    HStack {
                        Text("密钥")
                        Spacer()
                        TextField("API Key", text: $apiKey)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.secondary)
                            .disabled(store.isConnected)
                    }
                    // 快捷地址：局域网 / Tailscale（VPN 互通）
                    if !store.isConnected {
                        HStack(spacing: 8) {
                            Text("快捷")
                            Spacer()
                            Button("局域网 172.11.8.35") {
                                host = "172.11.8.35"
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            Button("Tailscale 100.101.164.60") {
                                host = "100.101.164.60"
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        Text("同一 Wi-Fi 用局域网；异地 / VPN 用 Tailscale（需本机已登录）")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if store.isConnected {
                        HStack {
                            Text("状态")
                            Spacer()
                            Label("已连接", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        }
                        if !store.modelName.isEmpty {
                            HStack {
                                Text("模型")
                                Spacer()
                                Text(store.modelName)
                                    .font(.caption.monospaced())
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // 连接/断开按钮
                Section {
                    Button(action: store.isConnected ? disconnect : connect) {
                        HStack {
                            Spacer()
                            if connecting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Label(store.isConnected ? "断开连接" : "连接设备",
                                      systemImage: store.isConnected ? "minus.circle" : "link")
                            }
                            Spacer()
                        }
                        .foregroundColor(store.isConnected ? .red : Theme.primary)
                    }
                    .disabled(connecting || host.isEmpty)
                }

                // 对话区（自动滚动到最新消息）
                if store.isConnected {
                    Section {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: 8) {
                                    ForEach(store.messages) { msg in
                                        VStack(alignment: msg.isUser ? .trailing : .leading, spacing: 4) {
                                            Text(msg.isUser ? "你" : "Hermes")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            Text(msg.content)
                                                .font(.body)
                                                .foregroundColor(.primary)
                                                .textSelection(.enabled)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                                .background(msg.isUser ? Color.accentColor.opacity(0.15) : Color(.tertiarySystemFill))
                                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                        }
                                        .id(msg.id)
                                    }
                                    if isSending {
                                        HStack {
                                            ProgressView()
                                                .scaleEffect(0.7)
                                            Text("思考中...")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        .id("sending")
                                    }
                                }
                                .padding(.horizontal, 4)
                            }
                            .frame(minHeight: 200)
                            .onChange(of: store.messages.count) { _ in
                                withAnimation {
                                    if let last = store.messages.last {
                                        proxy.scrollTo(last.id, anchor: .bottom)
                                    }
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    } header: {
                        Text("AI 对话（Hermes）")
                    }

                    Section {
                        HStack {
                            TextField("输入消息...", text: $input)
                                .textFieldStyle(.plain)
                            Button("发送") {
                                sendMessage()
                            }
                            .font(.body.weight(.semibold))
                            .foregroundColor(Theme.primary)
                            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
                        }
                    }
                }

                if !statusText.isEmpty {
                    Section {
                        Text(statusText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("设备互联")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .onAppear {
            // 从 store 恢复配置（持久化的地址/密钥/连接状态）
            host = store.host
            port = store.port
            apiKey = store.apiKey
        }
        .onDisappear {
            // 保存配置
            store.host = host
            store.port = port
            store.apiKey = apiKey
            store.save()
        }
    }

    private func connect() {
        connecting = true
        statusText = "正在连接..."
        let url = "\(baseURL)/v1/models"
        guard let requestURL = URL(string: url) else {
            statusText = "无效的地址"
            connecting = false
            return
        }
        var req = URLRequest(url: requestURL)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10
        directSession.dataTask(with: req) { data, _, error in
            DispatchQueue.main.async {
                connecting = false
                if let error = error {
                    statusText = "连接失败: \(error.localizedDescription)"
                    return
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let models = json["data"] as? [[String: Any]] else {
                    statusText = "连接失败: 响应格式错误"
                    return
                }
                store.isConnected = true
                store.modelName = models.first?["id"] as? String ?? "Hermes"
                statusText = "已连接 \(store.modelName)"
                // 默认问候
                if store.messages.isEmpty {
                    store.messages = [ChatMsg(content: "已连接到 Hermes Agent（\(store.modelName)），可以开始对话了 ✨", isUser: false)]
                    store.lastMessageTime = Date()
                }
                store.save()
            }
        }.resume()
    }

    private func disconnect() {
        store.isConnected = false
        store.modelName = ""
        store.messages = []
        statusText = "已断开"
        store.save()
    }

    private func sendMessage() {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        input = ""
        let userMsg = ChatMsg(content: text, isUser: true)
        store.messages.append(userMsg)
        store.lastMessageTime = Date()
        store.save()
        isSending = true

        let payload: [String: Any] = [
            "model": "hermes-agent",
            "messages": store.messages.map { ["role": $0.isUser ? "user" : "assistant", "content": $0.content] }
        ]
        guard let url = URL(string: "\(baseURL)/v1/chat/completions"),
              let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 120

        directSession.dataTask(with: req) { data, _, error in
            DispatchQueue.main.async {
                isSending = false
                let appendAndSave: (ChatMsg) -> Void = { msg in
                    store.messages.append(msg)
                    store.lastMessageTime = Date()
                    store.save()
                }
                if let error = error {
                    appendAndSave(ChatMsg(content: "请求失败: \(error.localizedDescription)", isUser: false))
                    return
                }
                guard let data = data,
                      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    // 显示原始响应片段，便于诊断
                    let raw = data.map { String(data: $0, encoding: .utf8) ?? "非文本响应" } ?? "无响应数据"
                    appendAndSave(ChatMsg(content: "响应解析失败（原始: \(String(raw.prefix(200)))）", isUser: false))
                    return
                }
                // OpenAI 错误信封
                if let err = json["error"] as? [String: Any],
                   let errMsg = err["message"] as? String {
                    appendAndSave(ChatMsg(content: "Hermes 错误: \(errMsg)", isUser: false))
                    return
                }
                guard let choices = json["choices"] as? [[String: Any]],
                      let msg = choices.first?["message"] as? [String: Any] else {
                    appendAndSave(ChatMsg(content: "响应格式异常: \(String(describing: json).prefix(200))", isUser: false))
                    return
                }
                // content 可能为 null（纯工具调用/思考），宽容处理
                if let content = msg["content"] as? String, !content.isEmpty {
                    appendAndSave(ChatMsg(content: content, isUser: false))
                } else if let reasoning = msg["reasoning_content"] as? String, !reasoning.isEmpty {
                    appendAndSave(ChatMsg(content: "（思考中）\(reasoning)", isUser: false))
                } else {
                    appendAndSave(ChatMsg(content: "（Hermes 无文本输出，可能正在调用工具）", isUser: false))
                }
            }
        }.resume()
    }
}

struct ChatMsg: Identifiable {
    let id = UUID()
    let content: String
    let isUser: Bool
}