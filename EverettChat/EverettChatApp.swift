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
