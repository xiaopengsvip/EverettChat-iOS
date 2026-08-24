import SwiftUI

// 实验版：Lottie 暂时移除（静态链接使 debug.dylib 过大，爱思签名失败）
// 恢复方法：project.yml 取消 Lottie 注释 + 本文件恢复 import Lottie
@available(iOS 16.0, *)
struct EvoLottieView: View {
    var animationName: String = ""
    var loopMode: Any? = nil
    var body: some View {
        // 占位：动画恢复前用系统转圈
        ProgressView()
            .tint(.purple)
    }
}

enum EvoLottie {
    static let aiAvatar = ""
    static let aiThinking = ""
    static let sendSuccess = ""
    static let voiceWave = ""
    static let callConnecting = ""
    static let aiToolLoading = ""
    static let sentOk = ""
    static let connection = ""
}
