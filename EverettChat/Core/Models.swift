import Foundation
import CryptoKit

/// 消息模型
struct ChatMessage: Identifiable, Codable, Equatable {
    let id: String
    var role: String          // user | ai | peer
    var text: String
    var reasoning: String = ""
    var senderName: String = ""
    var senderId: String = ""
    var isError: Bool = false
    var createdAt: Date = Date()

    init(id: String = UUID().uuidString, role: String, text: String, reasoning: String = "",
         senderName: String = "", senderId: String = "", isError: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.reasoning = reasoning
        self.senderName = senderName
        self.senderId = senderId
        self.isError = isError
    }
}

/// 会话模型
struct Conversation: Identifiable, Codable, Equatable {
    let id: String            // "ai" 或 对方 deviceId
    var name: String
    var type: String          // ai | peer
    var lastText: String = ""
    var lastTime: Date = Date()
    var unread: Int = 0
}

/// 联系人
struct Contact: Codable, Identifiable {
    let deviceId: String
    var name: String
    var status: String        // pending | approved
    var addedTime: Date = Date()

    var id: String { deviceId }
}

/// 底部 Tab
enum MainTab: String, CaseIterable {
    case messages = "消息"
    case contacts = "通讯录"
    case discover = "发现"
    case mine = "我的"

    var icon: String {
        switch self {
        case .messages: return "message.fill"
        case .contacts: return "person.2.fill"
        case .discover: return "dot.radiowaves.left.and.right"
        case .mine: return "person.fill"
        }
    }
}

/// 公网中继配置（与 Android 版一致）
enum PublicRelay {
    static let wsURL = "wss://relay.vios.top/ws"
    static let httpURL = "https://relay.vios.top"
    static let room = "everett-public"
    static let passphrase = "everett-public"
}

/// AI 模型配置
enum ApiConfig {
    static let baseURL = "https://relay.vios.top/ai"
    static let model = "deepseek-v4-flash"
    static let visionModel = "deepseek-v4-flash-vision-exp"
    static let hy3Model = "hy3"
    static let systemPrompt = "你是 Everett 的 AI 助手，一个乐于助人、知识渊博的智能助手。请用简洁清晰的语言回答问题。"

    struct ModelInfo: Identifiable {
        let id: String
        let name: String
        let desc: String
        let vision: Bool
    }

    static let models = [
        ModelInfo(id: "deepseek-v4-flash", name: "DeepSeek V4", desc: "通用文本 · 快", vision: false),
        ModelInfo(id: "deepseek-v4-flash-vision-exp", name: "DeepSeek 视觉", desc: "图片/文件分析", vision: true),
        ModelInfo(id: "hy3", name: "Hy3", desc: "混合模型", vision: false)
    ]
}
