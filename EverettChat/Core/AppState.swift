import Foundation
import SwiftUI
import Combine

/// 全局状态管理（与 Android 版 AppRoot 对应）
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    private init() {}

    // 设备信息
    let deviceId = DeviceIdentity.shared.deviceId
    var deviceName: String { DeviceIdentity.shared.deviceName }

    // 传输层
    let transport = RelayTransport(
        deviceId: DeviceIdentity.shared.deviceId,
        deviceName: DeviceIdentity.shared.deviceName
    )

    // 会话与消息
    @Published var conversations: [Conversation] = []
    @Published var aiMessages: [ChatMessage] = []
    @Published var peerMessages: [ChatMessage] = []
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
        showChat = true
    }

    func openPeerChat(name: String, peerId: String) {
        chatMode = "peer"
        chatPeerName = name
        chatPeerId = peerId
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
}