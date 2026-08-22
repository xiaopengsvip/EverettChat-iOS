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

    var body: some View {
        VStack(spacing: 0) {
            // 顶栏（标题居中）
            ZStack {
                Text("设置")
                    .font(.title3.bold())
                    .foregroundColor(Theme.textPrimary)
                HStack {
                    Spacer()
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            // 顶栏与内容区分：原生材质背景 + 底部细分隔线
            .background(.thinMaterial)
            .overlay(alignment: .bottom) {
                Divider().overlay(Theme.surfaceHigh)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 用户卡片
                    HStack(spacing: Spacing.md) {
                        Circle().fill(Theme.surfaceAlt).frame(width: 52, height: 52).overlay(Text("👤").font(.title3))
                        VStack(alignment: .leading) {
                            Text(appState.deviceName).font(.body.weight(.semibold)).foregroundColor(Theme.textPrimary)
                            Text("唯一 ID: \(String(appState.deviceId.prefix(8)))")
                                .font(.caption.monospaced()).foregroundColor(Theme.textTertiary)
                        }
                        Spacer()
                    }
                    .padding(Spacing.lg)

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

                    sectionHeader("设备")
                    SettingRow(icon: "✏️", title: "设备名称", subtitle: appState.deviceName) {
                        // 改名（简化为随机换名）
                        _ = DeviceIdentity.shared.rerollName()
                        appState.objectWillChange.send()
                    }

                    sectionHeader("通用")
                    SettingRow(icon: "🔋", title: "后台保活", subtitle: "前台保活 · 电池优化白名单") {}
                    SettingRow(icon: "🛰", title: "中继服务器", subtitle: "已配置 · \(PublicRelay.httpURL)") {}
                    // 自动删除消息（TTL）
                    let autoDays = UserDefaults.standard.integer(forKey: "auto_delete_days")
                    SettingRow(icon: "⏱", title: "自动删除消息", subtitle: autoDays == 0 ? "不自动删除" : "保留 \(autoDays) 天") {
                        showAutoDelete = true
                    }
                    SettingRow(icon: "📝", title: "反馈", subtitle: "问题与建议") {}

                    sectionHeader("身份")
                    SettingRow(icon: "🔑", title: "恢复密钥", subtitle: "保存此密钥，换机可恢复身份") {
                        showRecoveryKey = true
                    }
                    SettingRow(icon: "♻️", title: "恢复身份", subtitle: "输入恢复密钥找回身份") {
                        showRestore = true
                    }

                    sectionHeader("关于")
                    SettingRow(icon: "📱", title: "版本", subtitle: "v1.0.0 · iOS") {}
                }
            }
        }
        .background(Theme.bg)
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

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundColor(Theme.textTertiary)
            .padding(.leading, Spacing.lg)
            .padding(.top, Spacing.md)
            .padding(.bottom, 4)
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
