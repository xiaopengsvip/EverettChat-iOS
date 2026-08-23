import SwiftUI

/// 设备互联会话持久化存储
class DeviceLinkStore: ObservableObject {
    static let shared = DeviceLinkStore()

    @Published var messages: [ChatMsg] = []
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
        messages.last(where: { !$0.isUser })?.content ?? "开始使用 Hermes 设备互联"
    }

    func save() {
        // 存消息
        let data = messages.map { ["content": $0.content, "isUser": $0.isUser, "id": $0.id.uuidString] }
        if let encoded = try? JSONSerialization.data(withJSONObject: data) {
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
           let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            messages = json.compactMap { d in
                guard let content = d["content"] as? String,
                      let isUser = d["isUser"] as? Bool else { return nil }
                return ChatMsg(content: content, isUser: isUser)
            }
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