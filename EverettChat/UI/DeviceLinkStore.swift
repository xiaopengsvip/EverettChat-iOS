import SwiftUI

/// 设备互联会话持久化存储（消息用 ChatMessage 统一模型，与 AI/好友会话一致）
class DeviceLinkStore: ObservableObject {
    static let shared = DeviceLinkStore()

    @Published var messages: [ChatMessage] = []
    @Published var host = "172.11.8.35"
    @Published var port = "8642"
    @Published var apiKey = "evt-0a064c103a11512f7781bf6f999bf1fe"
    @Published var isConnected = false
    @Published var modelName = ""
    @Published var lastMessageTime = Date()

    private let defaults = UserDefaults.standard
    private let messagesKey = "device_link_messages"
    private let configKey = "device_link_config"

    init() {
        load()
    }

    var lastMessageText: String {
        messages.last(where: { $0.role == "ai" })?.text ?? "开始使用 Hermes 设备互联"
    }

    func save() {
        // 存消息（ChatMessage Codable）
        if let encoded = try? JSONEncoder().encode(messages) {
            defaults.set(encoded, forKey: messagesKey)
        }
        // 存配置
        let config: [String: Any] = ["host": host, "port": port, "apiKey": apiKey,
                                     "isConnected": isConnected, "modelName": modelName,
                                     "lastMessageTime": lastMessageTime.timeIntervalSince1970]
        if let encoded = try? JSONSerialization.data(withJSONObject: config) {
            defaults.set(encoded, forKey: configKey)
        }
    }

    func load() {
        // 读消息
        if let data = defaults.data(forKey: messagesKey),
           let decoded = try? JSONDecoder().decode([ChatMessage].self, from: data) {
            messages = decoded
        }
        // 读配置
        if let data = defaults.data(forKey: configKey),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            host = json["host"] as? String ?? host
            port = json["port"] as? String ?? port
            apiKey = json["apiKey"] as? String ?? apiKey
            isConnected = json["isConnected"] as? Bool ?? false
            modelName = json["modelName"] as? String ?? ""
            if let t = json["lastMessageTime"] as? TimeInterval {
                lastMessageTime = Date(timeIntervalSince1970: t)
            }
        }
    }

    func clear() {
        messages = []
        isConnected = false
        modelName = ""
        save()
    }
}
