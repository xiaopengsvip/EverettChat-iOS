package top.vios.chat

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import kotlinx.coroutines.delay

/**
 * EVO 全屏开屏封面页（无黑屏过渡）
 * - 系统 splash 背景 = 封面底色，与封面无缝衔接
 * - 封面立即显示（不做淡入，避免黑屏帧）
 * - 1.1 秒停留后淡入主界面
 */
class SplashActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        // Android 12+ 官方 SplashScreen：背景纯色 = 封面底色，无缝衔接无黑屏
        installSplashScreen()
        super.onCreate(savedInstanceState)

        setContent {
            var done by remember { mutableStateOf(false) }
            LaunchedEffect(Unit) {
                // 封面直接显示，仅停留后跳转
                delay(1100)
                done = true
                goMain()
            }
            SplashCover()
        }
    }

    private fun goMain() {
        val intent = Intent(this, MainActivity::class.java)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        startActivity(intent)
        // 淡出过渡（封面 → 主界面）
        overridePendingTransition(android.R.anim.fade_in, android.R.anim.fade_out)
        finish()
    }
}

/** 全屏封面：深黑底 + 品牌图 centerCrop 铺满（立即显示，无淡入） */
@androidx.compose.runtime.Composable
fun SplashCover() {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    listOf(Color(0xFF0A0A12), Color(0xFF12121E))
                )
            )
    ) {
        Image(
            painter = painterResource(id = R.drawable.evo_splash),
            contentDescription = "EVO 启动封面",
            modifier = Modifier.fillMaxSize(),
            contentScale = ContentScale.Crop
        )
    }
}
