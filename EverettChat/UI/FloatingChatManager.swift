import SwiftUI

/// 浮窗目标会话类型
enum FloatingTarget: Equatable {
    case ai
    case peer(id: String, name: String)
    case device
}

/// 浮窗尺寸档位
enum FloatingSize: CGFloat, CaseIterable {
    case small = 0.45   // 屏宽 45%
    case medium = 0.68  // 屏宽 68%
    case large = 0.92   // 屏宽 92%

    var label: String {
        switch self {
        case .small: return "小"
        case .medium: return "中"
        case .large: return "大"
        }
    }
}

/// 全局浮窗聊天管理器（挂 RootView 顶层，跨 Tab 可见）
@MainActor
final class FloatingChatManager: ObservableObject {
    static let shared = FloatingChatManager()

    @Published var isShowing = false
    @Published var isMinimized = false
    @Published var target: FloatingTarget = .ai
    @Published var size: FloatingSize = .medium
    @Published var offset: CGSize = .zero
    @Published var dragOffset: CGSize = .zero

    private init() {}

    var title: String {
        switch target {
        case .ai: return "AI 助手"
        case .peer(_, let name): return name
        case .device: return "Hermes 设备"
        }
    }

    var icon: String {
        switch target {
        case .ai: return "sparkles"
        case .peer: return "person.fill"
        case .device: return "desktopcomputer"
        }
    }

    func open(_ newTarget: FloatingTarget) {
        target = newTarget
        isMinimized = false
        offset = .zero
        isShowing = true
    }

    func minimize() {
        isMinimized = true
    }

    func expand() {
        isMinimized = false
    }

    func close() {
        isShowing = false
        isMinimized = false
    }

    func cycleSize() {
        let all = FloatingSize.allCases
        let idx = all.firstIndex(of: size) ?? 1
        size = all[(idx + 1) % all.count]
    }
}
