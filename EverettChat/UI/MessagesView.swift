import SwiftUI

/// 消息页（AI Inbox 风格）
struct MessagesView: View {
    @EnvironmentObject var appState: AppState
    @Binding var showAddSheet: Bool
    @State private var searchQuery = ""

    var body: some View {
        VStack(spacing: 0) {
            // 搜索（系统搜索样式）
            GlassSearchBar(text: $searchQuery, placeholder: "搜索消息")
                .padding(.top, 8)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ConversationRow(
                        icon: "sparkles",
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
                                unread: conv.unread,
                                avatarImage: ProfileStore.shared.friendAvatar(conv.id)
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
    var avatarImage: UIImage? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                // 头像（优先图片，其次 SF Symbol/占位）
                ZStack {
                    Circle()
                        .fill(accent ? Theme.primaryDim : Theme.surfaceAlt)
                    if let avatarImage {
                        Image(uiImage: avatarImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 20))
                            .foregroundColor(accent ? Theme.primary : Theme.textSecondary)
                    }
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
