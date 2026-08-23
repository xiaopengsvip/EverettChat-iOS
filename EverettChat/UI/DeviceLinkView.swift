import SwiftUI

/// 设备互联：连接本机 Hermes AI 助手（OpenAI 兼容 API）
struct DeviceLinkView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var host = "172.11.8.35"
    @State private var port = "8642"
    @State private var apiKey = "evt-0a064c103a11512f7781bf6f999bf1fe"
    @State private var isConnected = false
    @State private var connecting = false
    @State private var statusText = ""
    @State private var modelName = ""
    @State private var messages: [ChatMsg] = []
    @State private var input = ""
    @State private var isSending = false

    private var baseURL: String { "http://\(host):\(port)" }

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
                            .disabled(isConnected)
                        Text(":")
                            .foregroundColor(.secondary)
                        TextField("端口", text: $port)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.secondary)
                            .disabled(isConnected)
                    }
                    HStack {
                        Text("密钥")
                        Spacer()
                        TextField("API Key", text: $apiKey)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.secondary)
                            .disabled(isConnected)
                    }
                    if isConnected {
                        HStack {
                            Text("状态")
                            Spacer()
                            Label("已连接", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        }
                        if !modelName.isEmpty {
                            HStack {
                                Text("模型")
                                Spacer()
                                Text(modelName)
                                    .font(.caption.monospaced())
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // 连接/断开按钮
                Section {
                    Button(action: isConnected ? disconnect : connect) {
                        HStack {
                            Spacer()
                            if connecting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Label(isConnected ? "断开连接" : "连接设备",
                                      systemImage: isConnected ? "minus.circle" : "link")
                            }
                            Spacer()
                        }
                        .foregroundColor(isConnected ? .red : Theme.primary)
                    }
                    .disabled(connecting || host.isEmpty)
                }

                // 对话区
                if isConnected {
                    Section("AI 对话（Hermes）") {
                        ForEach(messages) { msg in
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
                        }
                        if isSending {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("思考中...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
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
        URLSession.shared.dataTask(with: req) { data, _, error in
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
                isConnected = true
                modelName = models.first?["id"] as? String ?? "Hermes"
                statusText = "已连接 \(modelName)"
                // 默认问候
                messages = [ChatMsg(content: "已连接到 Hermes Agent（\(modelName)），可以开始对话了 ✨", isUser: false)]
            }
        }.resume()
    }

    private func disconnect() {
        isConnected = false
        modelName = ""
        messages = []
        statusText = "已断开"
    }

    private func sendMessage() {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        input = ""
        let userMsg = ChatMsg(content: text, isUser: true)
        messages.append(userMsg)
        isSending = true

        let payload: [String: Any] = [
            "model": "hermes-agent",
            "messages": messages.map { ["role": $0.isUser ? "user" : "assistant", "content": $0.content] }
        ]
        guard let url = URL(string: "\(baseURL)/v1/chat/completions"),
              let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 120

        URLSession.shared.dataTask(with: req) { data, _, error in
            DispatchQueue.main.async {
                isSending = false
                if let error = error {
                    messages.append(ChatMsg(content: "请求失败: \(error.localizedDescription)", isUser: false))
                    return
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let msg = choices.first?["message"] as? [String: Any],
                      let content = msg["content"] as? String else {
                    messages.append(ChatMsg(content: "响应解析失败", isUser: false))
                    return
                }
                messages.append(ChatMsg(content: content, isUser: false))
            }
        }.resume()
    }
}

struct ChatMsg: Identifiable {
    let id = UUID()
    let content: String
    let isUser: Bool
}