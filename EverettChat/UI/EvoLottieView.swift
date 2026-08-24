import SwiftUI
import Lottie

/// EVO Lottie 动画视图（lottie-ios SwiftUI 封装）
/// 素材放在 EverettChat/LottieAnimations/*.json（作为 resource 打包进 main bundle）
struct EvoLottieView: UIViewRepresentable {
    let animationName: String      // JSON 文件名（不含扩展名）
    var loopMode: LottieLoopMode = .loop
    var contentMode: UIView.ContentMode = .scaleAspectFit

    func makeUIView(context: Context) -> LottieAnimationView {
        let view = LottieAnimationView()
        view.animation = LottieAnimation.named(animationName)
        view.loopMode = loopMode
        view.contentMode = contentMode
        view.backgroundBehavior = .pauseAndRestore
        view.play()
        return view
    }

    func updateUIView(_ uiView: LottieAnimationView, context: Context) {
        // 动画名变化时重新加载（用 tag 标记当前动画名）
        if uiView.tag != animationName.hashValue {
            uiView.tag = animationName.hashValue
            uiView.animation = LottieAnimation.named(animationName)
            uiView.loopMode = loopMode
            uiView.play()
        }
    }
}

/// EVO Lottie 动画名常量
enum EvoLottie {
    static let aiAvatar = "AI助手动态头像"     // AI 助手动态头像
    static let aiThinking = "AI思考加载"       // AI 回复等待
    static let sendSuccess = "消息发送动画"    // 发送反馈
    static let voiceWave = "录音波形"          // 录音波形
    static let callConnecting = "通话连接动画" // 通话接通等待
    static let aiToolLoading = "AI工具加载"    // AI 工具加载
    static let sentOk = "发送成功动画"         // 发送成功勾选
    static let connection = "连接状态动画"      // 连接状态指示
}
