package top.vios.chat.ui

import android.animation.Animator
import android.content.Context
import android.view.View
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import com.airbnb.lottie.LottieAnimationView
import com.airbnb.lottie.LottieDrawable

/**
 * EVO Lottie 动画视图（lottie-android Compose 封装）
 * 素材在 res/raw 下（与 iOS LottieAnimations/ 同款）
 */
@Composable
fun EvoLottieView(
    rawResId: Int,               // R.raw.xxx
    modifier: Modifier = Modifier,
    repeatMode: Int = LottieDrawable.INFINITE,
    repeatCount: Int = LottieDrawable.INFINITE
) {
    AndroidView(
        modifier = modifier,
        factory = { ctx ->
            LottieAnimationView(ctx).apply {
                setAnimation(rawResId)
                this.repeatMode = repeatMode
                this.repeatCount = repeatCount
                playAnimation()
            }
        },
        update = { view ->
            view.playAnimation()
        }
    )
}

/** EVO Lottie 素材资源名（与 iOS EvoLottie 常量对应） */
object EvoLottie {
    val aiThinking = top.vios.chat.R.raw.ai_thinking        // AI 思考加载
    val send = top.vios.chat.R.raw.send                     // 消息发送动画
    val voiceWave = top.vios.chat.R.raw.voice_wave          // 录音波形
    val callConnecting = top.vios.chat.R.raw.call_connecting // 通话连接
    val aiToolLoading = top.vios.chat.R.raw.ai_tool_loading // AI 工具加载
    val sendOk = top.vios.chat.R.raw.send_ok                // 发送成功勾选
    val connection = top.vios.chat.R.raw.connection          // 连接状态
}