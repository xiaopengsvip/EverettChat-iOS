import SwiftUI

/// 设备互联：连接本机 Hermes + 进入完整对话（复用 ChatView 全部能力：图片/文件/语音/附件）
struct DeviceLinkView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = DeviceLinkStore.shared
    @State private var host = ""
    @State private var port = ""
    @State private var apiKey = ""
    @State private var connecting = false
    @State private var statusText = ""

    private var baseURL: String { "http://\(host):\(port)" }

    private var directSession: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("连接信息") {
                    HStack {
                        Text("地址")
                        Spacer()
                        TextField("IP 地址", text: $host)
                            .multilineTextAlignment(.trailing).foregroundColor(.secondary)
                            .disabled(store.isConnected)
                        Text(":").foregroundColor(.secondary)
                        TextField("端口", text: $port)
                            .frame(width: 60).multilineTextAlignment(.trailing).foregroundColor(.secondary)
                            .disabled(store.isConnected)
                    }
                    HStack {
                        Text("密钥")
                        Spacer()
                        TextField("API Key", text: $apiKey)
                            .multilineTextAlignment(.trailing).foregroundColor(.secondary)
                            .disabled(store.isConnected)
                    }
                    if !store.isConnected {
                        HStack(spacing: 8) {
                            Text("快捷")
                            Spacer()
                            Button("局域网 172.11.8.35") { host = "172.11.8.35" }
                                .buttonStyle(.bordered).controlSize(.small)
                            Button("Tailscale 100.101.164.60") { host = "100.101.164.60" }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                        Text("同一 Wi-Fi 用局域网；异地 / VPN 用 Tailscale")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    if store.isConnected {
                        HStack {
                            Text("状态")
                            Spacer()
                            Label("已连接", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green).font(.caption)
                        }
                        if !store.modelName.isEmpty {
                            HStack {
                                Text("模型")
                                Spacer()
                                Text(store.modelName).font(.caption.monospaced()).foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Button(action: store.isConnected ? disconnect : connect) {
                        HStack {
                            Spacer()
                            if connecting { ProgressView().scaleEffect(0.8) }
                            else { Label(store.isConnected ? "断开连接" : "连接设备",
                                         systemImage: store.isConnected ? "minus.circle" : "link") }
                            Spacer()
                        }
                        .foregroundColor(store.isConnected ? .red : Theme.primary)
                    }
                    .disabled(connecting || host.isEmpty)
                }

                if store.isConnected {
                    Section {
                        Button {
                            appState.openDeviceChat()
                            dismiss()
                        } label: {
                            HStack {
                                Spacer()
                                Label("进入对话", systemImage: "bubble.left.and.bubble.right")
                                    .font(.body.weight(.semibold))
                                Spacer()
                            }
                            .foregroundColor(.white)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 20)
                            .background(Theme.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                }

                if !statusText.isEmpty {
                    Section {
                        Text(statusText).font(.caption).foregroundColor(.secondary)
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
            .onAppear {
                host = store.host; port = store.port; apiKey = store.apiKey
            }
            .onDisappear {
                store.host = host; store.port = port; store.apiKey = apiKey; store.save()
            }
        }
    }

    private func connect() {
        connecting = true
        statusText = "正在连接..."
        guard let requestURL = URL(string: "\(baseURL)/v1/models") else {
            statusText = "无效的地址"; connecting = false; return
        }
        var req = URLRequest(url: requestURL)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10
        directSession.dataTask(with: req) { data, _, error in
            DispatchQueue.main.async {
                connecting = false
                if let error = error { statusText = "连接失败: \(error.localizedDescription)"; return }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let models = json["data"] as? [[String: Any]] else {
                    statusText = "连接失败: 响应格式错误"; return
                }
                store.isConnected = true
                store.modelName = models.first?["id"] as? String ?? "Hermes"
                store.host = host; store.port = port; store.apiKey = apiKey
                store.save()
                statusText = "已连接 \(store.modelName)"
            }
        }.resume()
    }

    private func disconnect() {
        store.isConnected = false
        store.modelName = ""
        statusText = "已断开"
        store.save()
    }
}