import ActivityKit
import Foundation

/// EVO Live Activity 管理器（App 端启动/更新/结束灵动岛）
/// 支持两种模式：AI 任务进度 + 会话消息常驻
@MainActor
class EvoActivityManager {
    static let shared = EvoActivityManager()
    private var activity: Activity<EvoActivityAttributes>?
    private var currentChatType: String = ""

    private init() {}

    /// 是否支持 Live Activity
    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    // MARK: - AI 任务模式（原有）

    /// 启动 Live Activity（AI 任务开始）
    func start(sessionId: String, peerName: String = "EVO AI") {
        guard isSupported else { return }
        let attributes = EvoActivityAttributes(sessionId: sessionId, peerName: peerName)
        let state = EvoActivityAttributes.ContentState(status: "等待中", progress: 0)
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil)
            )
        } catch {
            activity = nil
        }
    }

    /// 更新 Live Activity（AI 状态实时刷新）
    func update(status: String, stepText: String = "", progress: Double = 0, toolName: String = "", fileName: String = "") {
        guard let activity else { return }
        let state = EvoActivityAttributes.ContentState(
            status: status,
            stepText: stepText,
            progress: min(max(progress, 0), 1),
            toolName: toolName,
            fileName: fileName,
            isFinished: false
        )
        Task {
            await activity.update(using: state)
        }
    }

    /// 结束 Live Activity（AI 任务完成/失败）
    func end(status: String = "完成", progress: Double = 1) {
        guard let activity else { return }
        let state = EvoActivityAttributes.ContentState(
            status: status,
            progress: progress,
            isFinished: true
        )
        Task {
            await activity.end(using: state, dismissalPolicy: .after(Date.now.addingTimeInterval(4)))
            self.activity = nil
        }
    }

    /// 取消 Live Activity（用户停止任务）
    func cancel() {
        guard let activity else { return }
        Task {
            await activity.end(dismissalPolicy: .immediate)
            self.activity = nil
        }
    }

    // MARK: - 会话消息模式（灵动岛常驻 + 锁屏消息预览）

    /// 启动会话常驻 Live Activity（AI/好友/Hermes）
    func startChat(sessionId: String, peerName: String, chatType: String) {
        guard isSupported else { return }
        // 如果已有同类型会话活动，不重复创建
        if activity != nil, currentChatType == chatType { return }
        endChat()
        currentChatType = chatType
        let attributes = EvoActivityAttributes(sessionId: sessionId, peerName: peerName)
        let state = EvoActivityAttributes.ContentState(
            status: "在线",
            chatType: chatType,
            messageText: "",
            messageCount: 0
        )
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil)
            )
        } catch {
            activity = nil
        }
    }

    /// 更新消息（新消息到达时触发）
    func updateChat(message: String, senderName: String, isMine: Bool = false, count: Int = 0) {
        guard let activity, !currentChatType.isEmpty else { return }
        let state = EvoActivityAttributes.ContentState(
            status: "在线",
            chatType: currentChatType,
            messageText: message,
            senderName: senderName,
            isMine: isMine,
            messageCount: count > 0 ? count : (activity.contentState.messageCount + 1)
        )
        Task {
            await activity.update(using: state)
        }
    }

    /// 结束会话常驻
    func endChat() {
        if activity != nil, !currentChatType.isEmpty {
            let state = EvoActivityAttributes.ContentState(
                status: "已结束",
                isFinished: true,
                messageText: "会话已关闭"
            )
            Task {
                await activity?.end(using: state, dismissalPolicy: .after(Date.now.addingTimeInterval(2)))
            }
            activity = nil
            currentChatType = ""
        }
    }
}