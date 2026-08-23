import SwiftUI

/// 根视图：系统 TabView + NavigationStack + 全局弹层
struct RootView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeVersion = 0
    @StateObject private var call = CallManager.shared
    @State private var showCall = false
    @State private var showAddSheet = false

    var body: some View {
        let _ = themeVersion

        ZStack {
            // 系统 TabView（iOS 27 自动 Liquid Glass 材质，无需自定义）
            TabView(selection: $appState.selectedTab) {
                NavigationStack {
                    MessagesView(showAddSheet: $showAddSheet)
                        .navigationTitle("消息")
                }
                .tabItem {
                    Label("消息", systemImage: appState.selectedTab == .messages ? "message.fill" : "message")
                }
                .tag(MainTab.messages)

                NavigationStack {
                    ContactsView()
                        .navigationTitle("通讯录")
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                TitleBarButton(icon: "qrcode") {
                                    appState.showMyQr = true
                                }
                            }
                        }
                }
                .tabItem {
                    Label("通讯录", systemImage: appState.selectedTab == .contacts ? "person.2.fill" : "person.2")
                }
                .tag(MainTab.contacts)

                NavigationStack {
                    DiscoverView()
                        .navigationTitle("发现")
                        .navigationBarTitleDisplayMode(.inline)
                }
                .tabItem {
                    Label("发现", systemImage: appState.selectedTab == .discover ? "sparkles" : "square.grid.2x2")
                }
                .tag(MainTab.discover)

                NavigationStack {
                    SettingsView()
                        .navigationTitle("设置")
                        .navigationBarTitleDisplayMode(.inline)
                }
                .tabItem {
                    Label("我的", systemImage: appState.selectedTab == .mine ? "person.fill" : "person")
                }
                .tag(MainTab.mine)
            }
            // 品牌紫色 tint（只作为选中色，不作为背景）
            .tint(Theme.primary)

            // 全屏聊天页（覆盖 TabView）
            if appState.showChat {
                ChatView()
                    .transition(.opacity)
            }

            // 全局弹层
            if let req = appState.pendingFriendRequest {
                FriendRequestDialog(request: req)
            }

            // 全局浮窗聊天（跨 Tab 常驻：AI 助手/好友会话/Hermes 设备）
            FloatingChatView()
                .zIndex(100)
        }
        // 主题切换时强制重建整棵视图树（实时响应，不残留旧色）
        .id(themeVersion)
        // 主题模式 → 系统色系（light/dark/system 跟随）
        .preferredColorScheme(themeColorScheme)
        .animation(.easeInOut(duration: 0.2), value: appState.showChat)
        // 全局通话弹窗
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
        // 添加好友 Sheet（从 + 按钮展开）
        .sheet(isPresented: $showAddSheet) {
            AddFriendSheet()
        }
        .sheet(isPresented: $appState.showQrScanner) {
            QrScannerView()
        }
        .sheet(isPresented: $appState.showMyQr) {
            MyQrCodeView()
        }
    }

    private var themeColorScheme: ColorScheme? {
        switch UserDefaults.standard.string(forKey: "theme_mode") ?? "system" {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private func applyTheme() {
        let mode = UserDefaults.standard.string(forKey: "theme_mode") ?? "system"
        AppTheme.apply(mode, systemDark: colorScheme == .dark)
        themeVersion += 1
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
                Image(systemName: "person.badge.plus")
                    .font(.title2)
                    .foregroundColor(Theme.primary)
                Text("好友请求")
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
                        let contact = Contact(deviceId: request.id, name: request.name, status: "approved")
                        if !appState.contacts.contains(where: { $0.deviceId == request.id }) {
                            appState.contacts.append(contact)
                        }
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
