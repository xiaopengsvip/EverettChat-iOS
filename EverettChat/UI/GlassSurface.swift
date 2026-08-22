import SwiftUI

/// 原生液态玻璃背景（iOS 26+ 系统 glassEffect，低版本回退 ultraThinMaterial）
/// 用于搜索框、底部导航栏等需要原生玻璃质感的地方
struct GlassSurface: View {
    var cornerRadius: CGFloat = Radius.medium

    var body: some View {
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .glassEffect()
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Theme.outline, lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Theme.outline, lineWidth: 1)
                )
        }
    }
}

/// 搜索框（原生液态玻璃）
struct GlassSearchBar: View {
    @Binding var text: String
    var placeholder: String = "搜索"

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Theme.textTertiary)
            TextField(placeholder, text: $text)
                .font(.body)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(Theme.textTertiary)
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 10)
        .background(GlassSurface(cornerRadius: Radius.medium))
        .padding(.horizontal, Spacing.lg)
    }
}
