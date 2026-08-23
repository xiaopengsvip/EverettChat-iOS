import SwiftUI
import UIKit

@main
struct EverettChatApp: App {
    @StateObject private var appState = AppState.shared

    init() {
        let mode = UserDefaults.standard.string(forKey: "theme_mode") ?? "system"
        AppTheme.apply(mode, systemDark: UITraitCollection.current.userInterfaceStyle == .dark)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(Self.preferredColorScheme())
                .onOpenURL { url in
                    handleDeepLink(url)
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

    private static func preferredColorScheme() -> ColorScheme? {
        let mode = UserDefaults.standard.string(forKey: "theme_mode") ?? "system"

        switch mode {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil
        }
    }
}
