package top.vios.chat.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import org.webrtc.VideoTrack
import org.webrtc.RendererCommon
import org.webrtc.SurfaceViewRenderer
import org.webrtc.EglBase

/**
 * 通话界面（2026 版）
 * - 拨号中：顶部小浮窗（对方头像）+ 中间"正在呼叫对方..."
 * - 通话中：顶部小浮窗 + 中间大号时长 mm:ss
 * - 结束态：显示通话摘要（语音/视频 · 挂断/失败 · 时长）
 * @param summary 结束摘要（如 "📞 语音通话 00:32" / "📵 未接通"）
 */
@Composable
fun CallScreen(
    isVideo: Boolean,
    state: String,             // connecting | active | ended
    remoteVideo: VideoTrack?,
    localVideo: VideoTrack?,
    peerName: String,
    durationSeconds: Int,
    eglBaseContext: EglBase.Context?,
    summary: String = "",
    onHangup: () -> Unit,
    onAccept: (() -> Unit)? = null,
    onReject: (() -> Unit)? = null
) {
    val isIncoming = onAccept != null
    val isEnded = state == "ended"
    val showVideo = isVideo && remoteVideo != null && eglBaseContext != null
    val callTypeLabel = if (isVideo) "视频通话" else "语音通话"

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF0A0A14))
    ) {
        // 视频通话：远端视频全屏
        if (showVideo) {
            AndroidView(
                modifier = Modifier.fillMaxSize(),
                factory = { ctx ->
                    SurfaceViewRenderer(ctx).apply {
                        init(eglBaseContext, null)
                        setMirror(false)
                        setScalingType(RendererCommon.ScalingType.SCALE_ASPECT_FIT)
                        remoteVideo.addSink(this)
                    }
                },
                update = { view -> remoteVideo.addSink(view) },
                onRelease = { view ->
                    try { remoteVideo.removeSink(view) } catch (_: Exception) {}
                }
            )
        }

        // ===== 中央内容（非视频全屏时显示） =====
        if (!showVideo) {
            Column(
                modifier = Modifier.fillMaxSize(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                if (isEnded) {
                    // 结束态：结果大字 + 摘要
                    Text(
                        if (durationSeconds > 0) "通话结束" else "未接通",
                        color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Bold
                    )
                    Spacer(Modifier.height(10.dp))
                    Text(
                        summary.ifEmpty {
                            if (durationSeconds > 0) "$callTypeLabel · 时长 ${formatDuration(durationSeconds)}" else "$callTypeLabel · 已取消"
                        },
                        color = Color(0xFF8888AA), fontSize = 14.sp
                    )
                    Spacer(Modifier.height(6.dp))
                    Text(
                        peerName, color = Color(0xFF666688), fontSize = 12.sp
                    )
                } else {
                    // 呼叫中/通话中：中间大时长（或呼叫文案）
                    if (state == "active" && durationSeconds > 0) {
                        Text(
                            formatDuration(durationSeconds),
                            color = Color.White, fontSize = 56.sp, fontWeight = FontWeight.Light,
                            fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
                        )
                        Spacer(Modifier.height(4.dp))
                        Text("通话时长", color = Color(0xFF666688), fontSize = 12.sp)
                    } else {
                        Spacer(Modifier.height(120.dp))
                        Text(
                            if (isIncoming) "来电邀请..." else "正在呼叫对方...",
                            color = Color(0xFF8888AA), fontSize = 15.sp
                        )
                    }
                }
            }
        }

        // ===== 顶部小浮窗（对方头像 + 类型，视频通话时画中画并列） =====
        Row(
            modifier = Modifier
                .align(Alignment.TopCenter)
                .padding(top = 20.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // 浮窗：圆形头像 + 通话类型角标
            Box {
                Surface(
                    shape = CircleShape,
                    color = Color(0xFF1E1E36),
                    modifier = Modifier.size(if (isEnded) 64.dp else 72.dp)
                ) {
                    Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxSize()) {
                        Text(if (isVideo) "🎥" else "🎧", fontSize = if (isEnded) 24.sp else 28.sp)
                    }
                }
                // 类型角标（底部小圆）
                Surface(
                    shape = CircleShape,
                    color = if (isEnded) Color(0xFF546E7A) else Color(0xFF34D399),
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .size(20.dp)
                ) {
                    Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxSize()) {
                        Text(
                            if (isVideo) "📹" else "📞",
                            fontSize = 10.sp
                        )
                    }
                }
            }
            Spacer(Modifier.width(14.dp))
            Column {
                Text(peerName, color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                Spacer(Modifier.height(3.dp))
                Text(
                    when {
                        isEnded -> if (durationSeconds > 0) "已结束 · ${formatDuration(durationSeconds)}" else "未接通"
                        state == "active" -> callTypeLabel
                        isIncoming -> "来电中"
                        else -> callTypeLabel
                    },
                    color = Color(0xFF8888AA), fontSize = 12.sp
                )
            }
        }

        // 本地视频画中画（视频通话且已接通）
        if (isVideo && localVideo != null && state == "active" && eglBaseContext != null) {
            AndroidView(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(16.dp)
                    .size(width = 120.dp, height = 180.dp)
                    .background(Color.Black, RoundedCornerShape(16.dp)),
                factory = { ctx ->
                    SurfaceViewRenderer(ctx).apply {
                        init(eglBaseContext, null)
                        setMirror(true)
                        setScalingType(RendererCommon.ScalingType.SCALE_ASPECT_FIT)
                        localVideo.addSink(this)
                    }
                },
                update = { view -> localVideo.addSink(view) },
                onRelease = { view ->
                    try { localVideo.removeSink(view) } catch (_: Exception) {}
                }
            )
        }

        // 通话状态提示（connecting）
        if (state == "connecting" && !isEnded) {
            Surface(
                shape = RoundedCornerShape(20.dp),
                color = Color(0x66000000),
                modifier = Modifier
                    .align(Alignment.Center)
                    .padding(top = 160.dp)
            ) {
                Text(
                    if (isIncoming) "🔔 ${callTypeLabel}邀请" else "⏳ 正在建立加密通话...",
                    modifier = Modifier.padding(horizontal = 20.dp, vertical = 10.dp),
                    color = Color.White, fontSize = 14.sp
                )
            }
        }

        // 底部控制按钮
        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 48.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            if (isIncoming && !isEnded) {
                Row(horizontalArrangement = Arrangement.spacedBy(48.dp)) {
                    CallActionButton("拒绝", Color(0xFFF87171), Icons.Default.Close) { onReject?.invoke() }
                    CallActionButton("接听", Color(0xFF34D399), Icons.Default.Call) { onAccept?.invoke() }
                }
            } else if (!isEnded) {
                CallActionButton("挂断", Color(0xFFF87171), Icons.Default.CallEnd) { onHangup() }
            } else {
                CallActionButton("返回", Color(0xFF546E7A), Icons.Default.ArrowBack) { onHangup() }
            }
        }
    }
}

@Composable
fun CallActionButton(label: String, color: Color, icon: androidx.compose.ui.graphics.vector.ImageVector, onClick: () -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Surface(
            shape = RoundedCornerShape(36.dp),
            color = color,
            modifier = Modifier
                .size(72.dp)
                .clickable(onClick = onClick)
        ) {
            Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxSize()) {
                Icon(icon, contentDescription = label, tint = Color.White, modifier = Modifier.size(30.dp))
            }
        }
        Spacer(Modifier.height(8.dp))
        Text(label, color = Color.White, fontSize = 13.sp)
    }
}

private fun formatDuration(seconds: Int): String {
    val m = seconds / 60
    val s = seconds % 60
    return String.format("%02d:%02d", m, s)
}
