import SwiftUI

/// 我的页（设置）
struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("设置")
                    .font(.title3.bold())
                    .foregroundColor(Theme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)

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

                    sectionHeader("设备")
                    SettingRow(icon: "✏️", title: "设备名称", subtitle: appState.deviceName) {
                        // 改名（简化为随机换名）
                        _ = DeviceIdentity.shared.rerollName()
                        appState.objectWillChange.send()
                    }

                    sectionHeader("通用")
                    SettingRow(icon: "🔋", title: "后台保活", subtitle: "前台保活 · 电池优化白名单") {}
                    SettingRow(icon: "🛰", title: "中继服务器", subtitle: "已配置 · \(PublicRelay.httpURL)") {}
                    SettingRow(icon: "📝", title: "反馈", subtitle: "问题与建议") {}

                    sectionHeader("关于")
                    SettingRow(icon: "📱", title: "版本", subtitle: "v1.0.0 · iOS") {}
                }
            }
        }
        .background(Theme.bg)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundColor(Theme.textTertiary)
            .padding(.leading, Spacing.lg)
            .padding(.top, Spacing.md)
            .padding(.bottom, 4)
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
