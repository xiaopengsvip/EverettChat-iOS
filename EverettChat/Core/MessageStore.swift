import Foundation

/// 消息本地存储：使用 UserDefaults + JSON，避免引入额外持久化依赖
enum MessageStore {
    private enum Key {
        static let conversations = "conversations"
        static let aiMessages = "aiMessages"
        static let peerMessages = "peerMessages"
    }

    private static let maxAiMessages = 500
    private static let maxPeerMessagesPerConversation = 500

    static func saveConversations(_ conversations: [Conversation]) {
        save(conversations, forKey: Key.conversations)
    }

    static func saveAiMessages(_ messages: [ChatMessage]) {
        save(Array(messages.suffix(maxAiMessages)), forKey: Key.aiMessages)
    }

    static func savePeerMessages(_ messages: [ChatMessage]) {
        save(limitPeerMessages(messages), forKey: Key.peerMessages)
    }

    static func loadAll() -> (
        conversations: [Conversation],
        aiMessages: [ChatMessage],
        peerMessages: [ChatMessage]
    ) {
        (
            conversations: load([Conversation].self, forKey: Key.conversations) ?? [],
            aiMessages: load([ChatMessage].self, forKey: Key.aiMessages) ?? [],
            peerMessages: load([ChatMessage].self, forKey: Key.peerMessages) ?? []
        )
    }

    private static func save<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// peer 消息按会话 ID 裁剪；旧数据没有 senderId 时归到 legacy 分组
    private static func limitPeerMessages(_ messages: [ChatMessage]) -> [ChatMessage] {
        var buckets: [String: [ChatMessage]] = [:]

        for message in messages {
            let conversationId = message.senderId.isEmpty ? "legacy" : message.senderId
            buckets[conversationId, default: []].append(message)
        }

        let limited = buckets.values.flatMap { bucket in
            Array(bucket.suffix(maxPeerMessagesPerConversation))
        }

        return limited.sorted { $0.createdAt < $1.createdAt }
    }
}
