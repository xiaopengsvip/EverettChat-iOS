import SwiftUI
import WebKit

/// AI 动画头像视图（WKWebView 加载 SVG 动画，实现呼吸光晕、轨道旋转、粒子闪烁）
/// 用于 AI 思考中 / 空闲等待状态
struct AnimatedAvatarView: View {
    var size: CGFloat = 56

    var body: some View {
        GeometryReader { geo in
            WebViewRepresentable(
                url: Bundle.main.url(forResource: "ai_avatar_animated", withExtension: "svg")!
            )
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(Circle())
            .overlay(Circle().stroke(Theme.outline, lineWidth: 1))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - WKWebView 包装

private struct WebViewRepresentable: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // 禁止用户交互（只显示动画）
        let prefs = WKWebpagePreferences()
        prefs.preferredContentMode = .mobile
        config.defaultWebpagePreferences = prefs

        let web = WKWebView(frame: .zero, configuration: config)
        web.backgroundColor = .clear
        web.isOpaque = false
        web.scrollView.isScrollEnabled = false
        web.isUserInteractionEnabled = false
        web.contentMode = .scaleAspectFit

        // 加载本地 SVG 文件
        web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // 如果 SVG 已加载完成但视图变化，重新加载以确保尺寸正确
        if uiView.isLoading == false {
            uiView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }
}

#Preview("AI 动画头像") {
    VStack(spacing: 20) {
        AnimatedAvatarView(size: 56)
            .frame(width: 56, height: 56)
        AnimatedAvatarView(size: 36)
            .frame(width: 36, height: 36)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}