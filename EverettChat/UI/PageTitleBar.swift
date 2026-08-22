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
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        // 顶栏与内容区分：深一层的背景色 + 可见分割线
        .background(Theme.bgAlt)
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
