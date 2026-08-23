import SwiftUI

/// 统一顶部标题栏（消息页标准）：ZStack 居中标题 + 可选右侧操作按钮 + 深色背景 + 分割线
struct PageTitleBar: View {
    let title: String
    var trailing: AnyView?

    init(title: String, @ViewBuilder trailing: () -> some View = { EmptyView() }) {
        self.title = title
        self.trailing = AnyView(trailing())
    }

    var body: some View {
        ZStack {
            Text(title)
                .font(.title3.bold())
                .foregroundColor(Theme.textPrimary)
            HStack {
                Spacer()
                if let trailing {
                    trailing
                }
            }
        }
        // 固定标题栏最小高度（32pt = 按钮高度），无按钮页不塌陷，四页高度一致
        .frame(minHeight: 32)
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        // 原生液态玻璃背景（无灰色层）+ 底部细分隔线区分内容
        .background(GlassSurface(cornerRadius: 0))
        .overlay(alignment: .bottom) {
            Divider().overlay(Theme.outline)
        }
    }
}

/// 顶栏右侧圆形操作按钮（消息页标准样式）
struct TitleBarButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .light))
                .foregroundColor(Theme.textPrimary)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 9).fill(Theme.surfaceHigh))
        }
    }
}
