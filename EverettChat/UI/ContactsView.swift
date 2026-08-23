import SwiftUI

/// 通讯录（系统 List + searchable）
struct ContactsView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchQuery = ""

    private var filteredUsers: [RelayTransport.OnlineUser] {
        let users = appState.conn.onlineUsers
        guard !searchQuery.isEmpty else { return users }
        return users.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
    }

    private var filteredContacts: [Contact] {
        guard !searchQuery.isEmpty else { return appState.contacts }
        return appState.contacts.filter {
            $0.name.localizedCaseInsensitiveContains(searchQuery)
                || String($0.deviceId.prefix(8)).contains(searchQuery)
        }
    }

    var body: some View {
        List {
            Section("我的联系人 (\(appState.contacts.count))") {
                if appState.contacts.isEmpty {
                    Text("暂无联系人，添加后即可长期通信")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(filteredContacts) { contact in
                    ContactRow(contact: contact)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            }

            if !filteredUsers.isEmpty {
                Section("在线用户") {
                    ForEach(filteredUsers) { user in
                        UserRow(user: user, isFriend: appState.contacts.contains { $0.deviceId == user.deviceId })
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .searchable(text: $searchQuery, prompt: "搜索联系人")
        .sheet(isPresented: $appState.showMyQr) { MyQrCodeView() }
    }
}

struct UserRow: View {
    @EnvironmentObject var appState: AppState
    let user: RelayTransport.OnlineUser
    let isFriend: Bool

    var body: some View {
        HStack(spacing: Spacing.md) {
            Circle().fill(Theme.surfaceAlt).frame(width: 40, height: 40)
                .overlay(Image(systemName: "person.fill").font(.system(size: 16)).foregroundColor(Theme.textSecondary))
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
            .disabled(isFriend)
        }
        .padding(.vertical, 2)
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
                Circle().fill(Theme.surfaceAlt).frame(width: 40, height: 40)
                    .overlay(Image(systemName: "person.fill").font(.system(size: 16)).foregroundColor(Theme.textSecondary))
                VStack(alignment: .leading) {
                    Text(contact.name).font(.body.weight(.medium)).foregroundColor(Theme.textPrimary)
                    Text("ID: \(String(contact.deviceId.prefix(8)))").font(.caption.monospaced()).foregroundColor(Theme.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundColor(Theme.textTertiary)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}
