import Foundation
import CryptoKit

/// 消息模型
struct ChatMessage: Identifiable, Codable, Equatable {
    let id: String
    var role: String          // user | ai | peer
    var text: String
    var imageBase64: String = ""
    var voiceBase64: String = ""
    var voiceDurationMs: Double = 0
    var reasoning: String = ""
    var senderName: String = ""
    var senderId: String = ""
    var isError: Bool = false
    var status: String = "sent"   // sent | delivered | failed
    var createdAt: Date = Date()

    init(id: String = UUID().uuidString, role: String, text: String, imageBase64: String = "", voiceBase64: String = "", voiceDurationMs: Double = 0, reasoning: String = "",
         senderName: String = "", senderId: String = "", isError: Bool = false, status: String = "sent") {
        self.id = id
        self.role = role
        self.text = text
        self.imageBase64 = imageBase64
        self.voiceBase64 = voiceBase64
        self.voiceDurationMs = voiceDurationMs
        self.reasoning = reasoning
        self.senderName = senderName
        self.senderId = senderId
        self.isError = isError
        self.status = status
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, text, imageBase64, voiceBase64, voiceDurationMs, reasoning, senderName, senderId, isError, status, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        role = try container.decode(String.self, forKey: .role)
        text = try container.decode(String.self, forKey: .text)
        imageBase64 = try container.decodeIfPresent(String.self, forKey: .imageBase64) ?? ""
        reasoning = try container.decodeIfPresent(String.self, forKey: .reasoning) ?? ""
        senderName = try container.decodeIfPresent(String.self, forKey: .senderName) ?? ""
        senderId = try container.decodeIfPresent(String.self, forKey: .senderId) ?? ""
        isError = try container.decodeIfPresent(Bool.self, forKey: .isError) ?? false
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "sent"
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
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
    static let systemPrompt = """
    你是 EVO 的 AI 助手，一个乐于助人、知识渊博的智能助手。请用简洁清晰的语言回答问题。
    你可以通过以下特殊标记调用内置工具（独立一行输出）：
    - 用户问时间/几点 → 输出 [工具:时间]（显示实时时钟与年月日）
    - 用户问日历/今天几号/某月日历 → 输出 [工具:日历]（显示当月日历）
    - 用户问天气 → 输出 [工具:天气]（自动定位并显示实时天气）
    - 用户问位置/我在哪 → 输出 [工具:定位]（显示经纬度并可打开地图）
    - 用户要求计算/写代码/脚本 → 用 ```js 代码块包裹 JavaScript 代码（应用内可直接运行，支持 console.log 输出结果）
    注意：输出工具标记时保留在消息中；代码块用 ```js 开头。
    """

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
