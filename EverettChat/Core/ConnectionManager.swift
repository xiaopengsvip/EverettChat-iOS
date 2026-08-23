import Foundation
import SwiftUI
import Combine

/// 统一连接状态
enum EvoConnectionState: String {
    case disconnected = "未连接"
    case connecting = "连接中"
    case lan = "局域网直连"
    case p2p = "P2P 直连"
    case cloud = "云端中继"
    case reconnecting = "重连中"
}

/// 持久连接时长（设置页选择，P1）
enum SessionDuration: Int, CaseIterable {
    case hours1 = 1
    case hours6 = 6
    case hours12 = 12
    case hours24 = 24
    case hours48 = 48
    case days7 = 168

    var label: String {
        switch self {
        case .hours1: return "1 小时"
        case .hours6: return "6 小时"
        case .hours12: return "12 小时"
        case .hours24: return "24 小时"
        case .hours48: return "48 小时"
        case .days7: return "7 天"
        }
    }

    static var current: SessionDuration {
        SessionDuration(rawValue: UserDefaults.standard.integer(forKey: "session_duration_hours")) ?? .hours24
    }
}

/// 统一 ConnectionManager（架构第三节）
/// 数据通信优先级：LAN → P2P → Cloud
/// - CloudTransport：RelayTransport（WS 云端中继，自动重连）
/// - LANTransport：MultipeerConnectivity（蓝牙/局域网）
/// 双端共用同一接口：connect/disconnect/send/receive/getState
@MainActor
final class ConnectionManager: ObservableObject {
    static let shared = ConnectionManager()

    // 传输层
    private let cloud = RelayTransport(
        deviceId: DeviceIdentity.shared.deviceId,
        deviceName: DeviceIdentity.shared.deviceName
    )

    @Published var state: EvoConnectionState = .disconnected
    @Published var isConnected = false
    @Published var onlineUsers: [RelayTransport.OnlineUser] = []

    // 消息回调（统一入口：AppState / CallManager 等各自注册）
    private var messageHandlers: [(String, String, String, [String: Any]) -> Void] = []
    var onMessage: ((String, String, String, [String: Any]) -> Void)? {
        didSet {
            // 兼容旧用法：设置 onMessage 时作为唯一 handler
            if let onMessage {
                messageHandlers = [onMessage]
            }
        }
    }
    var onStatusChange: ((Bool) -> Void)?

    /// 注册消息订阅者（多播：AppState + CallManager 同时接收）
    func addMessageHandler(_ handler: @escaping (String, String, String, [String: Any]) -> Void) {
        messageHandlers.append(handler)
    }

    private var cancellables = Set<AnyCancellable>()

    private init() {
        // 桥接 Cloud 传输层
        cloud.onMessage = { [weak self] type, from, senderId, payload in
            self?.messageHandlers.forEach { $0(type, from, senderId, payload) }
        }
        cloud.onStatusChange = { [weak self] connected in
            self?.isConnected = connected
            self?.state = connected ? .cloud : .reconnecting
            self?.onStatusChange?(connected)
        }
        cloud.$onlineUsers
            .sink { [weak self] users in self?.onlineUsers = users }
            .store(in: &cancellables)
    }

    // MARK: - 统一接口

    func connect() {
        cloud.connect()
        state = .connecting
        // 连接后广播 HELLO（Evo Protocol 握手）
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.state == .cloud else { return }
            cloud.sendRaw(type: "hello", payload: [
                "deviceId": DeviceIdentity.shared.deviceId,
                "deviceName": DeviceIdentity.shared.deviceName,
                "platform": "ios",
                "version": "1.0.0"
            ])
        }
    }

    func disconnect() {
        cloud.disconnect()
        state = .disconnected
    }

    /// 发送消息：内部按优先级选择传输层（当前 Cloud 为主，LAN 后续接入）
    func send(type: String, target: String, payload: [String: Any] = [:]) {
        cloud.sendRaw(type: type, target: target, payload: payload)
    }

    /// 发送加密文本（E2E，messageId 用于 ACK）
    func sendText(_ text: String, target: String, messageId: String = "") {
        cloud.sendText(text, target: target, messageId: messageId)
    }

    func sendImage(base64: String, target: String, name: String = "image.jpg", mime: String = "image/jpeg", text: String = "", messageId: String = "") {
        cloud.sendImage(base64: base64, target: target, name: name, mime: mime, text: text, messageId: messageId)
    }

    func sendVoice(base64: String, target: String, durationMs: Double, mime: String = "audio/m4a", messageId: String = "") {
        cloud.sendVoice(base64: base64, target: target, durationMs: durationMs, mime: mime, messageId: messageId)
    }

    func sendAck(messageId: String, target: String) {
        cloud.sendAck(messageId: messageId, target: target)
    }

    /// 发送好友请求（HTTP 直达，不依赖 WS）
    func sendFriendRequest(target: String, fromName: String, fromId: String) {
        let url = URL(string: "\(PublicRelay.httpURL)/friend-request")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "target": target, "type": "friend-request", "from": fromName, "fromId": fromId
        ])
        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }

    func requestOnlineUsers() {
        cloud.requestOnlineUsers()
    }

    /// 当前状态描述
    func stateDescription() -> String {
        state.rawValue
    }
}
