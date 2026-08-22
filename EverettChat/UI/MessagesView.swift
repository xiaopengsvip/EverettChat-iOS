import SwiftUI

/// 消息页（AI Inbox 风格）
struct MessagesView: View {
    @EnvironmentObject var appState: AppState
    @Binding var showAddSheet: Bool

    var body: some View {
        VStack(spacing: 0) {
            // 顶栏（标题居中）
            ZStack {
                Text("消息")
                    .font(.title3.bold())
                    .foregroundColor(Theme.textPrimary)
                HStack {
                    Spacer()
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .light))
                            .foregroundColor(Theme.textPrimary)
                            .frame(width: 36, height: 36)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surfaceHigh))
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            // 顶栏与内容区分：原生材质背景 + 底部细分隔线
            .background(.thinMaterial)
            .overlay(alignment: .bottom) {
                Divider().overlay(Theme.surfaceHigh)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    // AI 助手固定置顶
                    ConversationRow(
                        icon: "🤖",
                        name: "AI 助手",
                        subtitle: appState.aiMessages.last?.text ?? "开始聊天吧",
                        time: appState.aiMessages.isEmpty ? "" : "现在",
                        accent: true
                    ) {
                        appState.openAIChat()
                    }
                    Divider().overlay(Theme.surfaceHigh).padding(.leading, 64)

                    // 对端会话（按名去重）
                    let peerConvs = appState.conversations
                        .filter { $0.type == "peer" }
                        .sorted { $0.lastTime > $1.lastTime }
                    if peerConvs.isEmpty {
                        VStack(spacing: Spacing.md) {
                            Spacer().frame(height: 80)
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 40))
                                .foregroundColor(Theme.textTertiary)
                            Text("还没有聊天记录")
                                .font(.subheadline)
                                .foregroundColor(Theme.textSecondary)
                            Text("在「发现」连接设备，或在「通讯录」添加好友后开始加密聊天")
                                .font(.caption)
                                .foregroundColor(Theme.textTertiary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                    } else {
                        ForEach(peerConvs) { conv in
                            ConversationRow(
                                icon: "👤",
                                name: conv.name,
                                subtitle: conv.lastText,
                                time: Self.formatTime(conv.lastTime),
                                unread: conv.unread
                            ) {
                                appState.openPeerChat(name: conv.name, peerId: conv.id)
                            }
                            Divider().overlay(Theme.surfaceHigh).padding(.leading, 64)
                        }
                    }
                }
            }
        }
        .background(Theme.bg)
    }

    static func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

/// 会话行
struct ConversationRow: View {
    let icon: String
    let name: String
    let subtitle: String
    let time: String
    var unread: Int = 0
    var accent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                // 头像
                ZStack {
                    Circle()
                        .fill(accent ? Theme.primaryDim : Theme.surfaceAlt)
                    Text(icon)
                        .font(.system(size: 22))
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(name)
                            .font(.body.weight(.semibold))
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        Text(time)
                            .font(.caption2)
                            .foregroundColor(Theme.textTertiary)
                    }
                    HStack {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundColor(Theme.textSecondary)
                            .lineLimit(1)
                        Spacer()
                        if unread > 0 {
                            Text("\(unread)")
                                .font(.caption2.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Theme.error))
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
