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
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                TitleBarButton(icon: "plus") {
                                    showAddSheet = true
                                }
                            }
                        }
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
                    Label("发现", systemImage: appState.selectedTab == .discover ? "sparkles" : "sparkles")
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
        }
        // 主题切换时强制重建整棵视图树（实时响应，不残留旧色）
        .id(themeVersion)
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

    private func applyTheme() {
        let mode = UserDefaults.standard.string(forKey: "theme_mode") ?? "system"
        AppTheme.apply(mode, systemDark: colorScheme == .dark)
        themeVersion += 1
    }
}