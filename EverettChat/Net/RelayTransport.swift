import Foundation

/// 中继传输层（WebSocket → Cloudflare Workers，与 Android 版协议兼容）
/// 自动重连（指数退避）+ 心跳保活 + 定向路由（target）
@MainActor
final class RelayTransport: NSObject, ObservableObject {
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

    init(deviceId: String, deviceName: String,
         room: String = PublicRelay.room,
         passphrase: String = PublicRelay.passphrase) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.room = room
        self.passphrase = passphrase
        super.init()
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
        guard let parsed = CryptoEngine.parseMessage(text, passphrase: passphrase) else { return }
        switch parsed.type {
        case "welcome":
            isConnected = true
            reconnectAttempts = 0
            peerName = parsed.payload["peer"] as? String ?? "对端"
            onStatusChange?(true)
            startHeartbeat()
        case "peer-joined":
            peerName = parsed.payload["peer"] as? String ?? "对端"
        case "online-users":
            if let users = parsed.payload["users"] as? [[String: Any]] {
                onlineUsers = users.compactMap { u in
                    guard let id = u["deviceId"] as? String, let name = u["name"] as? String else { return nil }
                    return OnlineUser(deviceId: id, name: name, room: u["room"] as? String ?? "")
                }
            }
        default:
            var payload = parsed.payload
            if ["text", "image"].contains(parsed.type),
               let data = payload["data"] as? String,
               let plain = CryptoEngine.decrypt(data, passphrase: passphrase) {
                payload["data"] = plain
            }
            // 收到业务消息 → 自动回 ACK（携带原消息 id）
            if ["text", "image", "voice"].contains(parsed.type),
               let messageId = payload["messageId"] as? String, !messageId.isEmpty {
                sendAck(messageId: messageId, target: parsed.senderId)
            }
            onMessage?(parsed.type, parsed.from, parsed.senderId, payload)
        }
    }

    private func handleDisconnect() {
        isConnected = false
        onStatusChange?(false)
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

    /// 发送加密消息（E2E），messageId 用于送达确认
    func sendEncrypted(type: String, target: String, content: String, messageId: String = "") {
        guard let enc = CryptoEngine.encrypt(content, passphrase: passphrase) else { return }
        var payload: [String: Any] = ["data": enc, "target": target]
        if !messageId.isEmpty { payload["messageId"] = messageId }
        sendRaw(type: type, target: target, payload: payload)
    }

    /// 发送文本消息
    func sendText(_ text: String, target: String, messageId: String = "") {
        sendEncrypted(type: "text", target: target, content: text, messageId: messageId)
    }

    /// 发送图片消息，data 字段保持端到端加密
    func sendImage(base64: String, target: String, name: String = "image.jpg", mime: String = "image/jpeg", text: String = "", messageId: String = "") {
        guard let enc = CryptoEngine.encrypt(base64, passphrase: passphrase) else { return }
        var payload: [String: Any] = ["data": enc, "name": name, "mime": mime, "text": text, "target": target]
        if !messageId.isEmpty { payload["messageId"] = messageId }
        sendRaw(type: "image", target: target, payload: payload)
    }

    /// 发送语音消息（AAC m4a Base64），data 字段端到端加密
    func sendVoice(base64: String, target: String, durationMs: Double, mime: String = "audio/m4a", messageId: String = "") {
        guard let enc = CryptoEngine.encrypt(base64, passphrase: passphrase) else { return }
        var payload: [String: Any] = ["data": enc, "mime": mime, "durationMs": durationMs, "target": target]
        if !messageId.isEmpty { payload["messageId"] = messageId }
        sendRaw(type: "voice", target: target, payload: payload)
    }

    /// 发送送达确认（ACK）
    func sendAck(messageId: String, target: String) {
        sendRaw(type: "ack", target: target, payload: ["ackId": messageId, "target": target])
    }

    /// 发送视频消息
    func sendVideo(base64: String, target: String, durationMs: Double, mime: String = "video/mp4", messageId: String = "") {
        guard let enc = CryptoEngine.encrypt(base64, passphrase: passphrase) else { return }
        var payload: [String: Any] = ["data": enc, "mime": mime, "durationMs": durationMs, "target": target]
        if !messageId.isEmpty { payload["messageId"] = messageId }
        sendRaw(type: "video", target: target, payload: payload)
    }

    /// 查询在线用户
    func requestOnlineUsers() {
        sendRaw(type: "get-users")
    }
}

extension RelayTransport: URLSessionWebSocketDelegate {
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        // 加入房间
        let join: [String: Any] = ["type": "join", "id": UUID().uuidString,
                                   "from": deviceName, "senderId": deviceId,
                                   "payload": ["room": room]]
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
