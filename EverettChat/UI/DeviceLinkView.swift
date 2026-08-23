import SwiftUI

/// 设备互联：多设备管理
/// 1. Hermes 设备（本机 AI，OpenAI 兼容 API）
/// 2. 音频设备（蓝牙耳机/有线耳机/扬声器检测与切换）
/// 3. BLE 设备扫描（智能硬件/外设）
struct DeviceLinkView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = DeviceLinkStore.shared
    @StateObject private var deviceMgr = DeviceManager.shared
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
                // ============ 1. Hermes 设备 ============
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Theme.primary.opacity(0.15))
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 20))
                                .foregroundColor(Theme.primary)
                        }
                        .frame(width: 42, height: 42)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hermes 设备")
                                .font(.body.weight(.semibold))
                                .foregroundColor(.primary)
                            Text(store.isConnected ? "已连接 · \(store.modelName)" : "本机 AI 助手（未连接）")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if store.isConnected {
                            Label("在线", systemImage: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("AI 设备")
                }

                // Hermes 连接配置（未连接时显示）
                if !store.isConnected {
                    Section("连接 Hermes") {
                        HStack {
                            Text("地址")
                            Spacer()
                            TextField("IP 地址", text: $host)
                                .multilineTextAlignment(.trailing).foregroundColor(.secondary)
                            Text(":").foregroundColor(.secondary)
                            TextField("端口", text: $port)
                                .frame(width: 60).multilineTextAlignment(.trailing).foregroundColor(.secondary)
                        }
                        HStack {
                            Text("密钥")
                            Spacer()
                            TextField("API Key", text: $apiKey)
                                .multilineTextAlignment(.trailing).foregroundColor(.secondary)
                        }
                        HStack(spacing: 8) {
                            Text("快捷")
                            Spacer()
                            Button("局域网 172.11.8.35") { host = "172.11.8.35" }
                                .buttonStyle(.bordered).controlSize(.small)
                            Button("Tailscale") { host = "100.101.164.60" }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                        Button(action: connect) {
                            HStack {
                                Spacer()
                                if connecting { ProgressView().scaleEffect(0.8) }
                                else { Label("连接设备", systemImage: "link") }
                                Spacer()
                            }
                            .foregroundColor(Theme.primary)
                        }
                        .disabled(connecting || host.isEmpty)
                    }
                } else {
                    Section {
                        Button {
                            appState.openDeviceChat()
                            dismiss()
                        } label: {
                            HStack {
                                Spacer()
                                Label("进入 Hermes 对话", systemImage: "bubble.left.and.bubble.right")
                                    .font(.body.weight(.semibold))
                                Spacer()
                            }
                            .foregroundColor(.white)
                            .padding(.vertical, 8)
                            .background(Theme.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())

                        Button(role: .destructive) {
                            disconnect()
                        } label: {
                            Label("断开 Hermes", systemImage: "minus.circle")
                                .foregroundColor(.red)
                        }
                    }
                }

                // ============ 2. 音频设备（蓝牙耳机） ============
                Section {
                    if deviceMgr.audioOutputs.isEmpty {
                        HStack {
                            Image(systemName: "speaker.wave.2")
                                .foregroundColor(.secondary)
                            Text("未检测到音频输出")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    } else {
                        ForEach(deviceMgr.audioOutputs) { dev in
                            HStack(spacing: 12) {
                                Image(systemName: dev.icon)
                                    .font(.system(size: 18))
                                    .foregroundColor(dev.isBluetooth ? Theme.primary : .secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(dev.name)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    Text(dev.typeLabel)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if dev.isBluetooth {
                                    Label("蓝牙", systemImage: "wave.3.right")
                                        .font(.caption2)
                                        .foregroundColor(Theme.primary)
                                }
                            }
                        }
                    }
                    // 强制扬声器切换
                    if !deviceMgr.audioOutputs.isEmpty {
                        Button {
                            deviceMgr.routeToSpeaker(true)
                        } label: {
                            Label("切换到扬声器播放", systemImage: "speaker.wave.2.fill")
                        }
                    }
                } header: {
                    Text("音频设备")
                } footer: {
                    Text("检测蓝牙耳机/有线耳机连接，切换播放输出。插拔耳机实时刷新。")
                }

                // 跳转系统蓝牙设置
                Section {
                    Button {
                        openBluetoothSettings()
                    } label: {
                        Label("打开系统蓝牙设置", systemImage: "gear")
                    }
                }

                // ============ 3. BLE 设备扫描 ============
                Section {
                    if !deviceMgr.blePoweredOn {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            Text("蓝牙未开启，请先在系统设置中打开蓝牙")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Button {
                        deviceMgr.isScanning ? deviceMgr.stopScan() : deviceMgr.startScan()
                    } label: {
                        Label(deviceMgr.isScanning ? "停止扫描" : "扫描附近 BLE 设备",
                              systemImage: deviceMgr.isScanning ? "stop.circle" : "antenna.radiowaves.left.and.right")
                    }

                    if deviceMgr.isScanning {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.7)
                            Text("扫描中...")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }

                    if deviceMgr.bleDevices.isEmpty && !deviceMgr.isScanning {
                        Text("未发现设备，点击扫描开始搜索附近的蓝牙设备")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    ForEach(deviceMgr.bleDevices) { dev in
                        HStack(spacing: 12) {
                            Image(systemName: dev.isConnected ? "iphone.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right")
                                .font(.system(size: 16))
                                .foregroundColor(dev.isConnected ? .green : .secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(dev.name)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                if !dev.serviceUUIDs.isEmpty {
                                    Text(dev.serviceUUIDs.prefix(2).joined(separator: " · "))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("\(dev.rssi) dBm")
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.secondary)
                                if dev.isConnected {
                                    Text("已连接").font(.caption2).foregroundColor(.green)
                                }
                            }
                        }
                    }
                } header: {
                    Text("蓝牙设备")
                } footer: {
                    Text("扫描附近的 BLE 智能设备（支持自定义外设后续扩展）。系统蓝牙耳机由上方「音频设备」管理。")
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
                deviceMgr.refreshAudioRoute()
            }
            .onDisappear {
                store.host = host; store.port = port; store.apiKey = apiKey; store.save()
                deviceMgr.stopScan()
            }
        }
    }

    private func openBluetoothSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
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