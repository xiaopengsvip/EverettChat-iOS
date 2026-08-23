import SwiftUI

/// 统一搜索框（Level 1：轻量系统材质，模拟原生 .searchable 视觉）
struct GlassSearchBar: View {
    @Binding var text: String
    var placeholder: String = "搜索"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
            TextField(placeholder, text: $text)
                .font(.body)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(
            // 原生搜索框视觉：非常轻的填充，无描边
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
        )
        .padding(.horizontal, Spacing.lg)
    }
}
