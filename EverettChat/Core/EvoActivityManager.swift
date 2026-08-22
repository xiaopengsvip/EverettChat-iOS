import ActivityKit
import Foundation

/// EVO Live Activity 管理器（App 端启动/更新/结束灵动岛）
@MainActor
class EvoActivityManager {
    static let shared = EvoActivityManager()
    private var activity: Activity<EvoActivityAttributes>?

    private init() {}

    /// 是否支持 Live Activity
    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

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
            await activity.end(using: state, dismissalPolicy: .after(Duration.seconds(4)))
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
}
