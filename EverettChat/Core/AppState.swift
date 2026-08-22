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
    }

    // 设备信息
    let deviceId = DeviceIdentity.shared.deviceId
    var deviceName: String { DeviceIdentity.shared.deviceName }

    // 传输层
    let transport = RelayTransport(
        deviceId: DeviceIdentity.shared.deviceId,
        deviceName: DeviceIdentity.shared.deviceName
    )

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
        transport.onMessage = { [weak self] type, from, senderId, payload in
            guard let self else { return }
            switch type {
            case "friend-request":
                let name = (payload["name"] as? String) ?? from
                let requestSenderId = payload["senderId"] as? String ?? senderId
                self.pendingFriendRequest = (id: requestSenderId, name: name)
            case "text":
                guard let text = payload["data"] as? String else { return }
                let message = ChatMessage(role: "peer", text: text, senderName: from, senderId: senderId)
                self.peerMessages.append(message)
                self.updatePeerConversation(senderId: senderId, name: from, lastText: text, time: message.createdAt)
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
            default:
                break
            }
        }
        // 启动自动连接中继
        transport.connect()
        // 监听在线用户
        Task {
            while true {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                transport.requestOnlineUsers()
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
