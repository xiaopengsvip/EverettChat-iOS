import SwiftUI

/// 主题设置页（单独页面，点击"主题"进入）
struct ThemeView: View {
    @AppStorage("theme_mode") private var themeMode = "system"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            // 跟随系统
            themeRow(value: "system", icon: "iphone", title: "跟随系统",
                     subtitle: "自动匹配 iOS 系统外观设置")
            // 珍珠白
            themeRow(value: "light", icon: "sun.max.fill", title: "珍珠白",
                     subtitle: "浅色模式，细腻珍珠质感")
            // 深邃黑
            themeRow(value: "dark", icon: "moon.fill", title: "深邃黑",
                     subtitle: "深色模式，护眼暗色界面")
        }
        .navigationTitle("主题")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func themeRow(value: String, icon: String, title: String, subtitle: String) -> some View {
        Button {
            themeMode = value
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(themeMode == value ? Theme.primary : Theme.textSecondary)
                    .frame(width: 28, alignment: .center)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundColor(themeMode == value ? Theme.primary : Theme.textPrimary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(Theme.textTertiary)
                }
                Spacer()
                if themeMode == value {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Theme.primary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}