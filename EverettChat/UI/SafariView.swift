import SwiftUI
import SafariServices

/// 应用内网页浏览器（SFSafariViewController 封装，聊天消息点链接在应用内打开）
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

extension URL: Identifiable {
    public var id: String { absoluteString }
}

/// 消息文本链接化：检测 URL 生成可点击的 AttributedString
func linkified(_ text: String) -> AttributedString {
    var attributed = AttributedString(text)
    // 检测 http(s):// 链接
    let pattern = #"https?://[^\s<>"']+"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return attributed }
    let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
    for match in regex.matches(in: text, range: nsRange).reversed() {
        guard let range = Range(match.range, in: text) else { continue }
        let urlText = String(text[range])
        if let url = URL(string: urlText) {
            var sub = AttributedString(urlText)
            sub.link = url
            sub.foregroundColor = .blue
            sub.underlineStyle = .single
            if let r = Range(match.range, in: attributed) {
                attributed.replaceSubrange(r, with: sub)
            }
        }
    }
    return attributed
}
