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

/// 消息文本链接化：检测 URL（含无前缀域名）生成可点击的 AttributedString
func linkified(_ text: String) -> AttributedString {
    var attributed = AttributedString(text)
    // 匹配：带协议的 URL 或裸域名（example.com/path）
    let pattern = #"(?:https?://)?(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}(?:[/?#][^\s<>"']*)?"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return attributed }
    let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
    for match in regex.matches(in: text, range: nsRange).reversed() {
        guard let range = Range(match.range, in: text) else { continue }
        let raw = String(text[range])
        // 裸域名自动补 https://（应用自动判断）
        let full = raw.hasPrefix("http://") || raw.hasPrefix("https://") ? raw : "https://" + raw
        if let url = URL(string: full) {
            var sub = AttributedString(raw)
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
