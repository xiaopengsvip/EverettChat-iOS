import Foundation
import SwiftUI
import Combine

/// 全局状态管理（与 Android 版 AppRoot 对应）
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    private init() {
        let stored = MessageStore.loadAll()
        conversations = stored.conversations
        aiMessages = stored.aiMessages
        peerMessages = stored.peerMessages
        syncDebugChannel()
    }

    // 设备信息
    let deviceId = DeviceIdentity.shared.deviceId
    var deviceName: String { DeviceIdentity.shared.deviceName }

    // 传输层（统一 ConnectionManager：LAN → P2P → Cloud）
    let conn = ConnectionManager.shared

    // 会话与消息
    @Published var conversations: [Conversation] = [] {
        didSet { MessageStore.saveConversations(conversations) }
    }
    @Published var aiMessages: [ChatMessage] = [] {
        didSet { MessageStore.saveAiMessages(aiMessages) }
    }
    @Published var peerMessages: [ChatMessage] = [] {
        didSet { MessageStore.savePeerMessages(peerMessages) }
    }
    @Published var activeConvId: String? = nil
    @Published var onlineDeviceIds: Set<String> = []   // 在线设备 ID（relay /users 轮询）

    // 联系人
    @Published var contacts: [Contact] = []

    // 导航
    @Published var selectedTab: MainTab = .messages
    @Published var showChat = false
    @Published var chatMode: String = "ai"   // ai | peer
    @Published var chatPeerName: String = ""
    @Published var chatPeerId: String = ""

    // 二维码与好友请求
    @Published var showQrScanner = false
    @Published var showMyQr = false
    @Published var pendingFriendRequest: (id: String, name: String)? = nil

    private var cancellables = Set<AnyCancellable>()

    func start() {
        // 启动自动应用 TTL 清理
        applyAutoDelete()
        // 注册推送（APNs + VoIP PushKit，免费签名自动跳过）
        PushRegistration.shared.registerAPNs()
        PushRegistration.shared.registerVoIP()
        // 云端身份注册（首次启动注册，之后定期更新）
        IdentityClient.register()
        Task {
            while true {
                try? await Task.sleep(nanoseconds: 6 * 3600 * 1_000_000_000)
                IdentityClient.register(force: true)
            }
        }
        conn.onMessage = { [weak self] type, from, senderId, payload in
            guard let self else { return }
            switch type {
            case "friend-request":
                let name = (payload["name"] as? String) ?? from
                let requestSenderId = payload["senderId"] as? String ?? senderId
                // 扫码即加：自动把对方加入联系人（扫描方已直接建立好友关系）
                let contact = Contact(deviceId: requestSenderId, name: name, status: "approved")
                if !self.contacts.contains(where: { $0.deviceId == requestSenderId }) {
                    self.contacts.append(contact)
                }
                // 回复同意（对方收到后也保存）
                Task {
                    let url = URL(string: "\(PublicRelay.httpURL)/friend-request")!
                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    let body: [String: Any] = ["type": "friend-accept", "target": requestSenderId,
                                                "from": self.deviceName, "fromId": self.deviceId]
                    req.httpBody = try? JSONSerialization.data(withJSONObject: body)
                    try? await URLSession.shared.data(for: req)
                }
                // 仍弹面板让用户知道（可拒绝）
                self.pendingFriendRequest = (id: requestSenderId, name: name)
            case "text":
                guard let text = payload["content"] as? String else { return }
                let message = ChatMessage(role: "peer", text: text, senderName: from, senderId: senderId)
                self.peerMessages.append(message)
                self.updatePeerConversation(senderId: senderId, name: from, lastText: text, time: message.createdAt)
                // EVO-PING 互测消息 → 自动回显（验证双向通道）
                if text.hasPrefix("EVO-PING-") {
                    DiagAgent.shared.log("info", "收到互测: \(text) from \(senderId.prefix(8)) → 自动回显")
                    self.conn.sendText(text, target: senderId, messageId: UUID().uuidString)
                }
            case "image":
                guard let imageBase64 = payload["data"] as? String else { return }
                let text = payload["text"] as? String ?? ""
                let message = ChatMessage(
                    role: "peer",
                    text: text,
                    imageBase64: imageBase64,
                    senderName: from,
                    senderId: senderId
                )
                self.peerMessages.append(message)
                self.updatePeerConversation(
                    senderId: senderId,
                    name: from,
                    lastText: text.isEmpty ? "[图片]" : text,
                    time: message.createdAt
                )
            case "voice":
                guard let voiceBase64 = payload["data"] as? String else { return }
                let durationMs = payload["durationMs"] as? Double ?? 0
                let message = ChatMessage(
                    role: "peer",
                    text: "",
                    voiceBase64: voiceBase64,
                    voiceDurationMs: durationMs,
                    senderName: from,
                    senderId: senderId
                )
                self.peerMessages.append(message)
                self.updatePeerConversation(
                    senderId: senderId,
                    name: from,
                    lastText: "[语音]",
                    time: message.createdAt
                )
            case "video":
                guard let videoBase64 = payload["data"] as? String else { return }
                let durationMs = payload["durationMs"] as? Double ?? 0
                let message = ChatMessage(
                    role: "peer",
                    text: "",
                    videoBase64: videoBase64,
                    videoDurationMs: durationMs,
                    senderName: from,
                    senderId: senderId
                )
                self.peerMessages.append(message)
                self.updatePeerConversation(
                    senderId: senderId,
                    name: from,
                    lastText: "[视频]",
                    time: message.createdAt
                )
            case "ack":
                guard let ackId = payload["ackId"] as? String else { return }
                if let idx = self.peerMessages.firstIndex(where: { $0.id == ackId }) {
                    self.peerMessages[idx].status = "delivered"
                }
            default:
                break
            }
        }
        // 启动自动连接中继
        conn.connect()
        // 监听在线用户
        Task {
            while true {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                conn.requestOnlineUsers()
            }
        }
    }

    func openAIChat() {
        chatMode = "ai"
        chatPeerName = "AI 助手"
        chatPeerId = "ai"
        activeConvId = "ai"
        showChat = true
    }

    func openPeerChat(name: String, peerId: String) {
        chatMode = "peer"
        chatPeerName = name
        chatPeerId = peerId
        activeConvId = peerId
        showChat = true
    }

    /// 打开 Hermes 设备互联对话（复用 ChatView 完整能力：图片/文件/语音等）
    func openDeviceChat() {
        chatMode = "device"
        chatPeerName = "Hermes 设备"
        chatPeerId = "device"
        activeConvId = "device"
        showChat = true
    }

    func sendFriendRequest(targetId: String, targetName: String) {
        let url = URL(string: "\(PublicRelay.httpURL)/friend-request")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        let body: [String: Any] = ["type": "friend-request", "target": targetId, "from": deviceName, "fromId": deviceId]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let ok = json["ok"] as? Bool, ok {
                    // 请求成功
                }
            } catch {}
        }
    }

    func updatePeerConversation(senderId: String, name: String, lastText: String, time: Date = Date()) {
        if let index = conversations.firstIndex(where: { $0.id == senderId }) {
            conversations[index].name = name
            conversations[index].lastText = lastText
            conversations[index].lastTime = time
        } else {
            conversations.append(
                Conversation(id: senderId, name: name, type: "peer", lastText: lastText, lastTime: time)
            )
        }
    }

    /// 调试通道（EVO 测试通道）：调试模式开启时显示会话，关闭时隐藏
    func syncDebugChannel() {
        let debugId = "cmd-server"
        let debugOn = UserDefaults.standard.bool(forKey: "debug_mode")
        if debugOn {
            if conversations.firstIndex(where: { $0.id == debugId }) == nil {
                conversations.append(
                    Conversation(id: debugId, name: "EVO 调试通道", type: "debug",
                                 lastText: "调试通道已开启（来自中继的远程命令会显示在这里）", lastTime: Date())
                )
            }
        } else {
            conversations.removeAll { $0.id == debugId }
        }
    }

    /// 调试通道收到消息（调试模式开启时，每条 __cmd__ 记录到此处）
    func debugChannelMessage(_ text: String) {
        let debugId = "cmd-server"
        let msg = ChatMessage(role: "peer", text: text, senderName: "调试通道", senderId: debugId)
        peerMessages.append(msg)
        // 专门更新调试通道会话（保持 type="debug"，不混入好友会话区）
        if let index = conversations.firstIndex(where: { $0.id == debugId }) {
            conversations[index].lastText = text
            conversations[index].lastTime = Date()
        } else {
            conversations.append(
                Conversation(id: debugId, name: "EVO 调试通道", type: "debug",
                             lastText: text, lastTime: Date())
            )
        }
        syncDebugChannel()
    }

    /// 自动删除过期消息（TTL，依据 auto_delete_days）
    func applyAutoDelete() {
        let days = UserDefaults.standard.integer(forKey: "auto_delete_days")
        guard days > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        aiMessages = aiMessages.filter { $0.createdAt >= cutoff }
        peerMessages = peerMessages.filter { $0.createdAt >= cutoff }
        conversations = conversations.filter { $0.lastTime >= cutoff }
        MessageStore.saveAiMessages(aiMessages)
        MessageStore.savePeerMessages(peerMessages)
        MessageStore.saveConversations(conversations)
    }
}
