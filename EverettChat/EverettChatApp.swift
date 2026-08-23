import SwiftUI
import UIKit

@main
struct EverettChatApp: App {
    @StateObject private var appState = AppState.shared
    @AppStorage("theme_mode") private var themeMode = "system"

    init() {
        let mode = UserDefaults.standard.string(forKey: "theme_mode") ?? "system"
        AppTheme.apply(mode, systemDark: UITraitCollection.current.userInterfaceStyle == .dark)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(preferredColorScheme())   // @AppStorage 变化 → body 重算 → 实时切换
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .onChange(of: themeMode) { newMode in
                    // 实时应用主题：通知全局重绘
                    AppTheme.apply(newMode, systemDark: UITraitCollection.current.userInterfaceStyle == .dark)
                    NotificationCenter.default.post(name: Notification.Name("EVOThemeChanged"), object: nil)
                }
        }
    }

    /// 灵动岛 / Live Activity 点击跳转：evo://chat/<type>/<id>
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "evo", url.host == "chat" else { return }
        let comps = url.pathComponents.filter { $0 != "/" }
        guard let chatType = comps.first else { return }
        switch chatType {
        case "ai":
            appState.openAIChat()
        case "device":
            appState.openDeviceChat()
        default:
            // peer:<peerId>
            if comps.count >= 2 {
                let peerId = comps[1]
                let peerName = appState.contacts.first(where: { $0.deviceId == peerId })?.name ?? "好友"
                appState.openPeerChat(name: peerName, peerId: peerId)
            }
        }
    }

    /// 动态 preferredColorScheme（@AppStorage 变化时实时生效）
    private func preferredColorScheme() -> ColorScheme? {
        switch themeMode {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil
        }
    }
}
