import SwiftUI

/// 存储管理页（架构第八节：分类占用显示 + 清理缓存）
struct StorageManagerView: View {
    @Environment(\.dismiss) private var dismiss

    // 占用统计（估算）
    @State private var chatCount = 0
    @State private var imageCount = 0
    @State private var voiceCount = 0
    @State private var fileCount = 0
    @State private var cacheSize: Int64 = 0
    @State private var cleaned = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // 总占用概览
                    VStack(spacing: 6) {
                        Text("\(formatBytes(totalSize))")
                            .font(.system(size: 34, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.textPrimary)
                        Text("本地存储占用（估算）")
                            .font(.caption)
                            .foregroundColor(Theme.textTertiary)
                    }
                    .padding(.vertical, 20)

                    // 分类
                    VStack(spacing: 0) {
                        StorageRow(icon: "bubble.left.and.bubble.right", name: "聊天记录", detail: "\(chatCount) 条消息", size: chatSize)
                        Divider().overlay(Theme.surfaceHigh).padding(.leading, 52)
                        StorageRow(icon: "photo", name: "图片", detail: "\(imageCount) 张", size: imageSize)
                        Divider().overlay(Theme.surfaceHigh).padding(.leading, 52)
                        StorageRow(icon: "waveform", name: "语音", detail: "\(voiceCount) 条", size: voiceSize)
                        Divider().overlay(Theme.surfaceHigh).padding(.leading, 52)
                        StorageRow(icon: "folder", name: "文件", detail: "\(fileCount) 个", size: fileSize)
                        Divider().overlay(Theme.surfaceHigh).padding(.leading, 52)
                        StorageRow(icon: "trash", name: "缓存", detail: "临时文件", size: cacheSize)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: Radius.medium)
                            .fill(Theme.surface)
                            .overlay(RoundedRectangle(cornerRadius: Radius.medium).stroke(Theme.outline, lineWidth: 1))
                    )
                    .padding(.horizontal, Spacing.lg)

                    // 清理按钮
                    Button {
                        clearCache()
                    } label: {
                        Label(cleaned ? "✓ 缓存已清理" : "清理缓存", systemImage: "trash")
                            .font(.body.weight(.medium))
                            .foregroundColor(cleaned ? Theme.success : Theme.error)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.medium)
                                    .fill(cleaned ? Theme.success.opacity(0.12) : Theme.error.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, 8)
                    .disabled(cleaned)

                    Text("清理缓存不会删除聊天记录")
                        .font(.caption2)
                        .foregroundColor(Theme.textTertiary)
                        .padding(.top, 4)
                }
                .padding(.vertical, Spacing.md)
            }
            .navigationTitle("存储管理")
            .navigationBarTitleDisplayMode(.inline)
        }
        .background(Theme.bg)
        .onAppear(perform: scan)
    }

    // MARK: - 统计

    private func scan() {
        let stored = MessageStore.loadAll()
        chatCount = stored.aiMessages.count + stored.peerMessages.count
        imageCount = stored.aiMessages.filter { !$0.imageBase64.isEmpty }.count + stored.peerMessages.filter { !$0.imageBase64.isEmpty }.count
        voiceCount = stored.aiMessages.filter { !$0.voiceBase64.isEmpty }.count + stored.peerMessages.filter { !$0.voiceBase64.isEmpty }.count

        // 缓存：临时目录
        if let tmp = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
           let files = try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: [.fileSizeKey]) {
            cacheSize = files.reduce(Int64(0)) { partial, url in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return partial + Int64(size)
            }
        }
    }

    private func clearCache() {
        if let tmp = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            for url in (try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? [] {
                try? FileManager.default.removeItem(at: url)
            }
        }
        cacheSize = 0
        cleaned = true
    }

    // MARK: - 估算大小

    private var chatSize: Int64 {
        let stored = MessageStore.loadAll()
        return Int64(stored.aiMessages.reduce(0) { $0 + $1.text.utf8.count } + stored.peerMessages.reduce(0) { $0 + $1.text.utf8.count })
    }

    private var imageSize: Int64 {
        let stored = MessageStore.loadAll()
        let all = stored.aiMessages + stored.peerMessages
        return Int64(all.filter { !$0.imageBase64.isEmpty }.reduce(0) { $0 + $1.imageBase64.utf8.count })
    }

    private var voiceSize: Int64 {
        let stored = MessageStore.loadAll()
        let all = stored.aiMessages + stored.peerMessages
        return Int64(all.filter { !$0.voiceBase64.isEmpty }.reduce(0) { $0 + $1.voiceBase64.utf8.count })
    }

    private var fileSize: Int64 {
        // 文件走文本通道存储，计入聊天
        0
    }

    private var totalSize: Int64 {
        chatSize + imageSize + voiceSize + cacheSize
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: max(bytes, 0))
    }
}

/// 存储分类行
struct StorageRow: View {
    let icon: String
    let name: String
    let detail: String
    let size: Int64

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundColor(Theme.primary)
                .frame(width: 28)
            VStack(alignment: .leading) {
                Text(name).font(.body.weight(.medium)).foregroundColor(Theme.textPrimary)
                Text(detail).font(.caption).foregroundColor(Theme.textTertiary)
            }
            Spacer()
            Text(formatSize)
                .font(.caption.monospacedDigit())
                .foregroundColor(Theme.textSecondary)
        }
        .padding(Spacing.lg)
    }

    private var formatSize: String {
        ByteCountFormatter.string(fromByteCount: max(size, 0), countStyle: .file)
    }
}
