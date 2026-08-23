import SwiftUI

// MARK: - Design System：AppTypography / AppSpacing / AppMaterials

/// 统一字体（SF Pro / Dynamic Type）
enum AppTypography {
    static let navTitle = Font.headline                       // 导航标题
    static let title = Font.title3                            // 页面大标题
    static let body = Font.body
    static let subhead = Font.subheadline
    static let caption = Font.caption
    static let caption2 = Font.caption2
}

/// 统一间距
enum AppSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
}

/// 系统材质分级（Liquid Glass 使用层级）
/// Level 0: 内容（不用 Glass）
/// Level 1: 导航/搜索（极轻系统材质）
/// Level 2: 交互控件（明显玻璃）
/// Level 3: 浮层（明显 Liquid Glass）
enum AppMaterials {
    /// Level 1：极轻系统材质（导航栏/搜索框）
    static func level1(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
    }

    /// Level 2：交互控件（+ 按钮等）
    static func level2(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.thinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 0.5)
            )
    }

    /// Level 3：浮层（菜单/弹窗）
    static func level3(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.1), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
    }
}

// MARK: - 统一顶部导航栏（原生 iOS NavigationBar 视觉）

/// Level 1 导航栏：系统材质 + 无厚重边框 + 无胶囊
/// 结构：左侧（可选） + 居中标题 + 右侧按钮，功能层级清晰
struct PageTitleBar<Leading: View, Trailing: View>: View {
    let title: String
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    init(title: String,
         @ViewBuilder leading: @escaping () -> Leading = { EmptyView() },
         @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        ZStack {
            // 居中标题（系统 Dynamic Type）
            Text(title)
                .font(AppTypography.navTitle)
                .foregroundColor(.primary)
                .lineLimit(1)

            // 左侧 + 右侧
            HStack {
                leading()
                Spacer()
                trailing()
            }
        }
        .frame(minHeight: 40)
        .padding(.horizontal, AppSpacing.md)
        // 原生导航栏视觉：透明背景 + 极轻材质 + 若隐若现分隔线
        .background(.ultraThinMaterial.opacity(0.6))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
                .frame(height: 0.5)
        }
    }
}

/// 顶栏右侧圆形按钮（Level 2 玻璃，独立功能层级）
struct TitleBarButton: View {
    let icon: String
    var size: CGFloat = 34
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.primary)
                .frame(width: size, height: size)
                .background(AppMaterials.level2(cornerRadius: size / 2))
        }
        .buttonStyle(.plain)
    }
}
