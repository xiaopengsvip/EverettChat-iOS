import SwiftUI

/// 消息页（系统 List + searchable）
struct MessagesView: View {
    @EnvironmentObject var appState: AppState
    @Binding var showAddSheet: Bool
    @State private var searchQuery = ""
    @State private var showDeviceLink = false
    @StateObject private var deviceStore = DeviceLinkStore.shared

    private var filteredPeers: [Conversation] {
        let peers = appState.conversations
            .filter { $0.type == "peer" }
            .sorted { $0.lastTime > $1.lastTime }
        guard !searchQuery.isEmpty else { return peers }
        return peers.filter {
            $0.name.localizedCaseInsensitiveContains(searchQuery)
                || $0.lastText.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    var body: some View {
        List {
            Section {
                ConversationRow(
                    icon: "sparkles",
                    name: "AI 助手",
                    subtitle: appState.aiMessages.last?.text ?? "开始聊天吧",
                    time: appState.aiMessages.isEmpty ? "" : "现在",
                    accent: true
                ) {
                    appState.openAIChat()
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))

                // 设备互联：本机 Hermes（会话持久化，像普通会话一样）
                ConversationRow(
                    icon: "desktopcomputer",
                    name: "Hermes 设备",
                    subtitle: deviceStore.lastMessageText,
                    time: deviceStore.messages.isEmpty ? "" : Self.formatTime(deviceStore.lastMessageTime),
                    accent: false
                ) {
                    showDeviceLink = true
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }

            if filteredPeers.isEmpty {
                Section {
                    VStack(spacing: Spacing.md) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 40))
                            .foregroundStyle(.tertiary)
                        Text(searchQuery.isEmpty ? "还没有聊天记录" : "没有匹配的会话")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("在「发现」连接设备，或在「通讯录」添加好友后开始加密聊天")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(filteredPeers) { conv in
                        ConversationRow(
                            icon: "person.crop.circle",
                            name: conv.name,
                            subtitle: conv.lastText,
                            time: Self.formatTime(conv.lastTime),
                            unread: conv.unread,
                            avatarImage: ProfileStore.shared.friendAvatar(conv.id)
                        ) {
                            appState.openPeerChat(name: conv.name, peerId: conv.id)
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .searchable(text: $searchQuery, prompt: "搜索消息")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                TitleBarButton(icon: "plus") { showAddSheet = true }
            }
        }
        .sheet(isPresented: $showDeviceLink) {
            DeviceLinkView()
        }
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
                            Text("\\(unread)")
                                .font(.caption2.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Theme.error))
                        }
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
