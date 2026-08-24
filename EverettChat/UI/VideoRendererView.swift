import SwiftUI
import WebRTC

/// WebRTC 视频画面（SwiftUI 桥接，直接挂载 WebRTCEngine 已绑定的 RTCMTLVideoView）
struct VideoRendererView: UIViewRepresentable {
    let videoView: RTCMTLVideoView?

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // 复用 WebRTCEngine 中已绑定 track 的 renderer 实例
        uiView.subviews.forEach { $0.removeFromSuperview() }
        if let v = videoView {
            v.frame = uiView.bounds
            v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            uiView.addSubview(v)
        }
    }
}