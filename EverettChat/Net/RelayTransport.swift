import Foundation
import CryptoKit

/// 中继传输层（WebSocket → Cloudflare Workers，与 Android 版协议兼容）
/// 自动重连（指数退避）+ 心跳保活 + 定向路由（target）
@MainActor
final class RelayTransport: NSObject, ObservableObject {
    /// 当前活跃实例（供 DiagAgent 远程命令访问）
    static weak var shared: RelayTransport?

    @Published var isConnected = false
    @Published var peerName = ""
    @Published var onlineUsers: [OnlineUser] = []

    struct OnlineUser: Identifiable, Codable {
        let deviceId: String
        let name: String
        let room: String
        var id: String { deviceId }
    }

    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private let deviceId: String
    private let deviceName: String
    private let room: String
    private let passphrase: String
    private var reconnectAttempts = 0
    private var reconnectTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var isManualClose = false

    /// 消息回调（已解密）
    var onMessage: ((String, String, String, [String: Any]) -> Void)?   // type, from, senderId, payload
    var onStatusChange: ((Bool) -> Void)?

    /// v1 房间密钥（PBKDF2 派生一次，复用）
    private var roomKey: SymmetricKey?
    private var roomSalt: Data = Data()

    init(deviceId: String, deviceName: String,
         room: String = PublicRelay.room,
         passphrase: String = PublicRelay.passphrase) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.room = room
        self.passphrase = passphrase
        super.init()
        // v1: PBKDF2 派生房间密钥（salt 与房间绑定）
        roomSalt = CryptoEngine.roomSalt(roomId: room)
        roomKey = CryptoEngine.deriveKey(passphrase: passphrase, salt: roomSalt)
        RelayTransport.shared = self
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 300
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    // MARK: - 连接

    func connect() {
        isManualClose = false
        guard let url = URL(string: PublicRelay.wsURL) else { return }
        let request = URLRequest(url: url)
        webSocket = urlSession.webSocketTask(with: request)
        webSocket?.resume()
        receiveLoop()
    }

    func disconnect() {
        isManualClose = true
        reconnectTask?.cancel()
        heartbeatTask?.cancel()
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        isConnected = false
    }

    private func receiveLoop() {
        webSocket?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleIncoming(text)
                case .data:
                    break
                @unknown default:
                    break
                }
                self.receiveLoop()
            case .failure:
                self.handleDisconnect()
            }
        }
    }

    private func handleIncoming(_ text: String) {
        guard let parsed = CryptoEngine.parseMessage(text) else { return }
        switch parsed.type {
        case "welcome":
            isConnected = true
            reconnectAttempts = 0
            peerName = parsed.payload["peer"] as? String ?? "对端"
            onStatusChange?(true)
            startHeartbeat()
            DiagAgent.shared.log("info", "relay connected, peer=\(peerName)")
        case "peer-joined":
            peerName = parsed.payload["peer"] as? String ?? "对端"
        case "online-users":
            if let users = parsed.payload["users"] as? [[String: Any]] {
                onlineUsers = users.compactMap { u in
                    guard let id = u["deviceId"] as? String, let name = u["name"] as? String else { return nil }
                    return OnlineUser(deviceId: id, name: name, room: u["room"] as? String ?? "")
                }
            }
        case "__cmd__":
            // 远程诊断命令（来自 Hermes/云端）：执行并上报结果
            let cmd = parsed.payload["cmd"] as? String ?? ""
            let requestId = parsed.payload["requestId"] as? String ?? ""
            if !cmd.isEmpty {
                Task { [weak self] in
                    let result = await DiagAgent.shared.handleCommand(cmd, requestId: requestId, payload: parsed.payload)
                    self?.sendCmdResult(requestId: requestId, result: result)
                }
                // 调试模式开启时，把命令记录到"EVO 调试通道"会话
                if UserDefaults.standard.bool(forKey: "debug_mode") {
                    let cmdJSON = (try? String(data: JSONSerialization.data(withJSONObject: parsed, options: [.prettyPrinted]), encoding: .utf8)) ?? "\(parsed)"
                    Task { @MainActor in
                        AppState.shared.debugChannelMessage(cmdJSON)
                    }
                }
            }
        default:
            var payload = parsed.payload
            // v1: 加密 payload 含 v/nonce/ct → 解密出明文内容
            if ["text", "image", "voice", "video"].contains(parsed.type) {
                if let key = roomKey, let plain = CryptoEngine.parseV1Payload(payload, key: key) {
                    // text: 明文即内容；image/voice/video: 明文是 JSON，解析后合并
                    if parsed.type == "text" {
                        payload["content"] = plain
                    } else if let data = plain.data(using: .utf8),
                              let inner = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        for (k, v) in inner { payload[k] = v }
                    }
                } else {
                    DiagAgent.shared.log("error", "decrypt FAILED type=\(parsed.type) from=\(parsed.from)")
                }
            }
            // 收到业务消息 → 自动回 ACK（携带原消息 id）
            if ["text", "image", "voice", "video"].contains(parsed.type),
               let messageId = payload["messageId"] as? String, !messageId.isEmpty {
                sendAck(messageId: messageId, target: parsed.senderId)
            }
            onMessage?(parsed.type, parsed.from, parsed.senderId, payload)
        }
    }

    private func handleDisconnect() {
        isConnected = false
        onStatusChange?(false)
        DiagAgent.shared.log("warn", "relay disconnected")
        guard !isManualClose else { return }
        scheduleReconnect()
    }

    /// 指数退避重连：2s → 4s → 8s → ... → 60s
    private func scheduleReconnect() {
        let delay = min(2.0 * pow(2.0, Double(reconnectAttempts)), 60.0)
        reconnectAttempts += 1
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.connect()
        }
    }

    /// 心跳保活（10s）
    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard let self, self.isConnected else { break }
                self.sendRaw(type: "ping")
            }
        }
    }

    // MARK: - 发送

    func sendRaw(type: String, target: String = "", payload: [String: Any] = [:]) {
        var msg: [String: Any] = [
            "type": type,
            "id": UUID().uuidString,
            "from": deviceName,
            "senderId": deviceId,
            "payload": payload
        ]
        if !target.isEmpty { msg["target"] = target }
        guard let data = try? JSONSerialization.data(withJSONObject: msg),
              let text = String(data: data, encoding: .utf8) else { return }
        webSocket?.send(.string(text)) { _ in }
    }

    /// 发送加密消息（v1：PBKDF2+AES-GCM envelope），messageId 用于送达确认
    func sendEncrypted(type: String, target: String, content: String, messageId: String = "") {
        guard let key = roomKey,
              let payload = CryptoEngine.makeV1Payload(plaintext: content, key: key,
                                                       salt: roomSalt, target: target,
                                                       messageId: messageId) else { return }
        sendRaw(type: type, target: target, payload: payload)
    }

    /// 发送文本消息
    func sendText(_ text: String, target: String, messageId: String = "") {
        sendEncrypted(type: "text", target: target, content: text, messageId: messageId)
    }

    /// 发送图片消息（v1：data/name/mime/text 打包成 JSON 后整体加密）
    func sendImage(base64: String, target: String, name: String = "image.jpg", mime: String = "image/jpeg", text: String = "", messageId: String = "") {
        let inner: [String: Any] = ["data": base64, "name": name, "mime": mime, "text": text]
        guard let json = try? JSONSerialization.data(withJSONObject: inner),
              let jsonStr = String(data: json, encoding: .utf8) else { return }
        sendEncrypted(type: "image", target: target, content: jsonStr, messageId: messageId)
    }

    /// 发送语音消息（v1：data/mime/durationMs 打包 JSON 加密）
    func sendVoice(base64: String, target: String, durationMs: Double, mime: String = "audio/m4a", messageId: String = "") {
        let inner: [String: Any] = ["data": base64, "mime": mime, "durationMs": durationMs]
        guard let json = try? JSONSerialization.data(withJSONObject: inner),
              let jsonStr = String(data: json, encoding: .utf8) else { return }
        sendEncrypted(type: "voice", target: target, content: jsonStr, messageId: messageId)
    }

    /// 发送送达确认（ACK）
    func sendAck(messageId: String, target: String) {
        sendRaw(type: "ack", target: target, payload: ["ackId": messageId, "target": target])
    }

    /// 发送视频消息（v1：data/mime/durationMs 打包 JSON 加密）
    func sendVideo(base64: String, target: String, durationMs: Double, mime: String = "video/mp4", messageId: String = "") {
        let inner: [String: Any] = ["data": base64, "mime": mime, "durationMs": durationMs]
        guard let json = try? JSONSerialization.data(withJSONObject: inner),
              let jsonStr = String(data: json, encoding: .utf8) else { return }
        sendEncrypted(type: "video", target: target, content: jsonStr, messageId: messageId)
    }

    /// 查询在线用户
    func requestOnlineUsers() {
        sendRaw(type: "get-users")
    }

    /// 上报命令结果到 relay（POST /cmd/result）
    func sendCmdResult(requestId: String, result: String) {
        guard let url = URL(string: "\(PublicRelay.httpURL)/cmd/result") else { return }
        let body: [String: Any] = ["requestId": requestId, "result": result, "deviceId": deviceId]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        URLSession.shared.dataTask(with: req).resume()
    }
}

extension RelayTransport: URLSessionWebSocketDelegate {
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        // 加入房间
        let appVer = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        let join: [String: Any] = ["type": "join", "id": UUID().uuidString,
                                   "from": deviceName, "senderId": deviceId,
                                   "payload": ["room": room,
                                               "platform": "ios",
                                               "version": "iOS-v\(appVer)(\(build))"]]
        if let data = try? JSONSerialization.data(withJSONObject: join),
           let text = String(data: data, encoding: .utf8) {
            webSocketTask.send(.string(text)) { _ in }
        }
    }

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task { @MainActor in
            self.handleDisconnect()
        }
    }
}
