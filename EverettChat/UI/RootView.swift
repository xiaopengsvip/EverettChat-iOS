import SwiftUI

/// 根视图：Floating Tab Bar + 全屏页面 + 全局弹层
struct RootView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeVersion = 0
    @StateObject private var call = CallManager.shared
    @State private var showCall = false

    var body: some View {
        let _ = themeVersion

        ZStack {
            Theme.bg.ignoresSafeArea()

            // 主界面（Tab）
            MainTabView()
                .opacity(appState.showChat ? 0 : 1)

            // 全屏聊天页
            if appState.showChat {
                ChatView()
                    .transition(.opacity)
            }

            // 全局弹层
            if let req = appState.pendingFriendRequest {
                FriendRequestDialog(request: req)
            }
        }
        // 主题切换时强制重建整棵视图树（实时响应，不残留旧色）
        .id(themeVersion)
        .animation(.easeInOut(duration: 0.2), value: appState.showChat)
        // 全局通话弹窗（来电/去电/通话中）
        .fullScreenCover(isPresented: $showCall) {
            CallView()
        }
        .onChange(of: call.state) { state in
            let active = state == .ringing || state == .outgoing || state == .connecting || state == .inCall
            showCall = active
        }
        .onAppear {
            applyTheme()
            appState.start()
        }
        .onChange(of: colorScheme) { _ in
            applyTheme()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("EVOThemeChanged"))) { _ in
            applyTheme()
        }
    }

    private func applyTheme() {
        let mode = UserDefaults.standard.string(forKey: "theme_mode") ?? "system"
        AppTheme.apply(mode, systemDark: colorScheme == .dark)
        themeVersion += 1
    }
}

/// 主 Tab 界面
struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @State private var showAddSheet = false

    var body: some View {
        Group {
            switch appState.selectedTab {
            case .messages: MessagesView(showAddSheet: $showAddSheet)
            case .contacts: ContactsView()
            case .discover: DiscoverView()
            case .mine: SettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Floating Tab Bar：safeAreaInset 让悬浮栏贴住 Home Indicator 安全区上沿（17 Pro Max 适配）
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FloatingTabBar(selected: $appState.selectedTab)
        }
        // 添加好友 Bottom Sheet
        .sheet(isPresented: $showAddSheet) {
            AddFriendSheet()
        }
    }
}

/// 悬浮底部导航（原生 iOS 风格：薄、透明、系统材质、SF Symbols）
struct FloatingTabBar: View {
    @Binding var selected: MainTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                let isSelected = tab == selected
                Button {
                    selected = tab
                } label: {
                    VStack(spacing: 3) {
                        // SF Symbols（系统图标）
                        Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                            .font(.system(size: 21, weight: isSelected ? .semibold : .regular))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(isSelected ? AnyShapeStyle(Theme.primary) : AnyShapeStyle(Color.secondary))
                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? AnyShapeStyle(Theme.primary) : AnyShapeStyle(Color.secondary))
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        // 系统级材质：极轻、透明、无描边无阴影
        .background(.ultraThinMaterial.opacity(0.75))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.secondary.opacity(0.08))
                .frame(height: 0.5)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.bottom, Spacing.sm)
    }
}

/// 添加好友 Sheet
struct AddFriendSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showScanner = false
    @State private var showMyQr = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("添加好友")
                .font(.headline)
                .padding(Spacing.xl)

            Button {
                showScanner = true
            } label: {
                Label("扫一扫", systemImage: "qrcode.viewfinder")
                    .font(.body)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.xl)
            }

            Divider().padding(.leading, Spacing.xl)

            Button {
                showMyQr = true
            } label: {
                Label("我的二维码", systemImage: "qrcode")
                    .font(.body)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.xl)
            }
            Spacer()
        }
        .background(.regularMaterial)
        .presentationDetents([.height(200)])
        // 在当前页面直接全屏打开扫一扫/二维码（不跳转其他页面）
        .fullScreenCover(isPresented: $showScanner) {
            QrScannerView()
        }
        .fullScreenCover(isPresented: $showMyQr) {
            MyQrCodeView()
        }
    }
}

/// 好友请求弹窗
struct FriendRequestDialog: View {
    @EnvironmentObject var appState: AppState
    let request: (id: String, name: String)

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: Spacing.lg) {
                Text("📥 好友请求")
                    .font(.title3.bold())
                    .foregroundColor(Theme.textPrimary)
                Text("「\(request.name)」请求添加你为联系人")
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
                Text("ID: \(String(request.id.prefix(8)))")
                    .font(.caption.monospaced())
                    .foregroundColor(Theme.textTertiary)
                HStack(spacing: Spacing.md) {
                    Button("拒绝") {
                        appState.pendingFriendRequest = nil
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.surfaceAlt)
                    Button("同意") {
                        appState.pendingFriendRequest = nil
                        // 保存联系人 + 回复同意
                        let contact = Contact(deviceId: request.id, name: request.name, status: "approved")
                        if !appState.contacts.contains(where: { $0.deviceId == request.id }) {
                            appState.contacts.append(contact)
                        }
                        // 通知对方（HTTP）
                        Task {
                            let url = URL(string: "\(PublicRelay.httpURL)/friend-request")!
                            var req = URLRequest(url: url)
                            req.httpMethod = "POST"
                            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                            let body: [String: Any] = ["type": "friend-accept", "target": request.id,
                                                        "from": appState.deviceName, "fromId": appState.deviceId]
                            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
                            try? await URLSession.shared.data(for: req)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.primary)
                }
            }
            .padding(Spacing.xxl)
            .background(
                RoundedRectangle(cornerRadius: Radius.large)
                    .fill(Theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: Radius.large).stroke(Theme.outline, lineWidth: 1))
            )
            .padding(Spacing.xl)
        }
    }
}
