import SwiftUI

/// 消息页（系统 List + searchable）
struct MessagesView: View {
    @EnvironmentObject var appState: AppState
    @Binding var showAddSheet: Bool
    @State private var searchQuery = ""
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
                .contextMenu {
                    Button {
                        FloatingChatManager.shared.open(.ai)
                    } label: {
                        Label("浮窗聊天", systemImage: "rectangle.3.group.bubble")
                    }
                }

                // 设备互联：本机 Hermes（会话持久化，像普通会话一样）
                ConversationRow(
                    icon: "desktopcomputer",
                    name: "Hermes 设备",
                    subtitle: deviceStore.lastMessageText,
                    time: deviceStore.messages.isEmpty ? "" : Self.formatTime(deviceStore.lastMessageTime),
                    accent: false
                ) {
                    appState.openDeviceChat()
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .contextMenu {
                    Button {
                        FloatingChatManager.shared.open(.device)
                    } label: {
                        Label("浮窗聊天", systemImage: "rectangle.3.group.bubble")
                    }
                }
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
                            isOnline: appState.onlineDeviceIds.contains(conv.id),
                            avatarImage: ProfileStore.shared.friendAvatar(conv.id)
                        ) {
                            appState.openPeerChat(name: conv.name, peerId: conv.id)
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .contextMenu {
                            Button {
                                FloatingChatManager.shared.open(.peer(id: conv.id, name: conv.name))
                            } label: {
                                Label("浮窗聊天", systemImage: "rectangle.3.group.bubble")
                            }
                        }
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
    }

    static func formatTime(_ date: Date) -> String {
        // 智能时间：刚刚 / 今天 HH:mm / 今年 M月d日 HH:mm / 跨年 yyyy/M/d
        let cal = Calendar.current
        let now = Date()
        if date.timeIntervalSince(now) > -60 && date <= now.addingTimeInterval(60) {
            return "刚刚"
        }
        let f = DateFormatter()
        if cal.isDateInToday(date) {
            f.dateFormat = "HH:mm"
        } else if cal.isDate(date, equalTo: now, toGranularity: .year) {
            f.dateFormat = "M月d日"
        } else {
            f.dateFormat = "yyyy/M/d"
        }
        return f.string(from: date)
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
    var isOnline: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                // 头像（优先图片，其次 SF Symbol/占位）+ 在线状态点
                ZStack(alignment: .bottomTrailing) {
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
                    // 在线状态点（绿=在线，灰=离线）
                    Circle()
                        .fill(isOnline ? Color(red: 0.20, green: 0.78, blue: 0.35) : Color.gray.opacity(0.6))
                        .frame(width: 13, height: 13)
                        .overlay(Circle().stroke(Theme.bg, lineWidth: 2))
                        .offset(x: 2, y: 2)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(name)
                            .font(.body.weight(.semibold))
                            .foregroundColor(Theme.textPrimary)
                        if isOnline {
                            Text("在线")
                                .font(.caption2)
                                .foregroundColor(Color(red: 0.20, green: 0.78, blue: 0.35))
                        }
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
