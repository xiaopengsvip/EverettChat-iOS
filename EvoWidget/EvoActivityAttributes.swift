import ActivityKit
import Foundation

/// EVO Live Activity / 灵动岛共享属性（App 与 Widget 共用）
struct EvoActivityAttributes: ActivityAttributes {
    /// 动态内容（可实时更新）
    public struct ContentState: Codable, Hashable {
        var status: String = "等待"          // AI 状态：等待/思考/执行中/完成/失败
        var stepText: String = ""            // "Step 4 / 8"
        var progress: Double = 0             // 0...1
        var toolName: String = ""            // 当前工具
        var fileName: String = ""            // 当前文件/会话
        var isFinished: Bool = false

        // 会话消息模式（chatType 非空时显示消息，否则显示 AI 任务进度）
        var chatType: String = ""            // "ai" | "peer" | "device" | ""（任务模式）
        var messageText: String = ""         // 最新消息预览
        var senderName: String = ""          // 发送者
        var isMine: Bool = false             // 是否自己发的
        var messageCount: Int = 0            // 新消息条数（未读）
    }

    /// 静态内容
    var sessionId: String = ""              // Deep Link 会话 ID
    var peerName: String = "EVO AI"          // 会话名称
}
