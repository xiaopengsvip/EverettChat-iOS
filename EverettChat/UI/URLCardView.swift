import SwiftUI
import UIKit

/// URL 链接卡片（标题 + 封面预览，OpenGraph 解析）
/// 检测消息中的 URL → 气泡下方显示卡片 → 点击应用内打开
struct URLCardView: View {
    let urlString: String
    let onOpen: (URL) -> Void

    @State private var title: String = ""
    @State private var siteName: String = ""
    @State private var coverImage: UIImage? = nil
    @State private var loaded = false
    @State private var failed = false

    var body: some View {
        Button {
            if let url = URL(string: urlString) {
                onOpen(url)
            }
        } label: {
            HStack(spacing: 10) {
                // 封面
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(width: 56, height: 56)
                    if let coverImage {
                        Image(uiImage: coverImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        Image(systemName: "link")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                    }
                }

                // 标题 + 域名
                VStack(alignment: .leading, spacing: 3) {
                    Text(title.isEmpty ? hostName : title)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    Text(siteName.isEmpty ? hostName : siteName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear { fetchMetadata() }
    }

    private var hostName: String {
        URL(string: urlString)?.host ?? urlString
    }

    /// 抓取 OpenGraph 元数据（og:title / og:image / og:site_name）
    private func fetchMetadata() {
        guard !loaded, !failed, let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12
        URLSession.shared.dataTask(with: request) { data, resp, _ in
            guard let data,
                  let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
                  let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200 else {
                DispatchQueue.main.async { failed = true }
                return
            }
            let ogTitle = Self.ogValue(html, key: "og:title")
            let ogSite = Self.ogValue(html, key: "og:site_name")
            let ogImage = Self.ogValue(html, key: "og:image")
            let htmlTitle = Self.htmlTitle(html)

            DispatchQueue.main.async {
                title = ogTitle ?? htmlTitle ?? ""
                siteName = ogSite ?? ""
                loaded = true
                // 加载封面图
                if let ogImage, let imgURL = URL(string: ogImage, relativeTo: url).flatMap({ $0.absoluteString.contains("http") ? $0 : URL(string: ogImage) }) {
                    loadImage(imgURL)
                }
            }
        }.resume()
    }

    private func loadImage(_ url: URL) {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data, let img = UIImage(data: data) else { return }
            DispatchQueue.main.async { coverImage = img }
        }.resume()
    }

    /// 提取 og meta 值
    private static func ogValue(_ html: String, key: String) -> String? {
        let patterns = [
            "property=\"\(key)\"\\s+content=\"([^\"]*)\"",
            "property='\(key)'\\s+content='([^']*)'",
            "content=\"([^\"]*)\"\\s+property=\"\(key)\"",
            "content='([^']*)'\\s+property='\(key)'"
        ]
        for p in patterns {
            if let regex = try? NSRegularExpression(pattern: p),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                return String(html[range])
            }
        }
        return nil
    }

    private static func htmlTitle(_ html: String) -> String? {
        let pattern = "<title[^>]*>([^<]*)</title>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
