import SwiftUI
import UIKit
import AVKit
import Photos

extension UIImage: Identifiable {
    public var id: String { "img-\(hashValue)" }
}

extension String: Identifiable {
    public var id: String { self }
}

// MARK: - 图片全屏预览

struct FullscreenImageView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            // 支持缩放
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            // 关闭按钮
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding()
                }
                Spacer()
                // 保存按钮
                Button {
                    saveToAlbum()
                } label: {
                    Label("保存到相册", systemImage: "square.and.arrow.down")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(.white.opacity(0.2)))
                }
                .padding(.bottom, 30)
            }
        }
    }

    private func saveToAlbum() {
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        } completionHandler: { success, _ in
            // 结果提示（简单处理：无 UI 反馈）
        }
    }
}

// MARK: - 视频全屏播放 + 保存

struct FullscreenVideoView: View {
    let videoBase64: String
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding()
                }
                Spacer()
                // 保存视频
                Button {
                    saveToAlbum()
                } label: {
                    Label("保存视频", systemImage: "square.and.arrow.down")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(.white.opacity(0.2)))
                }
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            guard let data = Data(base64Encoded: videoBase64) else { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("play_\(Date().timeIntervalSince1970).mp4")
            try? data.write(to: url)
            player = AVPlayer(url: url)
            player?.play()
        }
    }

    private func saveToAlbum() {
        guard let data = Data(base64Encoded: videoBase64) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("save_\(Date().timeIntervalSince1970).mp4")
        try? data.write(to: url)
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        } completionHandler: { _, _ in
            try? FileManager.default.removeItem(at: url)
        }
    }
}

// MARK: - 聊天气泡视频卡片（缩略图 + 播放按钮 + 时长）

struct VideoBubbleCard: View {
    let videoBase64: String
    let durationMs: Double
    let onPlay: () -> Void
    @State private var thumbnail: UIImage?

    var body: some View {
        Button(action: onPlay) {
            ZStack {
                // 缩略图（首帧）或占位背景
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.35))
                        .frame(width: 240, height: 150)
                }
                // 播放按钮
                Circle()
                    .fill(.white.opacity(0.9))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.black)
                            .offset(x: 2)
                    )
                // 时长标签
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(String(format: "%.0f\"", durationMs / 1000))
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(.black.opacity(0.6)))
                            .padding(6)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            generateThumbnail()
        }
    }

    /// 提取视频首帧作为缩略图
    private func generateThumbnail() {
        guard thumbnail == nil, let data = Data(base64Encoded: videoBase64) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("thumb_\(Date().timeIntervalSince1970).mp4")
        try? data.write(to: url)
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        if let cg = try? generator.copyCGImage(at: .zero, actualTime: nil) {
            thumbnail = UIImage(cgImage: cg)
        }
        try? FileManager.default.removeItem(at: url)
    }
}
