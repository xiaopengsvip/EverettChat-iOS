import SwiftUI
import UIKit

/// 我的页（设置）
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showAutoDelete = false
    @State private var showRecoveryKey = false
    @State private var showRestore = false
    @State private var restoreInput = ""
    @State private var restoreResult: String? = nil
    @State private var showMyQr = false
    @State private var webURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            // 顶栏（统一 PageTitleBar）
            PageTitleBar(title: "设置")

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 用户卡片（点击二维码可查看）
                    HStack(spacing: Spacing.md) {
                        Circle().fill(Theme.surfaceAlt).frame(width: 52, height: 52).overlay(Text("👤").font(.title3))
                        VStack(alignment: .leading) {
                            Text(appState.deviceName).font(.body.weight(.semibold)).foregroundColor(Theme.textPrimary)
                            Text("唯一 ID: \(String(appState.deviceId.prefix(8)))")
                                .font(.caption.monospaced()).foregroundColor(Theme.textTertiary)
                        }
                        Spacer()
                        // 二维码按钮：点击查看我的二维码
                        Button {
                            showMyQr = true
                        } label: {
                            Image(systemName: "qrcode")
                                .font(.system(size: 20))
                                .foregroundColor(Theme.primary)
                                .frame(width: 40, height: 40)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.primaryDim))
                        }
                    }
                    .padding(Spacing.lg)
                    .contentShape(Rectangle())

                    sectionHeader("外观")
                    VStack(spacing: 0) {
                        ThemeModeRow(title: "跟随系统", mode: "system") {
                            applyThemeMode("system")
                        }
                        Divider().overlay(Theme.surfaceHigh).padding(.leading, Spacing.lg)
                        ThemeModeRow(title: "珍珠白 · Pearl White", mode: "light") {
                            applyThemeMode("light")
                        }
                        Divider().overlay(Theme.surfaceHigh).padding(.leading, Spacing.lg)
                        ThemeModeRow(title: "深邃黑 · Deep Black", mode: "dark") {
                            applyThemeMode("dark")
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: Radius.medium)
                            .fill(Theme.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.medium)
                                    .stroke(Theme.outline, lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, Spacing.lg)

                    sectionHeader("设备与通用")
                    settingsCard {
                        SettingRow(icon: "✏️", title: "设备名称", subtitle: appState.deviceName) {
                            // 改名（简化为随机换名）
                            _ = DeviceIdentity.shared.rerollName()
                            appState.objectWillChange.send()
                        }
                        Divider().overlay(Theme.surfaceHigh).padding(.leading, 52)
                        SettingRow(icon: "🔋", title: "后台保活", subtitle: "前台保活 · 电池优化白名单") {}
                        Divider().overlay(Theme.surfaceHigh).padding(.leading, 52)
                        SettingRow(icon: "🛰", title: "中继服务器", subtitle: "已配置 · \(PublicRelay.httpURL)") {}
                        Divider().overlay(Theme.surfaceHigh).padding(.leading, 52)
                        // 自动删除消息（TTL）
                        let autoDays = UserDefaults.standard.integer(forKey: "auto_delete_days")
                        SettingRow(icon: "⏱", title: "自动删除消息", subtitle: autoDays == 0 ? "不自动删除" : "保留 \(autoDays) 天") {
                            showAutoDelete = true
                        }
                        Divider().overlay(Theme.surfaceHigh).padding(.leading, 52)
                        SettingRow(icon: "📝", title: "反馈", subtitle: "问题与建议") {}
                    }

                    sectionHeader("身份")
                    settingsCard {
                        SettingRow(icon: "🔑", title: "恢复密钥", subtitle: "保存此密钥，换机可恢复身份") {
                            showRecoveryKey = true
                        }
                        Divider().overlay(Theme.surfaceHigh).padding(.leading, 52)
                        SettingRow(icon: "♻️", title: "恢复身份", subtitle: "输入恢复密钥找回身份") {
                            showRestore = true
                        }
                    }

                    sectionHeader("关于")
                    settingsCard {
                        SettingRow(icon: "📱", title: "版本", subtitle: "v1.0.0 · iOS") {}
                        Divider().overlay(Theme.surfaceHigh).padding(.leading, 52)
                        SettingRow(icon: "🌐", title: "官网", subtitle: "vios.top") { openWeb("https://vios.top/") }
                        Divider().overlay(Theme.surfaceHigh).padding(.leading, 52)
                        SettingRow(icon: "👨‍💻", title: "开发者信息", subtitle: "linktr.vios.top") { openWeb("https://linktr.vios.top/") }
                        Divider().overlay(Theme.surfaceHigh).padding(.leading, 52)
                        SettingRow(icon: "✉️", title: "邮箱", subtitle: "EVO@vios.top") {
                            if let url = URL(string: "mailto:EVO@vios.top") {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                }
            }
        }
        .background(Theme.bg)
        // 我的二维码：当前页面直接全屏打开（不跳转）
        .fullScreenCover(isPresented: $showMyQr) {
            MyQrCodeView()
        }
        // 官网/开发者信息：应用内打开（不跳出 Safari）
        .fullScreenCover(item: $webURL) { url in
            SafariView(url: url)
        }
        // 恢复密钥展示
        .alert("恢复密钥", isPresented: $showRecoveryKey) {
            Button("复制") {
                UIPasteboard.general.string = DeviceIdentity.shared.recoveryKey
            }
            Button("完成", role: .cancel) {}
        } message: {
            Text("""
            请保存此密钥（换机或重装时输入可恢复身份）：

            \(DeviceIdentity.shared.recoveryKey)
            """)
        }
        // 恢复身份
        .alert("恢复身份", isPresented: $showRestore) {
            TextField("输入恢复密钥", text: $restoreInput)
            Button("恢复") {
                if DeviceIdentity.shared.restore(fromRecoveryKey: restoreInput) {
                    restoreResult = "✅ 身份已恢复\n新 ID: \(DeviceIdentity.shared.shortId)\n请重新添加好友"
                } else {
                    restoreResult = "❌ 恢复密钥无效"
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(restoreResult ?? "输入之前保存的恢复密钥")
        }
        // 自动删除天数选择
        .confirmationDialog("自动删除消息", isPresented: $showAutoDelete, titleVisibility: .visible) {
            Button("不自动删除") { setAutoDelete(0) }
            Button("1 天") { setAutoDelete(1) }
            Button("7 天") { setAutoDelete(7) }
            Button("30 天") { setAutoDelete(30) }
            Button("90 天") { setAutoDelete(90) }
            Button("取消", role: .cancel) {}
        }
    }

    private func setAutoDelete(_ days: Int) {
        UserDefaults.standard.set(days, forKey: "auto_delete_days")
        appState.applyAutoDelete()
    }

    /// 应用内打开网页（不跳出 Safari）
    private func openWeb(_ urlString: String) {
        if let url = URL(string: urlString) {
            webURL = url
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundColor(Theme.textTertiary)
            .padding(.leading, Spacing.lg)
            .padding(.top, Spacing.md)
            .padding(.bottom, 4)
    }

    /// 统一设置卡片容器（圆角 + 边框）
    @ViewBuilder
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.medium)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.medium)
                        .stroke(Theme.outline, lineWidth: 1)
                )
        )
        .padding(.horizontal, Spacing.lg)
    }

    private func applyThemeMode(_ mode: String) {
        UserDefaults.standard.set(mode, forKey: "theme_mode")
        AppTheme.apply(mode, systemDark: UITraitCollection.current.userInterfaceStyle == .dark)
        NotificationCenter.default.post(name: Notification.Name("EVOThemeChanged"), object: nil)
    }
}

struct ThemeModeRow: View {
    let title: String
    let mode: String
    let action: () -> Void

    private var isSelected: Bool {
        (UserDefaults.standard.string(forKey: "theme_mode") ?? "system") == mode
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                Text(title)
                    .font(.body)
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                if isSelected {
                    Text("✓")
                        .font(.body.weight(.semibold))
                        .foregroundColor(Theme.primary)
                }
            }
            .padding(Spacing.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SettingRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(icon).font(.body)
                VStack(alignment: .leading) {
                    Text(title).font(.body).foregroundColor(Theme.textPrimary)
                    Text(subtitle).font(.caption).foregroundColor(Theme.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundColor(Theme.textTertiary)
            }
            .padding(Spacing.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        Divider().overlay(Theme.surfaceHigh).padding(.leading, 56)
    }
}
