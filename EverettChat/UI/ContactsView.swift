import SwiftUI

/// 通讯录
struct ContactsView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchQuery = ""

    var body: some View {
        VStack(spacing: 0) {
            // 顶栏（标题居中）
            ZStack {
                Text("通讯录")
                    .font(.title3.bold())
                    .foregroundColor(Theme.textPrimary)
                HStack {
                    Spacer()
                    Button { appState.showMyQr = true } label: {
                        Image(systemName: "qrcode").font(.body).foregroundColor(Theme.textSecondary)
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            // 顶栏与内容区分：深一层的背景色 + 可见分割线
            .background(Theme.bgAlt)
            .overlay(alignment: .bottom) {
                Divider().overlay(Theme.outline)
            }

            // 搜索（液态玻璃材质）
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(Theme.textTertiary)
                TextField("搜索联系人", text: $searchQuery)
                    .font(.body)
                if !searchQuery.isEmpty {
                    Button { searchQuery = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(Theme.textTertiary) }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                            .stroke(Theme.outline, lineWidth: 1)
                    )
            )
            .padding(.horizontal, Spacing.lg)

            // 我的名片
            HStack(spacing: Spacing.md) {
                Circle().fill(Theme.surfaceAlt).frame(width: 44, height: 44)
                    .overlay(Text("👤").font(.title3))
                VStack(alignment: .leading) {
                    Text(appState.deviceName).font(.body.weight(.semibold)).foregroundColor(Theme.textPrimary)
                    Text("我的 ID: \(String(appState.deviceId.prefix(8)))")
                        .font(.caption.monospaced()).foregroundColor(Theme.textTertiary)
                }
                Spacer()
            }
            .padding(Spacing.lg)

            ScrollView {
                // 在线用户
                Text("在线用户").font(.caption).foregroundColor(Theme.textTertiary).padding(.leading, Spacing.lg)
                ForEach(appState.transport.onlineUsers.filter {
                    searchQuery.isEmpty || $0.name.contains(searchQuery)
                }) { user in
                    UserRow(user: user, isFriend: appState.contacts.contains { $0.deviceId == user.deviceId })
                }

                // 我的联系人
                Text("我的联系人 (\(appState.contacts.count))")
                    .font(.caption).foregroundColor(Theme.textTertiary).padding(.leading, Spacing.lg).padding(.top, Spacing.md)
                if appState.contacts.isEmpty {
                    Text("暂无联系人，添加后即可长期通信")
                        .font(.footnote).foregroundColor(Theme.textTertiary).padding(Spacing.lg)
                }
                ForEach(appState.contacts) { contact in
                    ContactRow(contact: contact)
                }
            }
        }
        .background(Theme.bg)
        .sheet(isPresented: $appState.showMyQr) { MyQrCodeView() }
    }
}

struct UserRow: View {
    @EnvironmentObject var appState: AppState
    let user: RelayTransport.OnlineUser
    let isFriend: Bool

    var body: some View {
        HStack(spacing: Spacing.md) {
            Circle().fill(Theme.surfaceAlt).frame(width: 36, height: 36).overlay(Text("👤").font(.subheadline))
            VStack(alignment: .leading) {
                Text(user.name).font(.body.weight(.medium)).foregroundColor(Theme.textPrimary)
                Text("ID: \(String(user.deviceId.prefix(8)))").font(.caption.monospaced()).foregroundColor(Theme.textTertiary)
            }
            Spacer()
            Button(isFriend ? "已添加" : "添加") {
                if !isFriend {
                    appState.sendFriendRequest(targetId: user.deviceId, targetName: user.name)
                }
            }
            .font(.caption.weight(.medium))
            .foregroundColor(isFriend ? Theme.textTertiary : Theme.primary)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
    }
}

struct ContactRow: View {
    @EnvironmentObject var appState: AppState
    let contact: Contact

    var body: some View {
        Button {
            appState.openPeerChat(name: contact.name, peerId: contact.deviceId)
        } label: {
            HStack(spacing: Spacing.md) {
                Circle().fill(Theme.surfaceAlt).frame(width: 36, height: 36).overlay(Text("👤").font(.subheadline))
                VStack(alignment: .leading) {
                    Text(contact.name).font(.body.weight(.medium)).foregroundColor(Theme.textPrimary)
                    Text("ID: \(String(contact.deviceId.prefix(8)))").font(.caption.monospaced()).foregroundColor(Theme.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundColor(Theme.textTertiary)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
        }
        .buttonStyle(.plain)
    }
}