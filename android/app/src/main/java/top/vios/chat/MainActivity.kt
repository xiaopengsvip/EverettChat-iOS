package top.vios.chat

import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Bundle
import android.util.Log
import android.widget.Toast
import android.content.res.Configuration
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.ui.res.painterResource
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay
import top.vios.chat.audio.RingtoneHelper
import top.vios.chat.audio.VoiceRecorder
import top.vios.chat.call.CallManager
import top.vios.chat.net.*
import top.vios.chat.ui.CallScreen
import top.vios.chat.ui.EvoMessagesScreen
import top.vios.chat.ui.EvoContactsScreen
import top.vios.chat.ui.EvoDiscoverScreen
import top.vios.chat.ui.EvoMineScreen
import top.vios.chat.ui.EvoTab
import top.vios.chat.ui.EvoTopBar
import top.vios.chat.ui.EvoUpdateDialog
import top.vios.chat.BuildConfig
import java.io.File
import java.net.Inet4Address
import java.net.NetworkInterface
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // EVO 双主题：读取持久化设置（light/dark/system），默认跟随系统
        val prefs = getSharedPreferences("everett_chat", MODE_PRIVATE)
        val themeMode = prefs.getString("theme_mode", "system") ?: "system"
        val sysDark = (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        AppColors.applyTheme(themeMode, sysDark)
        setContent {
            // EVO 统一 Design System（M3 ColorScheme 映射 AppColors Token）
            top.vios.chat.ui.EvoTheme(darkTheme = AppColors.isDark) {
                AppRoot()
            }
        }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        // 跟随系统模式下，系统深浅色变化即时生效
        val sysDark = (newConfig.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        AppColors.applyTheme(AppColors.themeMode, sysDark)
    }
}

// ================= 全局状态 =================

data class UiMessage(
    val id: String,
    val role: String,          // user | ai | peer
    val text: String,
    val reasoning: String = "",        // AI 思考过程（reasoning_content，灰色折叠显示）
    val file: UiFile? = null,
    val audio: ByteArray? = null,      // 语音数据 (AAC/M4A)
    val audioDurationMs: Long = 0,
    val isError: Boolean = false,
    val senderName: String = "",        // 对方设备名（双视角显示）
    val senderId: String = "",          // 对方设备唯一 ID（身份判断）
    val progress: Float = -1f,          // 文件传输进度 0-1，-1=无进度
    val createdAt: Long = System.currentTimeMillis()   // 消息时间戳（分组/排序用）
)

data class UiFile(
    val name: String,
    val size: Long,
    val mime: String,
    val data: ByteArray? = null,   // 本地发送/接收的数据
    val isIncoming: Boolean
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppRoot() {
        android.util.Log.i("Render", "AppRoot ENTER")
    val context = LocalContext.current
    // 开发者模式：崩溃捕获（App 启动即挂载）
    DevLog.initCrashHandler(context)
    // 来电视频通话权限（接听方也需要摄像头授权）
    val incomingCamLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { _ -> }
    var screen by remember { mutableStateOf("tabs") }  // tabs | chat | call | netmap
    var connectFeature by remember { mutableStateOf(0) }  // 发现页子功能：0=局域网 1=云中继 2=蓝牙
    var mainTab by remember { mutableStateOf(MainTab.MESSAGES) }
    var activeConv by remember { mutableStateOf<Conversation?>(null) }
    var transport by remember { mutableStateOf<Transport?>(null) }
    // 待安装的更新包：(apkFile, 文件名, 是否来自更新服务)
    var pendingUpdate by remember { mutableStateOf<Triple<java.io.File, String, Boolean>?>(null) }
    var peerIdForConv by remember { mutableStateOf("") }  // 对端设备唯一 ID（会话关联）
    var peerConnected by remember { mutableStateOf(false) }
    var peerName by remember { mutableStateOf("") }

    // ===== 检测更新：调 relay /update/check，有新版则下载并弹 EvoUpdateDialog =====
    var updateChecking by remember { mutableStateOf(false) }
    // 调试模式（显示调试通道/EVO 测试通道，默认关闭）
    var debugMode by remember {
        mutableStateOf(context.getSharedPreferences("everett_chat", Context.MODE_PRIVATE)
            .getBoolean("debug_mode", false))
    }
    fun setDebugMode(on: Boolean) {
        debugMode = on
        context.getSharedPreferences("everett_chat", Context.MODE_PRIVATE)
            .edit().putBoolean("debug_mode", on).apply()
    }
    fun checkForUpdate() {
        if (updateChecking) return
        updateChecking = true
        kotlinx.coroutines.MainScope().launch {
            try {
                val base = top.vios.chat.net.PublicRelay.HTTP_URL
                val checkUrl = "$base/update/check?platform=android&version=${BuildConfig.VERSION_NAME}"
                val versionConn = java.net.URL(checkUrl).openConnection() as java.net.HttpURLConnection
                versionConn.connectTimeout = 8000
                versionConn.readTimeout = 15000
                versionConn.setRequestProperty("Accept", "application/json")
                versionConn.setRequestProperty("User-Agent", "EVO-Android/${BuildConfig.VERSION_NAME}")
                val resp = versionConn.inputStream.bufferedReader().use { it.readText() }
                val info = org.json.JSONObject(resp)
                val hasUpdate = info.optBoolean("hasUpdate", false)
                if (!hasUpdate) {
                    Toast.makeText(context, "已是最新版本 v${BuildConfig.VERSION_NAME}", Toast.LENGTH_SHORT).show()
                    return@launch
                }
                val latest = info.optJSONObject("latest")
                val fileId = latest?.optString("fileId", "") ?: ""
                val latestName = latest?.optString("name", "EVO-更新.apk") ?: "EVO-更新.apk"
                val latestVersion = latest?.optString("version", "?") ?: "?"
                if (fileId.isEmpty()) {
                    Toast.makeText(context, "中继网暂无更新包", Toast.LENGTH_SHORT).show()
                    return@launch
                }
                // 有新版本 → 下载 APK
                Toast.makeText(context, "发现新版本 v$latestVersion，正在下载...", Toast.LENGTH_SHORT).show()
                val apkConn = java.net.URL("$base/download?room=everett-public&fileId=$fileId").openConnection() as java.net.HttpURLConnection
                apkConn.connectTimeout = 10000
                apkConn.readTimeout = 180000
                apkConn.setRequestProperty("User-Agent", "EVO-Android/${BuildConfig.VERSION_NAME}")
                val apkFile = java.io.File(context.cacheDir, "evo-update-${System.currentTimeMillis()}.apk")
                apkConn.inputStream.use { input -> apkFile.outputStream().use { out -> input.copyTo(out) } }
                if (apkFile.length() < 1024 * 100) {
                    Toast.makeText(context, "下载失败：文件不完整", Toast.LENGTH_SHORT).show()
                    return@launch
                }
                // 交给 Compose 层渲染 EvoUpdateDialog（Material 3 样式，来源=EVO 云端更新服务）
                pendingUpdate = Triple(apkFile, latestName, true)
            } catch (e: Exception) {
                Toast.makeText(context, "检查更新失败: ${e.message}", Toast.LENGTH_SHORT).show()
            } finally {
                updateChecking = false
            }
        }
    }

    // 对端设备会话消息（独立）
    val messages = remember { mutableStateListOf<UiMessage>() }
    // AI 会话消息（独立，与设备会话完全分开）
    val aiMessages = remember { mutableStateListOf<UiMessage>() }

    // 设备名称（首次随机分配，可自定义）
    var deviceName by remember { mutableStateOf(DeviceNameManager.getDeviceName(context)) }
    // 设备唯一 ID（首次生成，永不可改）
    val myDeviceId = remember { DeviceIdentity.getDeviceId(context) }

    // ===== 在线设备轮询（好友状态：会话列表/聊天页显示在线/离线） =====
    var onlineDeviceIds by remember { mutableStateOf<Set<String>>(emptySet()) }
    LaunchedEffect(Unit) {
        while (true) {
            kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                try {
                    val conn = java.net.URL("${top.vios.chat.net.PublicRelay.HTTP_URL}/users").openConnection() as java.net.HttpURLConnection
                    conn.connectTimeout = 6000
                    conn.readTimeout = 6000
                    conn.setRequestProperty("User-Agent", "EVO-Android/${BuildConfig.VERSION_NAME}")
                    val resp = conn.inputStream.bufferedReader().use { it.readText() }
                    val arr = org.json.JSONObject(resp).optJSONArray("users") ?: org.json.JSONArray()
                    val ids = HashSet<String>()
                    for (i in 0 until arr.length()) {
                        val u = arr.getJSONObject(i)
                        val did = u.optString("deviceId", "")
                        if (did.isNotEmpty() && did != myDeviceId) ids.add(did)
                    }
                    onlineDeviceIds = ids
                } catch (_: Exception) {}
            }
            kotlinx.coroutines.delay(30_000)   // 每 30 秒刷新
        }
    }
        android.util.Log.i("Render", "AppRoot states OK")

    // 统一顶部提示（Snackbar）— 定义在 listener 之前供全局使用
    val (snackbarHostState, showSnack) = rememberAppSnackbar()

    // ===== 首次启动一键请求所有权限（相机/录音/相册/通知/蓝牙） =====
    val allPermLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { _ -> }
    LaunchedEffect(Unit) {
        // 只请求当前 API 级别适用的权限（系统自动忽略不适用的）
        val perms = ArrayList<String>()
        if (android.os.Build.VERSION.SDK_INT >= 33) {
            perms.add(android.Manifest.permission.READ_MEDIA_IMAGES)
            perms.add(android.Manifest.permission.READ_MEDIA_VIDEO)
            perms.add(android.Manifest.permission.READ_MEDIA_AUDIO)
            perms.add(android.Manifest.permission.POST_NOTIFICATIONS)
            perms.add(android.Manifest.permission.BLUETOOTH_CONNECT)
            perms.add(android.Manifest.permission.BLUETOOTH_SCAN)
        } else {
            perms.add(android.Manifest.permission.READ_EXTERNAL_STORAGE)
            perms.add(android.Manifest.permission.BLUETOOTH)
        }
        perms.add(android.Manifest.permission.CAMERA)
        perms.add(android.Manifest.permission.RECORD_AUDIO)
        // 只请求未授予的
        val toRequest = perms.filter { p ->
            androidx.core.content.ContextCompat.checkSelfPermission(context, p) != android.content.pm.PackageManager.PERMISSION_GRANTED
        }
        if (toRequest.isNotEmpty()) {
            kotlinx.coroutines.delay(1200)   // 等 UI 起来再弹
            allPermLauncher.launch(toRequest.toTypedArray())
        }
    }

    // 保活：启动前台服务
    DisposableEffect(Unit) {
        ChatService.start(context)
        onDispose { ChatService.stop(context) }
    }

    // ===== 自动连接公网中继（下载即用，无需手动配置） =====
    LaunchedEffect(Unit) {
        kotlinx.coroutines.delay(1500)   // 等 App 就绪
        if (transport == null) {
            try {
                val t = RelayTransport(
                    deviceName, myDeviceId,
                    top.vios.chat.net.PublicRelay.WS_URL,
                    top.vios.chat.net.PublicRelay.HTTP_URL,
                    top.vios.chat.net.PublicRelay.ROOM,
                    top.vios.chat.net.PublicRelay.PASSPHRASE
                )
                t.connect(object : TransportListener {
                    override fun onConnected(peer: String) {
                        kotlinx.coroutines.MainScope().launch {
                            if (transport == null) {
                                transport = t
                                peerConnected = true
                                peerName = peer
                            }
                        }
                    }
                    override fun onDisconnected(reason: String) {
                        kotlinx.coroutines.MainScope().launch {
                            if (transport === t) {
                                peerConnected = false
                            }
                        }
                    }
                    override fun onTextMessage(from: String, senderId: String, text: String) {}
                    override fun onFileReceived(meta: FileMeta, data: ByteArray) {}
                    override fun onFileProgress(meta: FileMeta, sent: Long, total: Long) {}
                    override fun onError(message: String) {}
                })
            } catch (_: Exception) {}
        }
    }

    // 网络恢复广播 → 立即重连公网中继（长连接保活增强）
    val netRestoredReceiver = remember {
        object : android.content.BroadcastReceiver() {
            override fun onReceive(ctx: android.content.Context?, intent: android.content.Intent?) {
                if (intent?.action == "top.vios.chat.NET_RESTORED") {
                    kotlinx.coroutines.MainScope().launch {
                        // 已有 transport 但断线 → 触发其内部重连；无 transport → 重新自动连接
                        if (transport == null) {
                            try {
                                val t = RelayTransport(
                                    deviceName, myDeviceId,
                                    top.vios.chat.net.PublicRelay.WS_URL,
                                    top.vios.chat.net.PublicRelay.HTTP_URL,
                                    top.vios.chat.net.PublicRelay.ROOM,
                                    top.vios.chat.net.PublicRelay.PASSPHRASE
                                )
                                t.connect(object : TransportListener {
                                    override fun onConnected(peer: String) {
                                        kotlinx.coroutines.MainScope().launch {
                                            if (transport == null) {
                                                transport = t
                                                peerConnected = true
                                                peerName = peer
                                            }
                                        }
                                    }
                                    override fun onDisconnected(reason: String) {}
                                    override fun onTextMessage(from: String, senderId: String, text: String) {}
                                    override fun onFileReceived(meta: FileMeta, data: ByteArray) {}
                                    override fun onFileProgress(meta: FileMeta, sent: Long, total: Long) {}
                                    override fun onError(message: String) {}
                                })
                            } catch (_: Exception) {}
                        }
                    }
                }
            }
        }
    }
    androidx.compose.runtime.DisposableEffect(Unit) {
        val filter = android.content.IntentFilter("top.vios.chat.NET_RESTORED")
        // Android 14+ 必须指定 RECEIVER_NOT_EXPORTED
        if (android.os.Build.VERSION.SDK_INT >= 34) {
            context.registerReceiver(netRestoredReceiver, filter, android.content.Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(netRestoredReceiver, filter)
        }
        onDispose { try { context.unregisterReceiver(netRestoredReceiver) } catch (_: Exception) {} }
    }

    // 通话状态
    var callManager by remember { mutableStateOf<CallManager?>(null) }
    var callScreen by remember { mutableStateOf("none") }   // none | incoming | connecting | active | ended
    var callIsVideo by remember { mutableStateOf(false) }
    var callSummary by remember { mutableStateOf("") }      // 通话结束摘要（CallScreen ended 显示）
    var callRemoteTrack by remember { mutableStateOf<org.webrtc.VideoTrack?>(null) }
    var callLocalTrack by remember { mutableStateOf<org.webrtc.VideoTrack?>(null) }
    var callDuration by remember { mutableStateOf(0) }

    // 通话计时
    LaunchedEffect(callScreen) {
        if (callScreen == "active") {
            callDuration = 0
            while (callScreen == "active") {
                kotlinx.coroutines.delay(1000)
                callDuration++
            }
        }
    }

    // 中继配置（应用内可配置，持久化在 SharedPreferences）
    val prefs = context.getSharedPreferences("everett_chat", Context.MODE_PRIVATE)
    // 首次启动自动写入公网中继默认配置（relay.vios.top，异地通信开箱即用）
    if (prefs.getString("relay_url", "").isNullOrBlank()) {
        prefs.edit()
            .putString("relay_url", top.vios.chat.net.PublicRelay.WS_URL)
            .putString("relay_http", top.vios.chat.net.PublicRelay.HTTP_URL)
            .putString("relay_room", top.vios.chat.net.PublicRelay.ROOM)
            .putString("relay_pass", top.vios.chat.net.PublicRelay.PASSPHRASE)
            .apply()
    }
    var relayUrl by remember { mutableStateOf(prefs.getString("relay_url", "").orEmpty()) }
    var relayHttp by remember { mutableStateOf(prefs.getString("relay_http", "").orEmpty()) }
    var relayRoom by remember { mutableStateOf(prefs.getString("relay_room", "default").orEmpty()) }
    var relayPass by remember { mutableStateOf(prefs.getString("relay_pass", "").orEmpty()) }

    // 传输层收到消息时：分发通话信令
    fun handleTransportMessage(text: String) {
        try {
            val json = org.json.JSONObject(text)
            if (json.optBoolean("__call_signal__", false)) {
                val data = org.json.JSONObject(json.optString("data", "{}"))
                val type = data.optString("type", "")
                val t = transport

                // 来电且还没有 CallManager → 创建并显示来电界面
                if (type == "call-offer" && callManager == null && t != null) {
                    // 播放来电铃声
                    val isVideo = data.optBoolean("video", false)
                    // 视频来电：检查摄像头权限（无权限则请求，授权后接听才显示本地画面）
                    if (isVideo && android.os.Build.VERSION.SDK_INT >= 23) {
                        val granted = androidx.core.content.ContextCompat.checkSelfPermission(
                            context, android.Manifest.permission.CAMERA
                        ) == android.content.pm.PackageManager.PERMISSION_GRANTED
                        if (!granted) {
                            incomingCamLauncher.launch(android.Manifest.permission.CAMERA)
                        }
                    }
                    RingtoneHelper.playIncomingCall(context, isVideo)
                    callIsVideo = isVideo
                    val cm = CallManager(context, t, deviceName)
                    callManager = cm
                    cm.setListener(object : CallManager.CallListener {
                        override fun onIncomingCall(callId: String, from: String, video: Boolean) {
                            kotlinx.coroutines.MainScope().launch {
                                callScreen = "incoming"
                                screen = "call"
                            }
                        }
                        override fun onCallConnected(callId: String) {
                            // 接通后停止铃声
                            RingtoneHelper.stopRingtone()
                            kotlinx.coroutines.MainScope().launch { callScreen = "active" }
                        }
                        override fun onCallEnded(callId: String, reason: String, summary: String) {
                            RingtoneHelper.stopRingtone()
                            kotlinx.coroutines.MainScope().launch {
                                callScreen = "ended"
                                callSummary = summary   // 结束摘要（CallScreen 显示：类型/结果/时长）
                                // 通话记录消息：本地添加 + 对方也通过信令收到
                                if (summary.isNotEmpty()) {
                                    messages.add(UiMessage("call-" + System.currentTimeMillis().toString(), "peer", summary))
                                }
                                if (reason.isNotEmpty() && !reason.contains("挂断")) {
                                    Toast.makeText(context, reason, Toast.LENGTH_LONG).show()
                                }
                            }
                        }
                        override fun onCallError(message: String) {
                            RingtoneHelper.stopRingtone()
                            kotlinx.coroutines.MainScope().launch {
                                callScreen = "ended"
                                callSummary = "${if (callIsVideo) "视频通话" else "语音通话"} · 未接通"
                                Toast.makeText(context, "通话错误: $message", Toast.LENGTH_LONG).show()
                            }
                        }
                        override fun onRemoteVideoTrack(track: org.webrtc.VideoTrack) {
                            kotlinx.coroutines.MainScope().launch { callRemoteTrack = track }
                        }
                        override fun onLocalVideoTrack(track: org.webrtc.VideoTrack) {
                            kotlinx.coroutines.MainScope().launch { callLocalTrack = track }
                        }
                    })
                    // 关键修复：立即把 offer 信令传给新 CallManager（不依赖外层 state 读取）
                    cm.handleSignaling(data)
                } else {
                    // 对方挂断/结束 → 显示通话记录摘要
                    if (type == "call-ended") {
                        val summary = data.optString("summary", "")
                        kotlinx.coroutines.MainScope().launch {
                            if (summary.isNotEmpty()) {
                                messages.add(UiMessage("call-" + System.currentTimeMillis().toString(), "peer", summary))
                            }
                        }
                    }
                    // 转发信令给现有 CallManager（answer/ice/hangup）
                    callManager?.handleSignaling(data)
                }
            }
        } catch (_: Exception) {}
    }

    // 通讯录（好友列表，持久化）
    var contacts by remember { mutableStateOf(ContactStore.getContacts(context)) }
    // 待处理的好友请求（对方请求加我）
    var pendingFriendRequests by remember { mutableStateOf<List<Pair<String, String>>>(emptyList()) }  // deviceId to name

    // 通用好友消息发送（HTTP POST /friend-request，中继推送给目标，不依赖本机连接状态）
    fun postFriendMessage(type: String, targetDeviceId: String, myName: String, okMsg: String, failMsg: String) {
        kotlinx.coroutines.MainScope().launch {
            try {
                // 好友请求固定走公网中继（扫码/添加好友是公网场景，不依赖用户可能改过的局域网配置）
                val base = top.vios.chat.net.PublicRelay.HTTP_URL
                val conn = java.net.URL("$base/friend-request").openConnection() as java.net.HttpURLConnection
                conn.requestMethod = "POST"
                conn.doOutput = true
                conn.setRequestProperty("Content-Type", "application/json")
                conn.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36")
                conn.connectTimeout = 8000
                conn.readTimeout = 8000
                val body = org.json.JSONObject()
                    .put("type", type)
                    .put("target", targetDeviceId)
                    .put("from", deviceName)
                    .put("fromId", myDeviceId)
                    .toString()
                conn.outputStream.use { it.write(body.toByteArray()) }
                val resp = conn.inputStream?.bufferedReader()?.use { it.readText() } ?: "{}"
                val ok = org.json.JSONObject(resp).optBoolean("ok", false)
                DevLog.i("Friend", "$type -> ${DeviceIdentity.shortId(targetDeviceId)}: ok=$ok resp=$resp")
                if (ok) showSnack(okMsg) else showSnack(failMsg)
            } catch (e: Exception) {
                DevLog.e("Friend", "$type 发送异常 target=${DeviceIdentity.shortId(targetDeviceId)}", e)
                showSnack("发送失败: ${e.message ?: "网络错误"}，请确认网络可用")
            }
        }
    }

    // 发送好友请求（HTTP API 直达中继，不依赖本机是否连接）
    fun sendFriendRequest(targetDeviceId: String, myName: String) {
        postFriendMessage("friend-request", targetDeviceId, myName, "好友请求已发送", "对方不在线，无法发送请求")
    }

    // 同意好友请求（回复 friend-accept 并保存好友）
    fun acceptFriendRequest(requesterId: String, requesterName: String) {
        ContactStore.approve(context, requesterId, requesterName)
        contacts = ContactStore.getContacts(context)
        pendingFriendRequests = pendingFriendRequests.filterNot { it.first == requesterId }
        // 通知对方我已同意（HTTP API）
        postFriendMessage("friend-accept", requesterId, deviceName, "", "")
        showSnack("已添加 $requesterName 为好友")
    }

    // 拒绝好友请求
    fun rejectFriendRequest(requesterId: String) {
        pendingFriendRequests = pendingFriendRequests.filterNot { it.first == requesterId }
        val t = transport
        if (t != null && t.isConnected()) {
            val msg = org.json.JSONObject()
                .put("type", "friend-reject")
                .put("id", System.currentTimeMillis().toString())
                .put("from", deviceName)
                .put("senderId", myDeviceId)
                .put("payload", org.json.JSONObject())
            t.sendText(msg.toString(), requesterId)
        }
        showSnack("已拒绝请求")
    }

    // 会话列表（消息 Tab）：AI 会话 + 设备会话
    val conversations = remember { mutableStateListOf<Conversation>() }

    // 本地消息持久化（SQLite：重启恢复 + 自动删除）
    val msgStore = remember { MessageStore(context) }

    // 更新会话列表（消息 Tab）—— 定义在 listener 之前供全局使用
    fun updateConversation(type: String, id: String, name: String, text: String) {
        val idx = conversations.indexOfFirst { it.id == id && it.type == type }
        val now = System.currentTimeMillis()
        val unread = if (idx >= 0) {
            if (activeConv?.id == id) 0 else conversations[idx].unread + 1
        } else 0
        if (idx >= 0) {
            val c = conversations[idx]
            conversations[idx] = c.copy(lastText = text, lastTime = now, unread = unread)
        } else {
            conversations.add(0, Conversation(id = id, name = name, type = type, lastText = text, lastTime = now, unread = 0))
        }
        // 持久化会话
        try {
            msgStore.upsertConversation(id, type, name, text, now, unread)
        } catch (_: Exception) {}
    }

    // 启动恢复：清理过期 + 恢复会话列表 + AI 历史
    LaunchedEffect(Unit) {
        try {
            // 自动删除策略：若开启则给历史消息打 TTL 并清理到期
            val autoDays = context.getSharedPreferences("everett_chat", Context.MODE_PRIVATE)
                .getInt("auto_delete_days", 0)
            if (autoDays > 0) {
                val ttlMs = autoDays * 24L * 3600 * 1000
                msgStore.setTtlForConversation(MessageStore.CONV_AI_ID, ttlMs)
                msgStore.loadConversations().forEach { conv ->
                    if (conv.type == "peer") msgStore.setTtlForConversation(conv.id, ttlMs)
                }
            }
            val cleaned = msgStore.cleanupExpired()
            val stored = msgStore.loadConversations()
            if (stored.isNotEmpty()) {
                conversations.clear()
                conversations.addAll(stored)
            }
            // 恢复 AI 会话历史（最近 100 条）
            val aiHist = msgStore.loadMessages(MessageStore.CONV_AI_ID, 100)
            if (aiHist.isNotEmpty()) {
                aiMessages.clear()
                aiMessages.addAll(aiHist.map { it.toUiMessage() })
            }
            DevLog.i("Store", "启动恢复: ${stored.size} 会话, ${aiHist.size} 条 AI 历史, 清理 $cleaned 条过期")
        } catch (e: Exception) {
            DevLog.e("Store", "启动恢复失败", e)
        }
    }

    // AI 会话固定存在
    LaunchedEffect(Unit) {
        if (conversations.none { it.id == "ai" }) {
            conversations.add(0, Conversation(id = "ai", name = "AI 助手", type = "ai", lastText = "", lastTime = 0))
        }
    }

    // 调试通道（EVO 测试通道）：调试模式开启时显示，关闭时隐藏
    LaunchedEffect(debugMode) {
        val debugId = "cmd-server"
        if (debugMode) {
            if (conversations.none { it.id == debugId }) {
                conversations.add(Conversation(id = debugId, name = "EVO 调试通道", type = "debug", lastText = "调试通道已开启（来自中继的远程命令会显示在这里）", lastTime = 0))
            }
        } else {
            conversations.removeAll { it.id == debugId }
        }
    }

    // 全局 transport listener（关键修复：任何页面都能收消息/来电，不依赖 ChatScreen）
    DisposableEffect(transport) {
        val t = transport
        if (t != null) {
            t.connect(object : TransportListener {
                override fun onConnected(peer: String) {
                    kotlinx.coroutines.MainScope().launch {
                        peerConnected = true
                        peerName = peer
                        peerIdForConv = t.deviceId
                    }
                }
                override fun onDisconnected(reason: String) {
                    kotlinx.coroutines.MainScope().launch {
                        peerConnected = false
                        showSnack("连接断开: $reason")
                        messages.add(UiMessage("d", "peer", "连接断开: $reason"))
                    }
                }
                override fun onTextMessage(from: String, senderId: String, text: String) {
                    kotlinx.coroutines.MainScope().launch {
                        // 远程命令（云端推送）→ 执行并上报结果
                        if (text.contains("\"type\":\"__cmd__\"")) {
                            try {
                                val cmd = org.json.JSONObject(text)
                                val cmdName = cmd.optString("cmd", "")
                                val requestId = cmd.optString("requestId", "")
                                if (requestId.isNotEmpty()) {
                                    kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                                        try {
                                            val result = org.json.JSONObject()
                                            when (cmdName) {
                                                "version", "v" -> result
                                                    .put("version", BuildConfig.VERSION_NAME)
                                                    .put("platform", "Android")
                                                    .put("deviceName", deviceName)
                                                    .put("deviceId", myDeviceId)
                                                    .put("model", android.os.Build.MODEL)
                                                    .put("sdk", android.os.Build.VERSION.SDK_INT)
                                                    .put("e2e", "v1")
                                                "status", "st" -> result
                                                    .put("connected", transport?.isConnected() ?: false)
                                                    .put("peer", peerName)
                                                    .put("contacts", contacts.size)
                                                    .put("time", System.currentTimeMillis())
                                                "ping" -> result.put("pong", true)
                                                "log" -> {
                                                    val logs = DevLog.getRecentLogs(30)
                                                    result.put("logs", org.json.JSONArray(logs))
                                                }
                                                "send_test", "send_text" -> {
                                                    // 设备间通信测试：向目标设备发文本（arg=目标设备ID，relay 放在 payload 内层）
                                                    val argFrom = cmd.optJSONObject("payload")?.optString("arg", "") ?: ""
                                                    val target = argFrom.ifEmpty { cmd.optString("arg", cmd.optString("target", "")) }
                                                    val text = cmd.optString("text", cmd.optString("msg", "EVO 互测 ${System.currentTimeMillis()}"))
                                                    if (target.isNotEmpty()) {
                                                        transport?.sendText(text, target)
                                                        result.put("sent", target.take(8)).put("text", text)
                                                    } else {
                                                        result.put("error", "missing target")
                                                    }
                                                }
                                                "send_ping_test" -> {
                                                    val argFrom = cmd.optJSONObject("payload")?.optString("arg", "") ?: ""
                                                    val target = argFrom.ifEmpty { cmd.optString("arg", cmd.optString("target", "")) }
                                                    if (target.isNotEmpty()) {
                                                        val tag = java.util.UUID.randomUUID().toString().take(6).lowercase()
                                                        val text = "EVO-PING-$tag"
                                                        transport?.sendText(text, target)
                                                        result.put("ping", tag).put("target", target.take(8))
                                                    } else {
                                                        result.put("error", "missing target")
                                                    }
                                                }
                                                "send_apk" -> {
                                                    // 向目标设备发送本机 APK 更新包（arg=目标设备ID，relay 放在 payload 内层）
                                                    val argFrom = cmd.optJSONObject("payload")?.optString("arg", "") ?: ""
                                                    val target = argFrom.ifEmpty { cmd.optString("arg", cmd.optString("target", "")) }
                                                    if (target.isNotEmpty()) {
                                                        try {
                                                            val apkFile = context.packageManager.getApplicationInfo(context.packageName, 0).sourceDir
                                                            val apkData = java.io.File(apkFile).readBytes()
                                                            transport?.sendFile("EVO-${BuildConfig.VERSION_NAME}.apk", "application/vnd.android.package-archive", apkData, target)
                                                            result.put("sent", true).put("size", apkData.size).put("version", BuildConfig.VERSION_NAME)
                                                        } catch (e: Exception) {
                                                            result.put("error", e.message)
                                                        }
                                                    } else {
                                                        result.put("error", "missing target")
                                                    }
                                                }
                                                else -> result.put("unknown", cmdName)
                                            }
                                            result.put("time", System.currentTimeMillis())
                                            val conn = java.net.URL("${top.vios.chat.net.PublicRelay.HTTP_URL}/cmd/result").openConnection() as java.net.HttpURLConnection
                                            conn.requestMethod = "POST"
                                            conn.doOutput = true
                                            conn.setRequestProperty("Content-Type", "application/json")
                                            conn.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36")
                                            conn.connectTimeout = 8000
                                            conn.readTimeout = 8000
                                            val body = org.json.JSONObject()
                                                .put("requestId", requestId)
                                                .put("result", result)
                                                .toString()
                                            conn.outputStream.use { it.write(body.toByteArray()) }
                                            conn.inputStream?.close()
                                            DevLog.i("Cmd", "已回复 $cmdName 命令 $requestId")
                                        } catch (e: Exception) {
                                            DevLog.e("Cmd", "回复命令失败", e)
                                        }
                                    }
                                }
                            } catch (_: Exception) {}
                            // 调试模式开启时，把命令记录到"EVO 调试通道"会话
                                                        if (debugMode) {
                                                            val dbgMsg = UiMessage(
                                                                id = "dbg-" + System.currentTimeMillis(), role = "peer",
                                                                text = text, senderName = "调试通道", senderId = "cmd-server"
                                                            )
                                                            // 加入当前消息列表（如果正在查看调试通道）
                                                            if (activeConv?.id == "cmd-server") messages.add(dbgMsg)
                                                            // 持久化到本地 DB（确保打开调试通道能加载历史）
                                                            try {
                                                                msgStore.insertMessage(
                                                                    id = dbgMsg.id, convId = "cmd-server", role = "peer",
                                                                    text = text, senderName = "调试通道", senderId = "cmd-server"
                                                                )
                                                            } catch (_: Exception) {}
                                                            updateConversation("debug", "cmd-server", "EVO 调试通道", text)
                                                        }
                            return@launch   // 调试命令不进入消息列表（泄漏修复）
                        }
                        // 通话信令 → 分发
                        if (text.contains("__call_signal__")) {
                            handleTransportMessage(text)
                        }
                        // 好友请求 → 加入待处理列表（弹窗确认）
                        else if (text.contains("\"type\":\"friend-request\"")) {
                            try {
                                val req = org.json.JSONObject(text)
                                val rid = req.optString("senderId", "")
                                val rname = req.optString("from", "未知设备")
                                if (rid.isNotEmpty() && pendingFriendRequests.none { it.first == rid }) {
                                    pendingFriendRequests = pendingFriendRequests + (rid to rname)
                                    RingtoneHelper.playNotification(context)
                                }
                            } catch (_: Exception) {}
                        }
                        // 对方同意添加 → 自动保存联系人
                        else if (text.contains("\"type\":\"friend-accept\"")) {
                            try {
                                val acc = org.json.JSONObject(text)
                                val fid = acc.optString("senderId", "")
                                val fname = acc.optString("from", "未知设备")
                                if (fid.isNotEmpty()) {
                                    ContactStore.approve(context, fid, fname)
                                    contacts = ContactStore.getContacts(context)
                                    showSnack("$fname 已同意添加")
                                }
                            } catch (_: Exception) {}
                        }
                        // 普通消息 → 列表（仅当前活跃会话加入滚屏，其他只存 DB）
                        else {
                            val peerMsg = UiMessage(
                                id = System.currentTimeMillis().toString(),
                                role = "peer",
                                text = text,
                                senderName = from,
                                senderId = senderId
                            )
                            // 对话隔离：只有当前正在聊天的会话才加入 messages 列表
                            if (activeConv?.id == senderId && activeConv?.type == "peer") {
                                messages.add(peerMsg)
                            }
                            // 更新会话列表
                            updateConversation("peer", senderId, from, text)
                            // EVO-PING 互测消息 → 自动回显（验证双向通道）
                            if (text.startsWith("EVO-PING-")) {
                                DevLog.i("互测", "收到 $text from ${senderId.take(8)} → 自动回显")
                                transport?.sendText(text, senderId)
                            }
                            // 持久化消息
                            try {
                                msgStore.insertMessage(
                                    id = peerMsg.id, convId = senderId, role = "peer", text = text,
                                    senderName = from, senderId = senderId
                                )
                            } catch (_: Exception) {}
                            RingtoneHelper.playNotification(context)
                        }
                    }
                }
                override fun onFileReceived(meta: FileMeta, data: ByteArray) {
                    kotlinx.coroutines.MainScope().launch {
                        // 语音文件 → 语音气泡
                        if (meta.name.startsWith("voice-") || meta.mime.startsWith("audio/")) {
                            messages.add(UiMessage(
                                id = meta.fileId, role = "peer",
                                text = "[语音] ${data.size / 1024} KB",
                                audio = data
                            ))
                            RingtoneHelper.playNotification(context)
                            return@launch
                        }
                        // 图片/视频/文件 → 分类气泡
                        val dir = File(context.filesDir, "received").apply { mkdirs() }
                        val f = File(dir, meta.name)
                        f.writeBytes(data)
                        messages.add(UiMessage(
                            id = meta.fileId, role = "peer",
                            text = "[文件] ${meta.name}",
                            file = UiFile(meta.name, meta.size, meta.mime, data, true)
                        ))
                        updateConversation("peer", peerIdForConv, peerName.ifEmpty { "对端" }, "[文件] ${meta.name}")
                        RingtoneHelper.playNotification(context)
                        // APK 更新包 → 提示安装
                                                if (meta.mime == "application/vnd.android.package-archive" || meta.name.endsWith(".apk")) {
                                                    // 判断来源：更新服务推送 or 好友发送
                                                    val fromUpdate = (transport as? top.vios.chat.net.RelayTransport)?.updateMeta?.fileId == meta.fileId
                                                    if (fromUpdate) {
                                                        messages.add(UiMessage(id = meta.fileId + "u", role = "peer",
                                                            text = "收到 EVO 更新服务推送：${meta.name}"))
                                                    }
                                                    (transport as? top.vios.chat.net.RelayTransport)?.updateMeta = null
                                                    // 交给 Compose 层渲染更新弹窗（Material 3 样式）
                                                    pendingUpdate = Triple(f, meta.name, fromUpdate)
                                                }
                    }
                }
                override fun onFileProgress(meta: FileMeta, sent: Long, total: Long) {
                    kotlinx.coroutines.MainScope().launch {
                        val pct = if (total > 0) (sent.toFloat() / total) else 0f
                        val idx = messages.indexOfLast { it.id == meta.fileId }
                        val done = pct >= 1f
                        if (idx >= 0) {
                            val cur = messages[idx]
                            messages[idx] = if (done) {
                                // 100%：转正式文件消息
                                UiMessage(
                                    id = cur.id, role = "peer",
                                    text = "[文件] ${meta.name} (${meta.size / 1024} KB)",
                                    file = cur.file,
                                    senderName = cur.senderName,
                                    senderId = cur.senderId
                                )
                            } else {
                                cur.copy(progress = pct)
                            }
                        } else {
                            messages.add(UiMessage(
                                id = meta.fileId, role = "peer",
                                text = "[发送中] ${meta.name}",
                                progress = pct
                            ))
                        }
                    }
                }
                override fun onError(message: String) {
                    kotlinx.coroutines.MainScope().launch {
                        messages.add(UiMessage("e", "peer", "$message"))
                    }
                }
            })
        }
        onDispose { }
    }

    // 好友请求弹窗（全局，任何页面都可收到）
    pendingFriendRequests.firstOrNull()?.let { (reqId, reqName) ->
        Dialog(onDismissRequest = { pendingFriendRequests = pendingFriendRequests.filterNot { it.first == reqId } }) {
            Surface(
                shape = RoundedCornerShape(20.dp),
                color = AppColors.surface,
                border = androidx.compose.foundation.BorderStroke(1.dp, AppColors.outline),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(Modifier.padding(20.dp)) {
                    Text("好友请求", color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(10.dp))
                    Text("「$reqName」请求添加你为联系人", color = AppColors.textSecondary, fontSize = 14.sp)
                    Spacer(Modifier.height(6.dp))
                    Text(
                        "ID: " + DeviceIdentity.shortId(reqId),
                        color = AppColors.textTertiary, fontSize = 12.sp,
                        fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
                    )
                    Spacer(Modifier.height(6.dp))
                    Text("同意后你们可以长期加密通信", color = AppColors.textTertiary, fontSize = 11.sp)
                    Spacer(Modifier.height(16.dp))
                    Row {
                        Button(
                            onClick = { rejectFriendRequest(reqId) },
                            modifier = Modifier.weight(1f).height(44.dp),
                            shape = RoundedCornerShape(12.dp),
                            colors = ButtonDefaults.buttonColors(containerColor = AppColors.surfaceAlt)
                        ) { Text("拒绝", fontSize = 14.sp) }
                        Spacer(Modifier.width(10.dp))
                        Button(
                            onClick = { acceptFriendRequest(reqId, reqName) },
                            modifier = Modifier.weight(1f).height(44.dp),
                            shape = RoundedCornerShape(12.dp),
                            colors = ButtonDefaults.buttonColors(containerColor = AppColors.primary)
                        ) { Text("同意", fontSize = 14.sp) }
                    }
        }
    }
}
}
    // ===== 二维码扫码添加好友 =====
    // 扫码结果（deviceId, name）→ 确认对话框
    var qrScanned by remember { mutableStateOf<Pair<String, String>?>(null) }
    val qrScanLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == android.app.Activity.RESULT_OK) {
            val content = result.data?.getStringExtra("SCAN_RESULT")
            if (content != null) {
                val decoded = QrContact.decode(content)
                if (decoded != null) {
                    if (decoded.first == myDeviceId) {
                        Toast.makeText(context, "这是你自己的二维码", Toast.LENGTH_SHORT).show()
                    } else {
                        qrScanned = decoded
                    }
                } else {
                    Toast.makeText(context, "不是 Everett 好友二维码", Toast.LENGTH_SHORT).show()
                }
            }
        }
    }
    fun launchQrScanner() {
        try {
            val scanIntent = com.journeyapps.barcodescanner.ScanContract()
            qrScanLauncher.launch(scanIntent.createIntent(context, com.journeyapps.barcodescanner.ScanOptions().apply {
                setDesiredBarcodeFormats(listOf("QR_CODE"))
                setPrompt("扫描好友二维码")
                setBeepEnabled(true)
                setOrientationLocked(true)
            }))
        } catch (e: Exception) {
            Toast.makeText(context, "扫码启动失败: ${e.message}", Toast.LENGTH_SHORT).show()
        }
    }
    // 添加好友 Bottom Sheet（+ 按钮入口）
    var addSheetVisible by remember { mutableStateOf(false) }

    // 扫码结果确认对话框
    qrScanned?.let { (targetId, targetName) ->
        // 已是好友？→ 直接显示名片可进入聊天；否则发送请求
        val alreadyFriend = contacts.any { it.deviceId == targetId }
        Dialog(onDismissRequest = { qrScanned = null }) {
            Surface(
                shape = RoundedCornerShape(20.dp),
                color = AppColors.surface,
                border = androidx.compose.foundation.BorderStroke(1.dp, AppColors.outline),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(Modifier.padding(20.dp)) {
                    if (alreadyFriend) {
                        // ===== 已是好友：显示名片 + 直接聊天 =====
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            AvatarCircle(name = targetName, size = 44.dp)
                            Spacer(Modifier.width(12.dp))
                            Column {
                                Text(targetName, color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                                Text("已是好友", color = AppColors.success, fontSize = 12.sp)
                            }
                        }
                        Spacer(Modifier.height(8.dp))
                        Text(
                            "ID: " + DeviceIdentity.shortId(targetId),
                            color = AppColors.textTertiary, fontSize = 12.sp,
                            fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
                        )
                        Spacer(Modifier.height(16.dp))
                        Row {
                            Button(
                                onClick = { qrScanned = null },
                                modifier = Modifier.weight(1f).height(44.dp),
                                shape = RoundedCornerShape(12.dp),
                                colors = ButtonDefaults.buttonColors(containerColor = AppColors.surfaceAlt)
                            ) { Text("关闭", fontSize = 14.sp) }
                            Spacer(Modifier.width(10.dp))
                            Button(
                                onClick = {
                                    qrScanned = null
                                    // 直接进入与该好友的加密聊天
                                    updateConversation("peer", targetId, targetName, "")
                                    activeConv = Conversation(id = targetId, name = targetName, type = "peer", lastText = "", lastTime = 0)
                                    screen = "chat"
                                },
                                modifier = Modifier.weight(1f).height(44.dp),
                                shape = RoundedCornerShape(12.dp),
                                colors = ButtonDefaults.buttonColors(containerColor = AppColors.primary)
                            ) { Text("发消息", fontSize = 14.sp) }
                        }
                    } else {
                        // ===== 非好友：发送好友请求 =====
                        Text("添加好友", color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                        Spacer(Modifier.height(10.dp))
                        Text("添加「$targetName」为联系人？", color = AppColors.textSecondary, fontSize = 14.sp)
                        Spacer(Modifier.height(6.dp))
                        Text(
                            "ID: " + DeviceIdentity.shortId(targetId),
                            color = AppColors.textTertiary, fontSize = 12.sp,
                            fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
                        )
                        Spacer(Modifier.height(6.dp))
                        Text("对方同意后你们可以长期加密通信", color = AppColors.textTertiary, fontSize = 11.sp)
                        Spacer(Modifier.height(16.dp))
                        Row {
                            Button(
                                onClick = { qrScanned = null },
                                modifier = Modifier.weight(1f).height(44.dp),
                                shape = RoundedCornerShape(12.dp),
                                colors = ButtonDefaults.buttonColors(containerColor = AppColors.surfaceAlt)
                            ) { Text("取消", fontSize = 14.sp) }
                            Spacer(Modifier.width(10.dp))
                            Button(
                                onClick = {
                                    qrScanned = null
                                    sendFriendRequest(targetId, deviceName)
                                },
                                modifier = Modifier.weight(1f).height(44.dp),
                                shape = RoundedCornerShape(12.dp),
                                colors = ButtonDefaults.buttonColors(containerColor = AppColors.primary)
                            ) { Text("发送请求", fontSize = 14.sp) }
                        }
                    }
                }
            }
        }
    }

    // + 添加好友 Bottom Sheet
    if (addSheetVisible) {
        androidx.compose.material3.ModalBottomSheet(
            onDismissRequest = { addSheetVisible = false },
            containerColor = AppColors.surface,
            dragHandle = { Box(Modifier.padding(top = 10.dp).size(36.dp, 4.dp).background(AppColors.surfaceAlt, RoundedCornerShape(2.dp))) }
        ) {
            Column(Modifier.padding(bottom = 40.dp)) {
                Text("添加好友", color = AppColors.textPrimary, fontSize = 17.sp, fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.padding(horizontal = 20.dp, vertical = 10.dp))
                Row(
                    Modifier.fillMaxWidth().clickable {
                        addSheetVisible = false
                        launchQrScanner()
                    }.padding(horizontal = 20.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Default.QrCodeScanner, contentDescription = null, tint = AppColors.primary, modifier = Modifier.size(22.dp))
                    Spacer(Modifier.width(14.dp))
                    Column(Modifier.weight(1f)) {
                        Text("扫一扫", color = AppColors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Medium)
                        Text("扫描对方二维码添加好友", color = AppColors.textTertiary, fontSize = 12.sp)
                    }
                    Icon(Icons.Default.ChevronRight, contentDescription = null, tint = AppColors.textTertiary)
                }
                HorizontalDivider(color = AppColors.outline, modifier = Modifier.padding(horizontal = 20.dp))
                Row(
                    Modifier.fillMaxWidth().clickable {
                        addSheetVisible = false
                        screen = "qrcode"
                    }.padding(horizontal = 20.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Default.QrCode, contentDescription = null, tint = AppColors.primary, modifier = Modifier.size(22.dp))
                    Spacer(Modifier.width(14.dp))
                    Column(Modifier.weight(1f)) {
                        Text("我的二维码", color = AppColors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Medium)
                        Text("展示二维码，让对方扫码添加你", color = AppColors.textTertiary, fontSize = 12.sp)
                    }
                    Icon(Icons.Default.ChevronRight, contentDescription = null, tint = AppColors.textTertiary)
                }
            }
        }
    }

    Box {
        android.util.Log.i("Render", "AppRoot Box reached")
    Scaffold(
        containerColor = AppColors.bg,
        contentWindowInsets = WindowInsets.systemBars.only(WindowInsetsSides.Horizontal),
        bottomBar = {
            // 全屏聊天/通话时不显示底部导航
            if (screen == "tabs") {
                val unread = conversations.sumOf { it.unread }
                BottomNavBar(
                    currentTab = mainTab,
                    unreadCount = unread,
                    onTabSelected = { mainTab = it }
                )
            }
        }
    ) { padding ->
        android.util.Log.i("Render", "Scaffold content reached")
        Box(Modifier.fillMaxSize().padding(padding).background(AppGradients.bg)) {
            // 页面切换动画（淡入淡出为主 + 极轻微滑动，避免列表页切换抖动）
            AnimatedContent(
                targetState = screen,
                transitionSpec = {
                    val target = targetState
                    val initial = initialState
                    val fullScreen = target == "chat" || target == "call" || target == "qrcode" || target == "netmap"
                    val fromFullScreen = initial == "chat" || initial == "call" || initial == "qrcode" || initial == "netmap"
                    if (fullScreen || fromFullScreen) {
                        fadeIn(androidx.compose.animation.core.tween(180)).togetherWith(
                            fadeOut(androidx.compose.animation.core.tween(120))
                        )
                    } else {
                        (fadeIn(androidx.compose.animation.core.tween(220)) +
                                slideInHorizontally { it / 25 })
                            .togetherWith(
                                fadeOut(androidx.compose.animation.core.tween(150)) +
                                        slideOutHorizontally { -it / 25 }
                            )
                    }
                },
                label = "screen"
            ) { currentScreen ->
                android.util.Log.i("Render", "AnimatedContent reached, current=" + currentScreen)
            when {
                // ===== 通话全屏 =====
                currentScreen == "call" -> {
                    val incoming = callScreen == "incoming"
                    CallScreen(
                        isVideo = callIsVideo,
                        state = if (callScreen == "ended") "ended" else if (callScreen == "active") "active" else "connecting",
                        remoteVideo = callRemoteTrack,
                        localVideo = callLocalTrack,
                        peerName = peerName,
                        durationSeconds = callDuration,
                        eglBaseContext = callManager?.getEglBaseContext(),
                        summary = callSummary,
                        onHangup = {
                            RingtoneHelper.stopRingtone()
                            callManager?.hangup()
                            callScreen = "none"
                            screen = "tabs"
                            activeConv = null
                            kotlinx.coroutines.MainScope().launch {
                                kotlinx.coroutines.delay(500)
                                callManager?.destroy()
                                callManager = null
                            }
                        },
                        onAccept = if (incoming) ({
                            RingtoneHelper.stopRingtone()
                            callManager?.answerCall()
                            callScreen = "connecting"
                        }) else null,
                        onReject = if (incoming) ({
                            RingtoneHelper.stopRingtone()
                            callManager?.rejectCall()
                            callScreen = "none"
                            screen = "tabs"
                            activeConv = null
                            kotlinx.coroutines.MainScope().launch {
                                kotlinx.coroutines.delay(500)
                                callManager?.destroy()
                                callManager = null
                            }
                        }) else null
                    )
                }
                // ===== 中继网可视化 =====
                screen == "netmap" -> {
                    NetMapScreen(
                        onBack = {
                            screen = "tabs"
                            activeConv = null
                        }
                    )
                }
                // ===== 发现页子功能（局域网/云中继/蓝牙直连，旧 ConnectScreen 子页） =====
                screen == "connect" -> {
                    ConnectScreen(
                        deviceName = deviceName,
                        onBack = { screen = "tabs" },
                        onConnected = { t, name ->
                            transport?.disconnect()
                            transport = t
                            peerConnected = true
                            peerName = name
                            updateConversation("peer", t.deviceId, name, "加密连接已建立")
                            screen = "tabs"
                            mainTab = MainTab.MESSAGES
                        },
                        onOpenNetMap = {
                            screen = "netmap"
                            activeConv = null
                        },
                        onOpenQrCode = { screen = "qrcode" },
                        onScanQr = { addSheetVisible = true },
                        relayUrl = relayUrl, relayHttp = relayHttp,
                        relayRoom = relayRoom, relayPass = relayPass,
                        initialTab = connectFeature
                    )
                }
                // ===== 我的二维码 =====
                screen == "qrcode" -> {
                    QrCodeScreen(
                        deviceName = deviceName,
                        myDeviceId = myDeviceId,
                        onBack = {
                            screen = "tabs"
                        }
                    )
                }
                // ===== 全屏聊天 =====
                screen == "chat" -> {
                    val conv = activeConv
                    if (conv != null) {
                        // 对话隔离：切换 peer 会话时从本地 DB 加载该会话历史（不混入其他会话）
                        if (conv.type == "peer" || conv.type == "debug") {
                            LaunchedEffect(conv.id) {
                                try {
                                    val hist = msgStore.loadMessages(conv.id, 200)
                                    // 只清空并加载该会话的消息（不动 aiMessages）
                                    messages.removeAll { it.role == "peer" }
                                    hist.forEach { m ->
                                        val ui = m.toUiMessage()
                                        if (messages.none { it.id == ui.id }) messages.add(ui)
                                    }
                                    DevLog.i("Store", "加载会话 ${conv.id.take(8)} 历史 ${hist.size} 条")
                                } catch (e: Exception) {
                                    DevLog.e("Store", "加载会话历史失败", e)
                                }
                            }
                        }
                        ChatScreen(
                            messages = if (conv.type == "ai") aiMessages else messages,
                            transport = if (conv.type == "peer") transport else null,
                            peerConnected = peerConnected,
                            peerName = conv.name,
                            deviceName = deviceName,
                            aiOnly = conv.type == "ai",
                            peerDeviceId = if (conv.type == "peer") conv.id else "",
                            peerOnline = conv.id in onlineDeviceIds,
                            onPersist = { m, convId ->
                                var mediaPath = ""; var mediaMime = ""; var mediaSize = 0L
                                m.file?.data?.let { data ->
                                    try {
                                        val dir = java.io.File(context.filesDir, "media").apply { mkdirs() }
                                        val f = java.io.File(dir, m.file.name)
                                        f.writeBytes(data)
                                        mediaPath = f.absolutePath
                                        mediaMime = m.file.mime
                                        mediaSize = m.file.size
                                    } catch (_: Exception) {}
                                }
                                try {
                                    msgStore.insertMessage(
                                        id = m.id, convId = convId, role = m.role, text = m.text,
                                        reasoning = m.reasoning, senderName = m.senderName, senderId = m.senderId,
                                        isError = m.isError, mediaPath = mediaPath, mediaMime = mediaMime, mediaSize = mediaSize
                                    )
                                } catch (_: Exception) {}
                            },
                            onDeleteMsg = { msgId ->
                                messages.removeAll { it.id == msgId }
                                aiMessages.removeAll { it.id == msgId }
                                try { msgStore.deleteMessage(msgId) } catch (_: Exception) {}
                            },
                            onBack = {
                                screen = "tabs"
                                activeConv = null
                            },
                            onStartCall = { video ->
                                val t = transport
                                if (t != null && t.isConnected()) {
                                    callSummary = ""
                                    // 刷新 Cloudflare TURN 凭据（跨网互拨必需，与 iOS 同端点）
                                    top.vios.chat.call.CallManager.TurnCredentialsHolder.refresh(
                                        if (relayHttp.isNotBlank()) relayHttp.trimEnd('/') else "https://relay.vios.top"
                                    )
                                    val cm = CallManager(context, t, deviceName)
                                    callManager = cm
                                    callIsVideo = video
                                    callScreen = "connecting"
                                    screen = "call"
                                    cm.setListener(object : CallManager.CallListener {
                                        override fun onIncomingCall(callId: String, from: String, video: Boolean) {}
                                        override fun onCallConnected(callId: String) {
                                            kotlinx.coroutines.MainScope().launch { callScreen = "active" }
                                        }
                                        override fun onCallEnded(callId: String, reason: String, summary: String) {
                                            RingtoneHelper.stopRingtone()
                                            kotlinx.coroutines.MainScope().launch {
                                                callScreen = "ended"
                                                callSummary = summary
                                                if (summary.isNotEmpty()) {
                                                    messages.add(UiMessage("call-" + System.currentTimeMillis().toString(), "peer", summary))
                                                }
                                                if (reason.isNotEmpty() && !reason.contains("挂断")) {
                                                    Toast.makeText(context, reason, Toast.LENGTH_LONG).show()
                                                }
                                            }
                                        }
                                        override fun onCallError(message: String) {
                                            RingtoneHelper.stopRingtone()
                                            kotlinx.coroutines.MainScope().launch {
                                                callScreen = "ended"
                                                callSummary = "${if (callIsVideo) "视频通话" else "语音通话"} · 未接通"
                                                Toast.makeText(context, "通话错误: $message", Toast.LENGTH_LONG).show()
                                            }
                                        }
                                        override fun onRemoteVideoTrack(track: org.webrtc.VideoTrack) {
                                            kotlinx.coroutines.MainScope().launch { callRemoteTrack = track }
                                        }
                                        override fun onLocalVideoTrack(track: org.webrtc.VideoTrack) {
                                            kotlinx.coroutines.MainScope().launch { callLocalTrack = track }
                                        }
                                    })
                                } else {
                                    Toast.makeText(context, "对方不在线，无法发起通话", Toast.LENGTH_SHORT).show()
                                }
                            }
                        )
                    }
                }
                // ===== 主 Tab =====
                screen == "tabs" -> {
                    when (mainTab) {
                        MainTab.MESSAGES -> EvoMessagesScreen(
                            conversations = conversations.toList(),
                            aiLastText = aiMessages.lastOrNull()?.text ?: "",
                            aiGenerating = aiMessages.lastOrNull()?.let { it.role == "ai" && it.text.isEmpty() && !it.isError } ?: false,
                            deviceLastText = "",
                            deviceHasMessages = false,
                            onlineDeviceIds = onlineDeviceIds,
                            onOpenAI = {
                                val conv = Conversation(id = "ai", name = "AI 助手", type = "ai", lastText = "", lastTime = 0)
                                activeConv = conv
                                screen = "chat"
                            },
                            onOpenDevice = {
                                Toast.makeText(context, "设备互联（Android 开发中，下一版接入）", Toast.LENGTH_SHORT).show()
                            },
                            onOpenConversation = { conv ->
                                activeConv = conv
                                val idx = conversations.indexOfFirst { it.id == conv.id && it.type == conv.type }
                                if (idx >= 0) conversations[idx] = conversations[idx].copy(unread = 0)
                                screen = "chat"
                            },
                            onAddFriend = { addSheetVisible = true }
                        )
                        MainTab.CONTACTS -> EvoContactsScreen(
                            deviceName = deviceName,
                            myDeviceId = myDeviceId,
                            relayHttp = relayHttp,
                            contacts = contacts,
                            onAddFriend = { addSheetVisible = true },
                            onAddContact = { id, name ->
                                // 添加在线用户为联系人
                                val c = Contact(deviceId = id, name = name, status = "pending")
                                sendFriendRequest(id, deviceName)
                            },
                            onOpenChat = { id, name ->
                                updateConversation("peer", id, name, "")
                                activeConv = Conversation("peer", id, name, "", 0)
                                screen = "chat"
                            }
                        )
                        MainTab.DISCOVER -> EvoDiscoverScreen(
                            onGame = {
                                Toast.makeText(context, "游戏中心（开发中）", Toast.LENGTH_SHORT).show()
                            },
                            onFileTransfer = {
                                Toast.makeText(context, "文件互传（开发中）", Toast.LENGTH_SHORT).show()
                            },
                            onDeviceLink = {
                                Toast.makeText(context, "设备互联（Android 开发中）", Toast.LENGTH_SHORT).show()
                            },
                            onLan = { connectFeature = 0; screen = "connect" },
                            onRelay = { connectFeature = 1; screen = "connect" },
                            onBluetooth = { connectFeature = 2; screen = "connect" },
                            onTopology = {
                                screen = "netmap"
                                activeConv = null
                            },
                            onMyQr = { screen = "qrcode" },
                            onScan = { addSheetVisible = true }
                        )
                        MainTab.MINE -> EvoMineScreen(
                            deviceName = deviceName,
                            deviceId = myDeviceId,
                            onProfileEdit = {
                                Toast.makeText(context, "个人资料编辑（开发中）", Toast.LENGTH_SHORT).show()
                            },
                            onAppearance = {
                                Toast.makeText(context, "外观设置（开发中）", Toast.LENGTH_SHORT).show()
                            },
                            onDeviceSettings = {
                                Toast.makeText(context, "设备管理（开发中）", Toast.LENGTH_SHORT).show()
                            },
                            onStorage = {
                                Toast.makeText(context, "存储管理（开发中）", Toast.LENGTH_SHORT).show()
                            },
                            onIdentity = {
                                Toast.makeText(context, "恢复密钥（开发中）", Toast.LENGTH_SHORT).show()
                            },
                            onAbout = {
                                val dev = DeviceNameManager.getDeviceName(context)
                                val shortId = myDeviceId.take(8)
                                Toast.makeText(context, "EVO ${BuildConfig.VERSION_NAME} · Android · $dev · $shortId · E2Ev1", Toast.LENGTH_LONG).show()
                            },
                            onCheckUpdate = { checkForUpdate() },
                            debugMode = debugMode,
                            onDebugModeChanged = { setDebugMode(it) }
                        )
                    }
                }
            }
            }
            }
        }
    }

    // 统一顶部 Snackbar（悬浮在页面之上）
    Box(Modifier.fillMaxSize().padding(top = 8.dp), contentAlignment = Alignment.TopCenter) {
        AppSnackbarHost(snackbarHostState)
    }

    // ===== EVO 更新服务弹窗（Material 3 自定义样式） =====
    pendingUpdate?.let { (apkFile, apkName, fromServer) ->
        EvoUpdateDialog(
            apkFile = apkFile,
            apkName = apkName,
            fromServer = fromServer,
            onDismiss = { pendingUpdate = null },
            onInstall = {
                pendingUpdate = null
                try {
                    val uri = androidx.core.content.FileProvider.getUriForFile(
                        context, "${BuildConfig.APPLICATION_ID}.fileprovider", apkFile
                    )
                    val intent = android.content.Intent(android.content.Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, "application/vnd.android.package-archive")
                        addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(intent)
                } catch (e: Exception) {
                    Toast.makeText(context, "安装失败: ${e.message}", Toast.LENGTH_LONG).show()
                }
            }
        )
    }
    }

/** 旧 AlertDialog 安装确认（保留作兜底，正常走 Compose EvoUpdateDialog） */
private fun promptInstallApk(ctx: android.content.Context, apkFile: java.io.File, name: String, fromServer: Boolean = false) {
    try {
        val title = if (fromServer) "EVO 更新服务" else "收到更新包"
        val source = if (fromServer) "来源：EVO 云端更新服务（Hermes 推送）" else "来源：好友发送"
        android.app.AlertDialog.Builder(ctx)
            .setTitle(title)
            .setMessage("$name\n(${apkFile.length() / 1024 / 1024} MB)\n$source\n是否立即安装？")
            .setPositiveButton("安装") { _, _ ->
                try {
                    val uri = androidx.core.content.FileProvider.getUriForFile(
                        ctx, "${BuildConfig.APPLICATION_ID}.fileprovider", apkFile
                    )
                    val intent = android.content.Intent(android.content.Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, "application/vnd.android.package-archive")
                        addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    ctx.startActivity(intent)
                } catch (e: Exception) {
                    Toast.makeText(ctx, "安装失败: ${e.message}", Toast.LENGTH_LONG).show()
                }
            }
            .setNegativeButton("稍后", null)
            .show()
    } catch (e: Exception) {
        Toast.makeText(ctx, "无法打开安装: ${e.message}", Toast.LENGTH_LONG).show()
    }
}

data class Conversation(
    val id: String,              // "ai" 或 对方 deviceId
    val name: String,            // 显示名
    val type: String,            // "ai" | "peer"
    val lastText: String,        // 最后一条消息
    val lastTime: Long,          // 最后消息时间戳
    val unread: Int = 0          // 未读数
)

/** 底部导航 Tab 定义 */
enum class MainTab(val title: String) {
    MESSAGES("消息"),
    CONTACTS("通讯录"),
    DISCOVER("发现"),
    MINE("我的")
}
@Composable
fun BottomNavBar(
    currentTab: MainTab,
    unreadCount: Int = 0,
    onTabSelected: (MainTab) -> Unit
) {
    // M3 系统 NavigationBar（对应 iOS TabView，原生组件不画假 TabBar）
    NavigationBar(
        containerColor = AppColors.surface,
        tonalElevation = 0.dp
    ) {
        val evoTab = when (currentTab) {
            MainTab.MESSAGES -> EvoTab.MESSAGES
            MainTab.CONTACTS -> EvoTab.CONTACTS
            MainTab.DISCOVER -> EvoTab.DISCOVER
            MainTab.MINE -> EvoTab.MINE
        }
        EvoTab.entries.forEach { tab ->
            val selected = tab == evoTab
            NavigationBarItem(
                selected = selected,
                onClick = {
                    onTabSelected(
                        when (tab) {
                            EvoTab.MESSAGES -> MainTab.MESSAGES
                            EvoTab.CONTACTS -> MainTab.CONTACTS
                            EvoTab.DISCOVER -> MainTab.DISCOVER
                            EvoTab.MINE -> MainTab.MINE
                        }
                    )
                },
                icon = {
                    Icon(
                        imageVector = if (selected) tab.selectedIcon else tab.icon,
                        contentDescription = tab.title,
                        tint = if (selected) AppColors.primary else AppColors.textTertiary
                    )
                },
                label = {
                    Text(
                        tab.title,
                        fontSize = 11.sp,
                        color = if (selected) AppColors.primary else AppColors.textTertiary,
                        fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal
                    )
                },
                colors = NavigationBarItemDefaults.colors(
                    selectedIconColor = AppColors.primary,
                    selectedTextColor = AppColors.primary,
                    indicatorColor = AppColors.primaryDim,
                    unselectedIconColor = AppColors.textTertiary,
                    unselectedTextColor = AppColors.textTertiary
                )
            )
        }
    }
}

/** 统一顶部栏（所有页面一致：紧凑高度、文字居中、返回按钮） */
@Composable
fun AppTopBar(
    title: String,
    onBack: (() -> Unit)? = null,
    actions: @Composable RowScope.() -> Unit = {},
    subtitle: String = "",
    hasActions: Boolean = false
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(AppColors.glass)
            .drawBehind {
                // 底部 1dp 高光描边（玻璃质感分层）
                drawLine(
                    AppColors.outlineStrong,
                    Offset(0f, size.height - 1.dp.toPx()),
                    Offset(size.width, size.height - 1.dp.toPx()),
                    strokeWidth = 1.dp.toPx()
                )
            }
            .windowInsetsPadding(WindowInsets.statusBars)
            .height(40.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // 左侧：返回按钮或占位（保持标题居中）
        if (onBack != null) {
            IconButton(onClick = onBack) {
                Icon(Icons.Default.ArrowBack, contentDescription = "返回", tint = Color.White)
            }
        } else {
            Spacer(Modifier.width(48.dp))
        }
        // 标题：水平居中、垂直居中
        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxHeight(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Text(
                title,
                color = Color.White,
                fontSize = 16.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 1,
                textAlign = TextAlign.Center
            )
            if (subtitle.isNotEmpty()) {
                Text(
                    subtitle,
                    color = AppColors.textSecondary,
                    fontSize = 10.sp,
                    maxLines = 1,
                    textAlign = TextAlign.Center
                )
            }
        }
        // 右侧：actions 或占位（保持标题居中）
        if (hasActions) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                actions()
            }
        } else {
            Spacer(Modifier.width(48.dp))
        }
    }
}

/** 统一底部安全区（导航栏避让） */
@Composable
fun BottomSafeArea(content: @Composable () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .navigationBarsPadding()
    ) {
        content()
    }
}

/** 统一提示弹窗（顶部 Snackbar，替代 Toast） */
@Composable
fun rememberAppSnackbar(): Pair<SnackbarHostState, (String) -> Unit> {
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    val show: (String) -> Unit = { message ->
        scope.launch {
            snackbarHostState.showSnackbar(
                message = message,
                duration = SnackbarDuration.Short
            )
        }
    }
    return Pair(snackbarHostState, show)
}

/** 统一 Snackbar 宿主（顶部） */
@Composable
fun AppSnackbarHost(hostState: SnackbarHostState) {
    SnackbarHost(
        hostState = hostState,
        modifier = Modifier
            .fillMaxWidth()
            .statusBarsPadding()
            .padding(horizontal = 12.dp, vertical = 8.dp),
        snackbar = { data ->
            Snackbar(
                snackbarData = data,
                containerColor = AppColors.surfaceAlt,
                contentColor = Color.White,
                shape = RoundedCornerShape(12.dp)
            )
        }
    )
}

// ================= 通讯录 =================

/**
 * 通讯录页：显示在线用户（从中继 /users 获取）+ 已添加联系人
 * 用户可主动添加对方（需对方同意后长期通信）
 */
@Composable
fun ContactsScreen(
    deviceName: String,
    myDeviceId: String,
    relayHttp: String,
    relayRoom: String,
    transport: Transport?,
    contacts: List<Contact>,
    onAddContact: (Contact) -> Unit,
    onOpenChat: (Contact) -> Unit,
    onAddFriend: () -> Unit = {}   // 右上角 + 添加好友（扫一扫/我的二维码）
) {
    val context = LocalContext.current
    var onlineUsers by remember { mutableStateOf<List<org.json.JSONObject>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    // 已发送请求的设备 ID（等待对方同意）
    var requestedIds by remember { mutableStateOf<Set<String>>(emptySet()) }

    // 从中继获取在线用户
    LaunchedEffect(Unit) {
        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
            try {
                val base = if (relayHttp.isNotBlank()) relayHttp.trimEnd('/')
                    else "https://relay.vios.top"
                val conn = java.net.URL("$base/users").openConnection() as java.net.HttpURLConnection
                conn.connectTimeout = 6000
                conn.readTimeout = 6000
                val resp = conn.inputStream.bufferedReader().use { it.readText() }
                val arr = org.json.JSONObject(resp).optJSONArray("users") ?: org.json.JSONArray()
                val list = ArrayList<org.json.JSONObject>()
                for (i in 0 until arr.length()) {
                    val u = arr.getJSONObject(i)
                    if (u.optString("deviceId", "") != myDeviceId) list.add(u)
                }
                onlineUsers = list
            } catch (_: Exception) {}
            loading = false
        }
    }

    Column(Modifier.fillMaxSize().background(AppGradients.bg)) {
        AppTopBar(
            title = "通讯录",
            hasActions = true,
            actions = {
                // + 添加好友（扫一扫 / 我的二维码）
                Box(
                    modifier = Modifier
                        .padding(end = 4.dp)
                        .size(36.dp)
                        .clip(RoundedCornerShape(10.dp))
                        .clickable { onAddFriend() },
                    contentAlignment = Alignment.Center
                ) {
                    Text("+", color = AppColors.textPrimary, fontSize = 22.sp, fontWeight = FontWeight.Light)
                }
            }
        )

        // 搜索框（现代 Contact System）
        var searchQuery by remember { mutableStateOf("") }
        val filteredOnline = remember(onlineUsers, searchQuery) {
            if (searchQuery.isBlank()) onlineUsers
            else onlineUsers.filter { it.optString("name", "").contains(searchQuery, ignoreCase = true) }
        }
        val filteredContacts = remember(contacts, searchQuery) {
            if (searchQuery.isBlank()) contacts
            else contacts.filter { it.name.contains(searchQuery, ignoreCase = true) }
        }
        Surface(
            shape = RoundedCornerShape(AppRadius.medium),
            color = AppColors.surfaceHigh,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = AppSpacing.lg, vertical = AppSpacing.sm)
        ) {
            Row(
                Modifier.padding(horizontal = AppSpacing.md, vertical = 2.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(Icons.Default.Search, contentDescription = null, tint = AppColors.textTertiary, modifier = Modifier.size(14.dp))
                Spacer(Modifier.width(8.dp))
                androidx.compose.foundation.text.BasicTextField(
                    value = searchQuery,
                    onValueChange = { searchQuery = it },
                    textStyle = androidx.compose.ui.text.TextStyle(color = AppColors.textPrimary, fontSize = 14.sp),
                    singleLine = true,
                    modifier = Modifier.weight(1f)
                )
                if (searchQuery.isNotEmpty()) {
                    Text(
                        "",
                        color = AppColors.textTertiary,
                        modifier = Modifier
                            .clickable { searchQuery = "" }
                            .padding(6.dp)
                    )
                }
            }
        }
        if (searchQuery.isBlank()) {
            Text(
                "搜索联系人", color = AppColors.textTertiary, fontSize = 11.sp,
                modifier = Modifier.padding(start = 20.dp, bottom = 2.dp)
            )
        }

        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp)
        ) {
            // ===== 我的名片 =====
            Surface(
                shape = RoundedCornerShape(16.dp),
                color = AppColors.surface,
                border = androidx.compose.foundation.BorderStroke(1.dp, AppColors.outline),
                modifier = Modifier.fillMaxWidth()
            ) {
                Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                    AvatarCircle(name = deviceName, size = 44.dp)
                    Spacer(Modifier.width(12.dp))
                    Column {
                        Text(deviceName, color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                        Spacer(Modifier.height(3.dp))
                        Text(
                            "我的 ID: " + DeviceIdentity.shortId(myDeviceId),
                            color = AppColors.textSecondary, fontSize = 12.sp,
                            fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
                        )
                    }
                }
            }
            Spacer(Modifier.height(12.dp))

            // ===== 在线用户（可添加） =====
            Text("在线用户", color = AppColors.textTertiary, fontSize = 12.sp, modifier = Modifier.padding(start = 4.dp, bottom = 6.dp))
            Surface(
                shape = RoundedCornerShape(16.dp),
                color = AppColors.surface,
                border = androidx.compose.foundation.BorderStroke(1.dp, AppColors.outline),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(Modifier.padding(vertical = 4.dp)) {
                    if (loading) {
                        Text("加载中...", color = AppColors.textTertiary, fontSize = 13.sp, modifier = Modifier.padding(14.dp))
                    } else if (filteredOnline.isEmpty()) {
                        Text(if (searchQuery.isBlank()) "暂无在线用户（对方需连接同一中继网）" else "未找到匹配的用户", color = AppColors.textTertiary, fontSize = 13.sp, modifier = Modifier.padding(14.dp))
                    } else {
                        filteredOnline.forEach { u ->
                            val uid = u.optString("deviceId", "")
                            val uname = u.optString("name", "未知设备")
                            val alreadyAdded = contacts.any { it.deviceId == uid }
                            val alreadyRequested = requestedIds.contains(uid)
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 14.dp, vertical = 10.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                AvatarCircle(name = uname, size = 36.dp)
                                Spacer(Modifier.width(10.dp))
                                Column(Modifier.weight(1f)) {
                                    Text(uname, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                                    Text(
                                        "ID: " + DeviceIdentity.shortId(uid),
                                        color = AppColors.textTertiary, fontSize = 11.sp,
                                        fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
                                    )
                                }
                                if (alreadyAdded) {
                                    Surface(shape = RoundedCornerShape(8.dp), color = AppColors.successDim) {
                                        Text("已添加", color = AppColors.success, fontSize = 11.sp,
                                            modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp))
                                    }
                                } else if (alreadyRequested) {
                                    Surface(shape = RoundedCornerShape(8.dp), color = AppColors.surfaceHigh) {
                                        Text("已请求", color = AppColors.textSecondary, fontSize = 11.sp,
                                            modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp))
                                    }
                                } else {
                                    Surface(
                                        shape = RoundedCornerShape(8.dp),
                                        color = AppColors.primary,
                                        modifier = Modifier.clickable {
                                            // 发送好友请求（等对方同意）
                                            requestedIds = requestedIds + uid
                                            onAddContact(Contact(uid, uname))
                                        }
                                    ) {
                                        Text("添加", color = Color.White, fontSize = 12.sp,
                                            modifier = Modifier.padding(horizontal = 14.dp, vertical = 6.dp))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Spacer(Modifier.height(12.dp))

            // ===== 我的联系人 =====
            Text("我的联系人 (${contacts.size})", color = AppColors.textTertiary, fontSize = 12.sp, modifier = Modifier.padding(start = 4.dp, bottom = 6.dp))
            Surface(
                shape = RoundedCornerShape(16.dp),
                color = AppColors.surface,
                border = androidx.compose.foundation.BorderStroke(1.dp, AppColors.outline),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(Modifier.padding(vertical = 4.dp)) {
                    if (filteredContacts.isEmpty()) {
                        Text(if (searchQuery.isBlank()) "暂无联系人，添加后即可长期通信" else "未找到匹配的联系人", color = AppColors.textTertiary, fontSize = 13.sp, modifier = Modifier.padding(14.dp))
                    } else {
                        filteredContacts.forEach { c ->
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable { onOpenChat(c) }
                                    .padding(horizontal = 14.dp, vertical = 10.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                AvatarCircle(name = c.name, size = 36.dp)
                                Spacer(Modifier.width(10.dp))
                                Column(Modifier.weight(1f)) {
                                    Text(c.name, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                                    Text(
                                        "ID: " + DeviceIdentity.shortId(c.deviceId),
                                        color = AppColors.textTertiary, fontSize = 11.sp,
                                        fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
                                    )
                                }
                                Text("聊天 >", color = AppColors.primary, fontSize = 12.sp)
                            }
                        }
                    }
                }
            }
            Spacer(Modifier.height(12.dp))

            // ===== 添加说明 =====
            Text(
                "说明：对方连接同一中继网后，你可以在线用户中添加对方；添加后即建立长期联系，可随时发起加密聊天。",
                color = AppColors.textTertiary, fontSize = 11.sp, lineHeight = 16.sp,
                modifier = Modifier.padding(horizontal = 4.dp)
            )
        }
    }
}

// ================= 消息列表页 =================

/** 会话行 */
@Composable
fun ConversationRow(
    conv: Conversation,
    onClick: () -> Unit
) {
    Surface(
        color = Color.Transparent,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // 头像
            AvatarCircle(
                name = if (conv.type == "ai") "AI 助手" else conv.name,
                size = 50.dp
            )
            Spacer(Modifier.width(12.dp))
            // 名称 + 最后消息
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        conv.name,
                        color = Color.White,
                        fontSize = 16.sp,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.weight(1f)
                    )
                    Text(
                        formatConvTime(conv.lastTime),
                        color = AppColors.textTertiary,
                        fontSize = 11.sp
                    )
                }
                Spacer(Modifier.height(3.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        conv.lastText.ifEmpty { "开始聊天吧" },
                        color = AppColors.textSecondary,
                        fontSize = 13.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f)
                    )
                    if (conv.unread > 0) {
                        Spacer(Modifier.width(8.dp))
                        Box(
                            modifier = Modifier
                                .background(AppColors.error, RoundedCornerShape(10.dp))
                                .padding(horizontal = 6.dp, vertical = 2.dp)
                        ) {
                            Text(
                                if (conv.unread > 99) "99+" else "${conv.unread}",
                                color = Color.White,
                                fontSize = 10.sp
                            )
                        }
                    }
                }
            }
        }
        // 分隔线
        HorizontalDivider(color = AppColors.surfaceHigh, thickness = 0.5.dp)
    }
}

/** 消息 Tab 主界面（会话列表） */
@Composable
fun MessagesScreen(
    conversations: List<Conversation>,
    onOpenConversation: (Conversation) -> Unit,
    aiLastText: String = "",        // AI 最后消息预览
    aiGenerating: Boolean = false,   // AI 是否正在生成
    onAddFriend: () -> Unit = {}     // 右上角 + 添加好友
) {
    Column(Modifier.fillMaxSize().background(AppGradients.bg)) {
        AppTopBar(
            title = "消息",
            hasActions = true,
            actions = {
                // + 添加好友（扫一扫 / 我的二维码）
                Box(
                    modifier = Modifier
                        .padding(end = 4.dp)
                        .size(36.dp)
                        .clip(RoundedCornerShape(10.dp))
                        .clickable { onAddFriend() },
                    contentAlignment = Alignment.Center
                ) {
                    Text("+", color = AppColors.textPrimary, fontSize = 22.sp, fontWeight = FontWeight.Light)
                }
            }
        )
        LazyColumn(Modifier.fillMaxSize()) {
            // ===== AI 助手固定置顶（主要会话） =====
            item {
                ModernConvRow(
                    avatarName = "AI 助手",
                    title = "AI 助手",
                    subtitle = when {
                        aiGenerating -> "正在生成…"
                        aiLastText.isNotEmpty() -> aiLastText
                        else -> "开始聊天吧"
                    },
                    timeText = if (aiLastText.isNotEmpty()) "现在" else "",
                    accent = true,
                    avatarImage = R.drawable.ai_avatar,
                    onClick = { onOpenConversation(Conversation(id = "ai", name = "AI 助手", type = "ai", lastText = "", lastTime = 0)) }
                )
            }
            // ===== 对端会话列表（AI 由置顶项提供，过滤避免重复） =====
            // 去重：同一设备重装后 deviceId 变化会生成同名会话 → 按名称合并，保留最新
            val peerConvs = conversations
                .filter { it.type != "ai" }
                .groupBy { it.name }                      // 按显示名分组
                .map { (_, group) -> group.maxBy { it.lastTime } }  // 每组保留最新
                .sortedByDescending { it.lastTime }
            if (peerConvs.isEmpty()) {
                // 空状态（精致）
                item {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 64.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Icon(Icons.Filled.Message, contentDescription = null, tint = AppColors.textTertiary, modifier = Modifier.size(40.dp))
                        Spacer(Modifier.height(14.dp))
                        Text("还没有聊天记录", color = AppColors.textSecondary, fontSize = 14.sp, fontWeight = FontWeight.Medium)
                        Spacer(Modifier.height(6.dp))
                        Text(
                            "在「发现」连接设备，或在「通讯录」添加好友后开始加密聊天",
                            color = AppColors.textTertiary, fontSize = 12.sp,
                            modifier = Modifier.padding(horizontal = 40.dp),
                            textAlign = TextAlign.Center
                        )
                    }
                }
            } else {
                             items(peerConvs) { conv ->
                    ModernConvRow(
                        avatarName = conv.name,
                        title = conv.name,
                        subtitle = conv.lastText.ifEmpty { "开始聊天吧" },
                        timeText = formatConvTime(conv.lastTime),
                        unread = conv.unread,
                        onClick = { onOpenConversation(conv) }
                    )
                }
            }
        }
    }
}

/** 现代会话行（AI Inbox 风格：无 Card、细分隔线、状态语义色） */
@Composable
fun ModernConvRow(
    avatarName: String,
    title: String,
    subtitle: String,
    timeText: String,
    unread: Int = 0,
    accent: Boolean = false,   // AI 助手等主要会话：标题用强调色
    avatarImage: Any? = null,  // AI 助手默认头像（DrawableRes 或 Painter）
    onClick: () -> Unit
) {
    Surface(
        color = Color.Transparent,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = AppSpacing.lg, vertical = AppSpacing.md),
            verticalAlignment = Alignment.CenterVertically
        ) {
            if (avatarImage != null) {
                // AI 助手图片头像（圆形裁切）
                Box(
                    modifier = Modifier
                        .size(48.dp)
                        .clip(CircleShape)
                        .background(AppColors.surfaceAlt)
                ) {
                    Image(
                        painter = painterResource(id = avatarImage as Int),
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize()
                    )
                }
            } else {
                AvatarCircle(name = avatarName, size = 48.dp)
            }
            Spacer(Modifier.width(AppSpacing.md))
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        title,
                        color = if (accent) AppColors.textPrimary else Color.White,
                        fontSize = AppType.body,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.weight(1f)
                    )
                    Text(
                        timeText,
                        color = AppColors.textTertiary,
                        fontSize = 11.sp
                    )
                }
                Spacer(Modifier.height(3.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        subtitle,
                        color = if (accent) AppColors.textSecondary else AppColors.textSecondary,
                        fontSize = 13.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f)
                    )
                    if (unread > 0) {
                        Spacer(Modifier.width(8.dp))
                        Box(
                            modifier = Modifier
                                .background(AppColors.error, RoundedCornerShape(10.dp))
                                .padding(horizontal = 6.dp, vertical = 2.dp)
                        ) {
                            Text(
                                if (unread > 99) "99+" else "$unread",
                                color = Color.White,
                                fontSize = 10.sp,
                                fontWeight = FontWeight.SemiBold
                            )
                        }
                    }
                }
            }
        }
        HorizontalDivider(color = AppColors.surfaceHigh, thickness = 0.5.dp)
    }
}

/** 会话时间格式化 */
fun formatConvTime(time: Long): String {
    if (time <= 0) return ""
    val cal = java.util.Calendar.getInstance()
    cal.timeInMillis = time
    val now = java.util.Calendar.getInstance()
    val sdf = java.text.SimpleDateFormat("HH:mm", Locale.getDefault())
    return if (cal.get(java.util.Calendar.DAY_OF_YEAR) == now.get(java.util.Calendar.DAY_OF_YEAR)) {
        sdf.format(java.util.Date(time))
    } else {
        java.text.SimpleDateFormat("MM-dd", Locale.getDefault()).format(java.util.Date(time))
    }
}

// ================= 首页 =================

@Composable
fun HomeScreen(
    peerConnected: Boolean,
    peerName: String,
    deviceName: String,
    myDeviceId: String,
    onOpenAI: () -> Unit,
    onOpenChat: () -> Unit,
    onOpenConnect: () -> Unit,
    onOpenSettings: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(listOf(AppColors.surface, AppColors.bg))
            )
    ) {
        // 统一顶部栏
        AppTopBar(
            title = "EVO",
            subtitle = "端到端加密通信 · AI 助手",
            hasActions = true,
            actions = {
                // 连接状态指示灯
                Box(
                    modifier = Modifier
                        .size(10.dp)
                        .background(
                            if (peerConnected) AppColors.success else AppColors.textTertiary,
                            RoundedCornerShape(5.dp)
                        )
                )
                Spacer(Modifier.width(12.dp))
            }
        )

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(Modifier.height(24.dp))

            // 设备信息卡片
            Surface(
                shape = RoundedCornerShape(16.dp),
                color = if (peerConnected) AppColors.successDim else AppColors.surfaceHigh
            ) {
                Column(
                    modifier = Modifier.padding(horizontal = 20.dp, vertical = 14.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(
                        if (peerConnected) "已连接: $peerName" else "未连接对端",
                        color = if (peerConnected) AppColors.successText else AppColors.textSecondary,
                        fontSize = 14.sp
                    )
                    Text(
                        "$deviceName · ${DeviceIdentity.shortId(myDeviceId)}",
                        color = AppColors.textTertiary,
                        fontSize = 11.sp
                    )
                }
            }

        Spacer(Modifier.height(40.dp))

        // 功能卡片（AI 独立模块）
        FeatureCard("AI 助手", "智能对话 · 独立模块", onClick = onOpenAI)
        Spacer(Modifier.height(14.dp))
        FeatureCard("对端聊天", "加密消息 · 语音 · 文件", onClick = onOpenChat)
        Spacer(Modifier.height(14.dp))
        FeatureCard("连接对端", "局域网直连 / 云中继", onClick = onOpenConnect)
        Spacer(Modifier.height(14.dp))
        FeatureCard("设置", "中继服务器 · 权限 · 铃声", onClick = onOpenSettings)

        Spacer(Modifier.weight(1f))
        Text("v${BuildConfig.VERSION_NAME} · E2E Encrypted", fontSize = 12.sp, color = AppColors.textTertiary)
        Spacer(Modifier.height(20.dp))
        }
    }
}

@Composable
fun FeatureCard(title: String, subtitle: String, onClick: () -> Unit) {
    Surface(
        shape = RoundedCornerShape(16.dp),
        color = AppColors.surfaceHigh,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
    ) {
        Row(
            modifier = Modifier.padding(20.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(title, fontSize = 18.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
            Spacer(Modifier.weight(1f))
            Text(subtitle, fontSize = 12.sp, color = AppColors.textTertiary)
            Spacer(Modifier.width(8.dp))
            Icon(Icons.Default.ChevronRight, contentDescription = null, tint = AppColors.textTertiary)
        }
    }
}

// ================= 连接页 =================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ConnectScreen(
    deviceName: String,
    onBack: (() -> Unit)? = null,
    onConnected: (Transport, String) -> Unit,
    onOpenNetMap: () -> Unit = {},
    onOpenQrCode: () -> Unit = {},
    onScanQr: () -> Unit = {},
    relayUrl: String, relayHttp: String, relayRoom: String, relayPass: String,
    initialTab: Int = -1   // >=0 时直接进入对应子页（0=局域网 1=云中继 2=蓝牙），-1=功能列表
) {
    val context = LocalContext.current
    var tab by remember { mutableStateOf(if (initialTab >= 0) initialTab else 0) }   // 0=局域网 1=云中继 2=蓝牙
    var featureList by remember { mutableStateOf(initialTab < 0) }   // true=功能列表主页，false=子页
    var lanMode by remember { mutableStateOf(0) } // 0=服务端 1=客户端
    var clientIp by remember { mutableStateOf("") }
    var connecting by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var scanning by remember { mutableStateOf(false) }
    var discovered by remember { mutableStateOf<List<LanDiscovery.DiscoveredDevice>>(emptyList()) }
    val scope = rememberCoroutineScope()
    val discovery = remember { LanDiscovery(deviceName) }
    val myDeviceId = remember { DeviceIdentity.getDeviceId(context) }

    // 配对码模式状态
    var pairMode by remember { mutableStateOf(0) }    // 0=关闭 1=生成码等待配对 2=输入码匹配
    var myPairCode by remember { mutableStateOf("") }
    var inputPairCode by remember { mutableStateOf("") }
    var pairing by remember { mutableStateOf(false) }
    var pairResult by remember { mutableStateOf<String?>(null) }

    // 本机局域网 IP
    val localIp = remember { getLocalIpAddress() }

    // 生成 6 位配对码
    fun generateCode(): String {
        val sb = StringBuilder()
        val rand = java.util.Random()
        repeat(6) { sb.append(rand.nextInt(10)) }
        return sb.toString()
    }

    // 启动配对监听（等待对方输入我的码）—— 生成方 = 服务端
    fun startPairListener() {
        val code = generateCode()
        myPairCode = code
        pairResult = null
        pairMode = 1

        // 1. 启动 UDP responder：响应对方 pair-probe
        discovery.onPairRequest = { reqCode, fromIp, fromPort ->
            if (reqCode == myPairCode && myPairCode.isNotEmpty()) {
                // 码匹配，回复对方（回到来源端口）
                discovery.respondPair(myPairCode, fromIp, fromPort)
                kotlinx.coroutines.MainScope().launch {
                    pairResult = "配对成功！等待 ${fromIp} 连接..."
                }
            }
        }
        discovery.startResponder()

        // 2. 同时启动 TCP 服务端监听（等待输入方连接）
        connecting = true
        val serverTransport = LanTransport(deviceName, myDeviceId, LanTransport.Mode.SERVER, listenPort = 44777)
        serverTransport.connect(object : TransportListener {
            override fun onConnected(peer: String) {
                kotlinx.coroutines.MainScope().launch {
                    connecting = false
                    onConnected(serverTransport, peer)
                }
            }
            override fun onDisconnected(reason: String) {
                kotlinx.coroutines.MainScope().launch { connecting = false; error = reason }
            }
            override fun onTextMessage(from: String, senderId: String, text: String) {}
            override fun onFileReceived(meta: FileMeta, data: ByteArray) {}
            override fun onFileProgress(meta: FileMeta, sent: Long, total: Long) {}
            override fun onError(message: String) {
                kotlinx.coroutines.MainScope().launch { connecting = false; error = message }
            }
        })
    }

    // 输入配对码去匹配 —— 输入方 = 客户端
    fun matchWithCode() {
        val code = inputPairCode.trim()
        if (code.length != 6) {
            error = "请输入 6 位配对码"
            return
        }
        error = null
        pairing = true
        scope.launch {
            try {
                val dev = discovery.pairMatch(code, 6000)
                if (dev != null) {
                    pairResult = "匹配到 ${dev.name} (${dev.ip})，正在连接..."
                    // 作为客户端连接生成方
                    connecting = true
                    val t = LanTransport(deviceName, myDeviceId, LanTransport.Mode.CLIENT, serverHost = dev.ip, serverPort = dev.port)
                    t.connect(object : TransportListener {
                        override fun onConnected(peer: String) {
                            kotlinx.coroutines.MainScope().launch {
                                connecting = false
                                pairing = false
                                onConnected(t, peer)
                            }
                        }
                        override fun onDisconnected(reason: String) {
                            kotlinx.coroutines.MainScope().launch { connecting = false; pairing = false; error = reason }
                        }
                        override fun onTextMessage(from: String, senderId: String, text: String) {}
                        override fun onFileReceived(meta: FileMeta, data: ByteArray) {}
                        override fun onFileProgress(meta: FileMeta, sent: Long, total: Long) {}
                        override fun onError(message: String) {
                            kotlinx.coroutines.MainScope().launch { connecting = false; pairing = false; error = message }
                        }
                    })
                } else {
                    pairResult = "未找到配对设备（确认对方已生成配对码）"
                }
            } catch (e: Exception) {
                pairResult = "配对失败: ${e.message}"
            } finally {
                pairing = false
            }
        }
    }

    // 扫描局域网设备
    fun scanDevices() {
        error = null
        scanning = true
        discovered = emptyList()
        scope.launch {
            try {
                val devices = discovery.scan(2500)
                discovered = devices
                if (devices.isEmpty()) {
                    error = "未发现设备（确保对方已打开 App 并处于服务端模式）"
                }
            } catch (e: Exception) {
                error = "扫描失败: ${e.message}"
            } finally {
                scanning = false
            }
        }
    }

    fun connect() {
        error = null
        connecting = true
        scope.launch {
            try {
                if (tab == 0) {
                    // 局域网
                    val mode = if (lanMode == 0) LanTransport.Mode.SERVER else LanTransport.Mode.CLIENT
                    val t = LanTransport(
                        deviceName = deviceName,
                        deviceId = myDeviceId,
                        mode = mode,
                        listenPort = 44777,
                        serverHost = if (mode == LanTransport.Mode.CLIENT) clientIp else "",
                        serverPort = 44777
                    )
                    // 服务端：复用同一 discovery 实例启动 responder（内部有防重入）
                    if (mode == LanTransport.Mode.SERVER) {
                        t.attachDiscovery(discovery)
                        discovery.startResponder()
                    }
                    var connName = ""
                    t.connect(object : TransportListener {
                        override fun onConnected(peer: String) {
                            connName = peer
                            // 主线程通知
                            kotlinx.coroutines.MainScope().launch {
                                connecting = false
                                onConnected(t, peer)
                            }
                        }
                        override fun onDisconnected(reason: String) {
                            kotlinx.coroutines.MainScope().launch { connecting = false; error = reason }
                        }
                        override fun onTextMessage(from: String, senderId: String, text: String) {}
                        override fun onFileReceived(meta: FileMeta, data: ByteArray) {}
                        override fun onFileProgress(meta: FileMeta, sent: Long, total: Long) {}
                        override fun onError(message: String) {
                            kotlinx.coroutines.MainScope().launch { connecting = false; error = message }
                        }
                    })
                } else {
                    // 云中继
                    if (relayUrl.isBlank() || relayPass.isBlank()) {
                        error = "请先在设置中配置中继服务器地址和口令"
                        connecting = false
                        return@launch
                    }
                    val t = RelayTransport(deviceName, myDeviceId, relayUrl, relayHttp.ifBlank { relayUrl.replace("ws", "http") }, relayRoom, relayPass)
                    t.connect(object : TransportListener {
                        override fun onConnected(peer: String) {
                            kotlinx.coroutines.MainScope().launch {
                                connecting = false
                                onConnected(t, peer)
                            }
                        }
                        override fun onDisconnected(reason: String) {
                            kotlinx.coroutines.MainScope().launch { connecting = false; error = reason }
                        }
                        override fun onTextMessage(from: String, senderId: String, text: String) {}
                        override fun onFileReceived(meta: FileMeta, data: ByteArray) {}
                        override fun onFileProgress(meta: FileMeta, sent: Long, total: Long) {}
                        override fun onError(message: String) {
                            kotlinx.coroutines.MainScope().launch { connecting = false; error = message }
                        }
                    })
                }
            } catch (e: Exception) {
                connecting = false
                error = e.message
            }
        }
    }

    Column(Modifier.fillMaxSize().background(AppGradients.bg)) {
        // 统一顶部栏（子页时返回列表）
        AppTopBar(
            title = "发现",
            onBack = if (featureList) onBack else ({ featureList = true; tab = 0 })
        )

        if (featureList) {
            // ===== 功能列表页（各功能入口，点击进入对应子页） =====
            // 每项：[图标, 名称, 描述, action(0=局域网 1=云中继 2=蓝牙 3=可视化 4=二维码 5=扫一扫)]
            val features = listOf(
                listOf("", "局域网直连", "同一 Wi-Fi · 配对码/扫描", "0"),
                listOf("", "云中继", "公网跨网络 · 在线设备", "1"),
                listOf("", "蓝牙直连", "近距离 · 无需 Wi-Fi", "2"),
                listOf("", "中继网可视化", "实时拓扑 / 在线用户 / 安装量", "3"),
                listOf("", "我的二维码", "扫码互加好友", "4"),
                listOf("", "扫一扫", "扫描二维码添加好友", "5")
            )
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(top = 8.dp)) {
                features.forEach { f ->
                    val icon = f[0]; val name = f[1]; val desc = f[2]; val action = f[3].toInt()
                    Surface(
                        color = Color.Transparent,
                        modifier = Modifier.fillMaxWidth().clickable {
                            when (action) {
                                0, 1, 2 -> { featureList = false; tab = action }
                                3 -> onOpenNetMap()
                                4 -> onOpenQrCode()
                                5 -> onScanQr()
                            }
                        }
                    ) {
                        Row(Modifier.padding(horizontal = 20.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text(icon, fontSize = 22.sp)
                            Spacer(Modifier.width(14.dp))
                            Column(Modifier.weight(1f)) {
                                Text(name, color = AppColors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Medium)
                                Text(desc, color = AppColors.textTertiary, fontSize = 11.sp)
                            }
                            Icon(Icons.Default.ChevronRight, contentDescription = null, tint = AppColors.textTertiary, modifier = Modifier.size(18.dp))
                        }
                        HorizontalDivider(color = AppColors.outline, modifier = Modifier.padding(start = 56.dp))
                    }
                }
            }
        } else {
            // ===== 子页：连接详情 + Segmented Control =====
            // Tab 切换（2026 Segmented Control）
        SegmentedControl(
            options = listOf("局域网", "云中继", "蓝牙"),
            selectedIndex = tab,
            onSelect = { tab = it },
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = AppSpacing.lg, end = AppSpacing.lg, top = AppSpacing.sm, bottom = AppSpacing.sm)
        )
        // 中继网实时可视化入口
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 4.dp)
                .clip(RoundedCornerShape(14.dp))
                .background(
                    Brush.linearGradient(listOf(AppColors.surfaceHigh, AppColors.surfaceHigh))
                )
                .border(1.dp, AppColors.outlineStrong, RoundedCornerShape(14.dp))
                .clickable {
                    // 打开中继网可视化页面
                    onOpenNetMap()
                }
                .padding(horizontal = 14.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(Icons.Default.Hub, contentDescription = null, tint = AppColors.textSecondary, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) {
                Text("中继网实时可视化", color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                Text("实时查看节点拓扑 / 在线用户 / 安装量", color = AppColors.textTertiary, fontSize = 11.sp)
            }
            Text("查看 >", color = AppColors.primary, fontSize = 12.sp)
        }

        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
        ) {
            if (tab == 0) {
                // ===== ① 配对码快捷连接 =====
                SectionCard("配对连接", "两台设备在同一 Wi-Fi 时最快") {
                    if (pairMode == 0) {
                        Row {
                            Button(
                                onClick = {
                                    pairMode = 1
                                    startPairListener()
                                },
                                modifier = Modifier.weight(1f).height(46.dp),
                                shape = RoundedCornerShape(12.dp),
                                colors = ButtonDefaults.buttonColors(containerColor = AppColors.success)
                            ) { Text("生成配对码", fontSize = 13.sp) }
                            Spacer(Modifier.width(8.dp))
                            Button(
                                onClick = { pairMode = 2 },
                                modifier = Modifier.weight(1f).height(46.dp),
                                shape = RoundedCornerShape(12.dp),
                                colors = ButtonDefaults.buttonColors(containerColor = AppColors.info)
                            ) { Text("⌨️ 输入配对码", fontSize = 13.sp) }
                        }
                    }

                    if (pairMode == 1) {
                        Text("请对方输入以下配对码：", color = AppColors.textSecondary, fontSize = 13.sp)
                        Spacer(Modifier.height(8.dp))
                        Surface(
                            shape = RoundedCornerShape(14.dp),
                            color = AppColors.bg,
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(
                                myPairCode,
                                fontSize = 44.sp,
                                fontWeight = FontWeight.Bold,
                                color = AppColors.success,
                                letterSpacing = 8.sp,
                                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                                modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp)
                            )
                        }
                        Spacer(Modifier.height(8.dp))
                        Text("等待对方输入配对码自动连接...", color = AppColors.success, fontSize = 12.sp)
                        Spacer(Modifier.height(4.dp))
                        TextButton(onClick = {
                            pairMode = 0
                            myPairCode = ""
                            discovery.stopResponder()
                        }) { Text("取消", color = AppColors.textSecondary, fontSize = 13.sp) }
                    }

                    if (pairMode == 2) {
                        OutlinedTextField(
                            value = inputPairCode,
                            onValueChange = { inputPairCode = it.filter { c -> c.isDigit() }.take(6) },
                            label = { Text("输入对方配对码", color = AppColors.textTertiary) },
                            modifier = Modifier.fillMaxWidth(),
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.Number, imeAction = ImeAction.Done),
                            keyboardActions = KeyboardActions(onDone = { matchWithCode() }),
                            colors = textFieldColors()
                        )
                        Spacer(Modifier.height(8.dp))
                        Button(
                            onClick = { matchWithCode() },
                            enabled = !pairing,
                            modifier = Modifier.fillMaxWidth().height(46.dp),
                            shape = RoundedCornerShape(12.dp),
                            colors = ButtonDefaults.buttonColors(containerColor = AppColors.info)
                        ) {
                            if (pairing) {
                                CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = Color.White)
                                Spacer(Modifier.width(8.dp))
                            }
                            Text("自动匹配并连接", fontSize = 14.sp)
                        }
                        Spacer(Modifier.height(4.dp))
                        TextButton(onClick = { pairMode = 0 }) { Text("返回", color = AppColors.textSecondary, fontSize = 13.sp) }
                    }

                    pairResult?.let {
                        Spacer(Modifier.height(8.dp))
                        Text(it, color = if (it.startsWith("配对成功") || it.startsWith("匹配到")) AppColors.success else AppColors.error, fontSize = 13.sp)
                    }
                }

                // ===== ② 附近设备 =====
                SectionCard("附近设备", "扫描同一局域网，点击即可连接") {
                    Button(
                        onClick = { scanDevices() },
                        enabled = !scanning && !connecting,
                        modifier = Modifier.fillMaxWidth().height(44.dp),
                        shape = RoundedCornerShape(12.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = AppColors.surfaceAlt)
                    ) {
                        if (scanning) {
                            CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = Color.White)
                            Spacer(Modifier.width(8.dp))
                            Text("扫描中...", fontSize = 14.sp)
                        } else {
                            Text("扫描局域网设备", fontSize = 14.sp)
                        }
                    }
                    if (discovered.isNotEmpty()) {
                        Spacer(Modifier.height(10.dp))
                        Text("发现 ${discovered.size} 台设备", color = AppColors.textSecondary, fontSize = 12.sp)
                        discovered.forEach { dev ->
                            val isSelf = dev.ip == localIp || dev.ip == "127.0.0.1"
                            Surface(
                                shape = RoundedCornerShape(12.dp),
                                color = if (isSelf) AppColors.successDim else AppColors.surfaceHigh,
                                border = if (isSelf) null else androidx.compose.foundation.BorderStroke(1.dp, AppColors.outline),
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(top = 6.dp)
                                    .clickable(enabled = !isSelf && !connecting) {
                                        clientIp = dev.ip
                                        lanMode = 1
                                        error = null
                                        connecting = true
                                        scope.launch {
                                            val t = LanTransport(deviceName, myDeviceId, LanTransport.Mode.CLIENT, serverHost = dev.ip, serverPort = dev.port)
                                            t.connect(object : TransportListener {
                                                override fun onConnected(peer: String) {
                                                    kotlinx.coroutines.MainScope().launch {
                                                        connecting = false
                                                        onConnected(t, peer)
                                                    }
                                                }
                                                override fun onDisconnected(reason: String) {
                                                    kotlinx.coroutines.MainScope().launch { connecting = false; error = reason }
                                                }
                                                override fun onTextMessage(from: String, senderId: String, text: String) {}
                                                override fun onFileReceived(meta: FileMeta, data: ByteArray) {}
                                                override fun onFileProgress(meta: FileMeta, sent: Long, total: Long) {}
                                                override fun onError(message: String) {
                                                    kotlinx.coroutines.MainScope().launch { connecting = false; error = "连接失败: $message" }
                                                }
                                            })
                                        }
                                    }
                            ) {
                                Row(
                                    Modifier.padding(12.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Text(dev.name, color = Color.White, fontSize = 14.sp, modifier = Modifier.weight(1f))
                                    if (isSelf) {
                                        Surface(
                                            shape = RoundedCornerShape(6.dp),
                                            color = AppColors.success
                                        ) {
                                            Text(
                                                "本机",
                                                color = AppColors.successDim,
                                                fontSize = 10.sp,
                                                fontWeight = FontWeight.Bold,
                                                modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                                            )
                                        }
                                        Spacer(Modifier.width(8.dp))
                                    }
                                    Text(dev.ip, color = AppColors.primary, fontSize = 13.sp)
                                    Icon(Icons.Default.ChevronRight, contentDescription = null, tint = AppColors.textTertiary)
                                }
                            }
                        }
                    }
                }

                // ===== ③ 手动连接 =====
                SectionCard("手动连接", "服务端等待连接 / 客户端指定 IP 发起") {
                    Row {
                        ModeButton("服务端", lanMode == 0, Modifier.weight(1f)) { lanMode = 0 }
                        Spacer(Modifier.width(8.dp))
                        ModeButton("客户端", lanMode == 1, Modifier.weight(1f)) { lanMode = 1 }
                    }
                    if (lanMode == 1) {
                        Spacer(Modifier.height(12.dp))
                        OutlinedTextField(
                            value = clientIp,
                            onValueChange = { clientIp = it },
                            label = { Text("对端 IP（如 192.168.1.100）", color = AppColors.textTertiary) },
                            modifier = Modifier.fillMaxWidth(),
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                            colors = textFieldColors()
                        )
                    }
                    Spacer(Modifier.height(12.dp))
                    Button(
                        onClick = { connect() },
                        enabled = !connecting,
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(50.dp),
                        shape = RoundedCornerShape(14.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = AppColors.primary)
                    ) {
                        if (connecting) {
                            CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp, color = Color.White)
                            Spacer(Modifier.width(10.dp))
                            Text("连接中...")
                        } else {
                            Text("开始连接", fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                        }
                    }
                }

                // ===== ④ 本机信息 =====
                SectionCard("ℹ️ 本机信息", "") {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("本机局域网 IP: ", color = AppColors.textSecondary, fontSize = 14.sp)
                        Text(localIp, color = AppColors.success, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                        Spacer(Modifier.width(8.dp))
                        Surface(
                            shape = RoundedCornerShape(6.dp),
                            color = AppColors.success
                        ) {
                            Text(
                                "本机",
                                color = AppColors.successDim,
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold,
                                modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                            )
                        }
                    }
                    Spacer(Modifier.height(4.dp))
                    Text("端口: 44777 · 设备名: $deviceName", color = AppColors.textSecondary, fontSize = 12.sp)
                    Text("两台设备需在同一 Wi-Fi/局域网", color = AppColors.textTertiary, fontSize = 12.sp)
                }
            } else if (tab == 1) {
                // ===== 云中继（自动发现 + 手动配置） =====
                var relayNodes by remember { mutableStateOf<List<top.vios.chat.net.RelayDiscovery.RelayNode>>(emptyList()) }
                var relayScanning by remember { mutableStateOf(true) }
                val relayDiscovery = remember { top.vios.chat.net.RelayDiscovery(context) }

                // 进入云中继 tab 自动监听局域网中继广播
                LaunchedEffect(Unit) {
                    relayScanning = true
                    relayDiscovery.startListen { _ ->
                        relayNodes = relayDiscovery.currentNodes()
                    }
                    // 3 秒后仍无发现则停止扫描动画（继续监听）
                    kotlinx.coroutines.delay(3000)
                    relayScanning = false
                }
                DisposableEffect(Unit) { onDispose { relayDiscovery.stopListen() } }

                // 自动连接发现的中继
                fun connectToRelay(node: top.vios.chat.net.RelayDiscovery.RelayNode) {
                    connecting = true
                    error = null
                    val room = if (relayRoom.isBlank()) "everett" else relayRoom
                    val pass = if (relayPass.isBlank()) "everett123" else relayPass
                    scope.launch {
                        try {
                            val t = RelayTransport(deviceName, myDeviceId, node.wsUrl, node.httpUrl, room, pass)
                            t.connect(object : TransportListener {
                                override fun onConnected(peer: String) {
                                    kotlinx.coroutines.MainScope().launch {
                                        connecting = false
                                        onConnected(t, peer)
                                    }
                                }
                                override fun onDisconnected(reason: String) {
                                    kotlinx.coroutines.MainScope().launch { connecting = false; error = reason }
                                }
                                override fun onTextMessage(from: String, senderId: String, text: String) {}
                                override fun onFileReceived(meta: FileMeta, data: ByteArray) {}
                                override fun onFileProgress(meta: FileMeta, sent: Long, total: Long) {}
                                override fun onError(message: String) {
                                    kotlinx.coroutines.MainScope().launch { connecting = false; error = "中继错误: $message" }
                                }
                            })
                        } catch (e: Exception) {
                            connecting = false
                            error = e.message
                        }
                    }
                }

                SectionCard("云中继", "自动发现局域网中继，无需手动填地址") {
                    // 自动发现状态 + 节点列表
                    Text(
                        if (relayScanning) "正在扫描局域网中继..." else "扫描完成",
                        color = if (relayScanning) AppColors.info else AppColors.textSecondary,
                        fontSize = 12.sp
                    )
                    if (relayNodes.isEmpty()) {
                        Spacer(Modifier.height(6.dp))
                        Text(
                            "未发现中继设备。请在其中一台设备打开「设置 → 本机作为中继」，这里会自动出现并一键连接。",
                            color = AppColors.textTertiary, fontSize = 12.sp, lineHeight = 17.sp
                        )
                    } else {
                        Spacer(Modifier.height(8.dp))
                        Text("发现 ${relayNodes.size} 个中继：", color = AppColors.textSecondary, fontSize = 12.sp)
                        relayNodes.forEach { node ->
                            Surface(
                                shape = RoundedCornerShape(12.dp),
                                color = AppColors.surfaceHigh,
                                border = androidx.compose.foundation.BorderStroke(1.dp, AppColors.outline),
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(top = 6.dp)
                                    .clickable(enabled = !connecting) { connectToRelay(node) }
                            ) {
                                Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                                    Icon(Icons.Default.SatelliteAlt, contentDescription = null, tint = AppColors.textSecondary, modifier = Modifier.size(16.dp))
                                    Spacer(Modifier.width(10.dp))
                                    Column(Modifier.weight(1f)) {
                                        Text(node.name, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                                        Text(node.ip + ":" + node.port, color = AppColors.textTertiary, fontSize = 11.sp)
                                    }
                                    if (connecting) {
                                        CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = AppColors.primary)
                                    } else {
                                        Text("连接", color = AppColors.primary, fontSize = 13.sp)
                                    }
                                }
                            }
                        }
                    }

                    // ===== 中继网在线设备（用户间通信优化：点谁连谁） =====
                    var relayUsers by remember { mutableStateOf<List<org.json.JSONObject>>(emptyList()) }
                    var usersLoaded by remember { mutableStateOf(false) }
                    LaunchedEffect(relayNodes.size) {
                        // 从中继节点获取在线用户
                        val base = if (relayHttp.isNotBlank()) relayHttp.trimEnd('/')
                            else {
                                val u = relayUrl.trim().removeSuffix("/ws").removeSuffix("/")
                                if (u.startsWith("ws://")) "http://" + u.removePrefix("ws://") else u
                            }
                        // 优先用自动发现节点的 http 地址
                        val nodeHttp = relayNodes.firstOrNull()?.httpUrl?.trimEnd('/')
                        val target = nodeHttp ?: base
                        if (target.isNotBlank()) {
                            kotlinx.coroutines.MainScope().launch {
                                try {
                                    val conn = java.net.URL("$target/users").openConnection() as java.net.HttpURLConnection
                                    conn.connectTimeout = 5000
                                    conn.readTimeout = 5000
                                    val resp = conn.inputStream.bufferedReader().use { it.readText() }
                                    val arr = org.json.JSONObject(resp).optJSONArray("users") ?: org.json.JSONArray()
                                    val list = ArrayList<org.json.JSONObject>()
                                    for (i in 0 until arr.length()) {
                                        val u = arr.getJSONObject(i)
                                        if (u.optString("deviceId", "") != myDeviceId) list.add(u)
                                    }
                                    relayUsers = list
                                } catch (_: Exception) { relayUsers = emptyList() }
                                usersLoaded = true
                            }
                        } else {
                            usersLoaded = true
                        }
                    }
                    Spacer(Modifier.height(10.dp))
                    HorizontalDivider(color = AppColors.outline)
                    Spacer(Modifier.height(8.dp))
                    Text("中继网在线设备", color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Bold)
                    Text(
                        if (!usersLoaded) "加载中..." else if (relayUsers.isEmpty()) "暂无其他在线设备（对方需连接同一中继网）" else "点击设备名即可连接对方",
                        color = AppColors.textTertiary, fontSize = 11.sp
                    )
                    relayUsers.forEach { u ->
                        val uname = u.optString("name", "设备")
                        val uroom = u.optString("room", "default")
                        Surface(
                            shape = RoundedCornerShape(12.dp),
                            color = AppColors.surfaceHigh,
                            border = androidx.compose.foundation.BorderStroke(1.dp, AppColors.outline),
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 6.dp)
                                .clickable(enabled = !connecting) {
                                    // 加入对方所在房间 → 建立联系
                                    connecting = true
                                    error = null
                                    val pass = if (relayPass.isBlank()) "everett123" else relayPass
                                    val node = relayNodes.firstOrNull()
                                    val wsUrl = node?.wsUrl ?: relayUrl
                                    val httpUrl = node?.httpUrl ?: relayHttp.ifBlank { relayUrl }
                                    scope.launch {
                                        try {
                                            val t = RelayTransport(deviceName, myDeviceId, wsUrl, httpUrl, uroom, pass)
                                            t.connect(object : TransportListener {
                                                override fun onConnected(peer: String) {
                                                    kotlinx.coroutines.MainScope().launch {
                                                        connecting = false
                                                        onConnected(t, peer)
                                                    }
                                                }
                                                override fun onDisconnected(reason: String) {
                                                    kotlinx.coroutines.MainScope().launch { connecting = false; error = reason }
                                                }
                                                override fun onTextMessage(from: String, senderId: String, text: String) {}
                                                override fun onFileReceived(meta: FileMeta, data: ByteArray) {}
                                                override fun onFileProgress(meta: FileMeta, sent: Long, total: Long) {}
                                                override fun onError(message: String) {
                                                    kotlinx.coroutines.MainScope().launch { connecting = false; error = "连接失败: $message" }
                                                }
                                            })
                                        } catch (e: Exception) {
                                            connecting = false
                                            error = e.message
                                        }
                                    }
                                }
                        ) {
                            Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                                Box(Modifier.size(10.dp).background(AppColors.success, CircleShape))
                                Spacer(Modifier.width(10.dp))
                                Column(Modifier.weight(1f)) {
                                    Text(uname, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                                    Text("房间: $uroom", color = AppColors.textTertiary, fontSize = 11.sp)
                                }
                                if (connecting) {
                                    CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = AppColors.primary)
                                } else {
                                    Text("连接", color = AppColors.primary, fontSize = 13.sp)
                                }
                            }
                        }
                    }

                    // 手动配置的连接
                    if (relayUrl.isNotBlank()) {
                        Spacer(Modifier.height(10.dp))
                        HorizontalDivider(color = AppColors.outline)
                        Spacer(Modifier.height(6.dp))
                        Text("手动配置: $relayUrl", color = AppColors.textSecondary, fontSize = 12.sp)
                        Text("房间: ${relayRoom.ifBlank { "default" }}", color = AppColors.textSecondary, fontSize = 12.sp)
                        Spacer(Modifier.height(8.dp))
                        Button(
                            onClick = { connect() },
                            enabled = !connecting,
                            modifier = Modifier.fillMaxWidth().height(46.dp),
                            shape = RoundedCornerShape(14.dp),
                            colors = ButtonDefaults.buttonColors(containerColor = AppColors.primary)
                        ) {
                            if (connecting) {
                                CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp, color = Color.White)
                                Spacer(Modifier.width(10.dp))
                                Text("连接中...")
                            } else {
                                Text("连接已配置中继", fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                            }
                        }
                    }
                }
            } else if (tab == 2) {
                // ===== 蓝牙直连 =====
                var btPermGranted by remember { mutableStateOf(false) }
                var btMode by remember { mutableStateOf(0) }  // 0=服务端 1=客户端
                var btDevices by remember { mutableStateOf<List<android.bluetooth.BluetoothDevice>>(emptyList()) }
                var btServerActive by remember { mutableStateOf(false) }

                // 蓝牙权限请求
                val btPermLauncher = rememberLauncherForActivityResult(
                    ActivityResultContracts.RequestMultiplePermissions()
                ) { granted ->
                    btPermGranted = granted.values.all { it }
                }

                fun checkBtPerm(): Boolean {
                    if (android.os.Build.VERSION.SDK_INT < 31) return true
                    return androidx.core.content.ContextCompat.checkSelfPermission(
                        context, android.Manifest.permission.BLUETOOTH_CONNECT
                    ) == android.content.pm.PackageManager.PERMISSION_GRANTED
                }
                LaunchedEffect(Unit) { btPermGranted = checkBtPerm() }

                if (!btPermGranted) {
                    SectionCard("蓝牙直连", "需要蓝牙权限才能使用") {
                        Text("请授予蓝牙权限以使用蓝牙直连通信", color = AppColors.textSecondary, fontSize = 13.sp)
                        Spacer(Modifier.height(12.dp))
                        Button(
                            onClick = {
                                if (android.os.Build.VERSION.SDK_INT >= 31) {
                                    btPermLauncher.launch(arrayOf(
                                        android.Manifest.permission.BLUETOOTH_CONNECT,
                                        android.Manifest.permission.BLUETOOTH_SCAN
                                    ))
                                } else {
                                    btPermLauncher.launch(arrayOf(android.Manifest.permission.BLUETOOTH))
                                }
                            },
                            modifier = Modifier.fillMaxWidth().height(44.dp),
                            shape = RoundedCornerShape(12.dp),
                            colors = ButtonDefaults.buttonColors(containerColor = AppColors.primary)
                        ) { Text("授予蓝牙权限", fontSize = 14.sp) }
                    }
                } else {
                    SectionCard("蓝牙直连", "无需 Wi-Fi 的近距离通信，已配对设备点击即连") {
                        Row {
                            ModeButton("服务端", btMode == 0, Modifier.weight(1f)) { btMode = 0 }
                            Spacer(Modifier.width(8.dp))
                            ModeButton("客户端", btMode == 1, Modifier.weight(1f)) { btMode = 1 }
                        }
                        Spacer(Modifier.height(12.dp))

                        if (btMode == 0) {
                            // 服务端模式：开启蓝牙等待连接
                            if (!btServerActive) {
                                Button(
                                    onClick = {
                                        btServerActive = true
                                        val bt = top.vios.chat.net.BtTransport(context, deviceName, myDeviceId, top.vios.chat.net.BtTransport.Mode.SERVER)
                                        connecting = true
                                        bt.connect(object : TransportListener {
                                            override fun onConnected(peer: String) {
                                                kotlinx.coroutines.MainScope().launch {
                                                    connecting = false
                                                    onConnected(bt, peer)
                                                }
                                            }
                                            override fun onDisconnected(reason: String) {
                                                kotlinx.coroutines.MainScope().launch { connecting = false; error = reason }
                                            }
                                            override fun onTextMessage(from: String, senderId: String, text: String) {}
                                            override fun onFileReceived(meta: FileMeta, data: ByteArray) {}
                                            override fun onFileProgress(meta: FileMeta, sent: Long, total: Long) {}
                                            override fun onError(message: String) {
                                                kotlinx.coroutines.MainScope().launch { connecting = false; error = "蓝牙错误: $message" }
                                            }
                                        })
                                    },
                                    modifier = Modifier.fillMaxWidth().height(50.dp),
                                    shape = RoundedCornerShape(14.dp),
                                    colors = ButtonDefaults.buttonColors(containerColor = AppColors.success)
                                ) { Text("开启蓝牙服务", fontSize = 15.sp) }
                            } else {
                                Text("等待蓝牙设备连接...", color = AppColors.success, fontSize = 14.sp)
                                Spacer(Modifier.height(8.dp))
                                Text("设备名: $deviceName · 请对方在客户端选择", color = AppColors.textSecondary, fontSize = 12.sp)
                                Spacer(Modifier.height(8.dp))
                                TextButton(onClick = {
                                    btServerActive = false
                                    connecting = false
                                }) { Text("取消", color = AppColors.textSecondary, fontSize = 13.sp) }
                            }
                        } else {
                            // 客户端模式：列出已配对设备
                            LaunchedEffect(btPermGranted) {
                                if (btPermGranted) {
                                    try {
                                        val adapter = android.bluetooth.BluetoothAdapter.getDefaultAdapter()
                                        btDevices = adapter?.bondedDevices?.toList() ?: emptyList()
                                    } catch (_: Exception) { btDevices = emptyList() }
                                }
                            }
                            if (btDevices.isEmpty()) {
                                Text("未找到已配对的蓝牙设备", color = AppColors.textSecondary, fontSize = 13.sp)
                                Spacer(Modifier.height(6.dp))
                                Text("请先在系统设置 > 蓝牙中配对设备", color = AppColors.textTertiary, fontSize = 12.sp)

                            } else {
                                Text("已配对设备 (${btDevices.size})", color = AppColors.textSecondary, fontSize = 12.sp)
                                btDevices.forEach { dev ->
                                    val name = dev.name ?: dev.address
                                    Surface(
                                        shape = RoundedCornerShape(12.dp),
                                        color = AppColors.surfaceHigh,
                                        border = androidx.compose.foundation.BorderStroke(1.dp, AppColors.outline),
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .padding(top = 6.dp)
                                            .clickable(enabled = !connecting) {
                                                connecting = true
                                                val bt = top.vios.chat.net.BtTransport(context, deviceName, myDeviceId, top.vios.chat.net.BtTransport.Mode.CLIENT, dev)
                                                bt.connect(object : TransportListener {
                                                    override fun onConnected(peer: String) {
                                                        kotlinx.coroutines.MainScope().launch {
                                                            connecting = false
                                                            onConnected(bt, peer)
                                                        }
                                                    }
                                                    override fun onDisconnected(reason: String) {
                                                        kotlinx.coroutines.MainScope().launch { connecting = false; error = reason }
                                                    }
                                                    override fun onTextMessage(from: String, senderId: String, text: String) {}
                                                    override fun onFileReceived(meta: FileMeta, data: ByteArray) {}
                                                    override fun onFileProgress(meta: FileMeta, sent: Long, total: Long) {}
                                                    override fun onError(message: String) {
                                                        kotlinx.coroutines.MainScope().launch { connecting = false; error = "蓝牙错误: $message" }
                                                    }
                                                })
                                            }
                                    ) {
                                        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                                            Text("$name", color = Color.White, fontSize = 14.sp, modifier = Modifier.weight(1f))
                                            Text(dev.address, color = AppColors.textTertiary, fontSize = 11.sp)
                                            Icon(Icons.Default.ChevronRight, contentDescription = null, tint = AppColors.textTertiary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    }
                    }   // 闭 featureList else（子页内容）

                    if (error != null) {
                        Spacer(Modifier.height(4.dp))
                        Text(error!!, color = AppColors.error, fontSize = 13.sp)
                    }
                    Spacer(Modifier.height(16.dp))
            }
        }
}
}

@Composable
fun SectionCard(
    title: String,
    subtitle: String = "",
    content: @Composable () -> Unit
) {
    Surface(
        shape = RoundedCornerShape(16.dp),
        color = AppColors.surface,
        border = androidx.compose.foundation.BorderStroke(1.dp, AppColors.outline),
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = 12.dp)
    ) {
        Column(Modifier.padding(16.dp)) {
            Text(title, color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.Bold)
            if (subtitle.isNotEmpty()) {
                Spacer(Modifier.height(3.dp))
                Text(subtitle, color = AppColors.textTertiary, fontSize = 11.sp)
            }
            Spacer(Modifier.height(12.dp))
            content()
        }
    }
}

/** 设置行（微信风格：图标 + 标题 + 副标题 + 右箭头） */
@Composable
fun SettingRow(
    icon: String,
    title: String,
    subtitle: String = "",
    onClick: (() -> Unit)? = null,
    valueColor: Color = AppColors.textTertiary
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = onClick != null) { onClick?.invoke() }
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(icon, fontSize = 18.sp)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(title, color = Color.White, fontSize = 14.sp)
            if (subtitle.isNotEmpty()) {
                Text(subtitle, color = valueColor, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        Icon(Icons.Default.ChevronRight, contentDescription = null, tint = AppColors.textTertiary, modifier = Modifier.size(18.dp))
    }
}

/** 2026 Segmented Control（分段控制器：胶囊容器 + 选中段高亮 + 滑动指示） */
@Composable
fun SegmentedControl(
    options: List<String>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier
) {
    Surface(
        shape = RoundedCornerShape(AppRadius.medium),
        color = AppColors.surfaceHigh,
        modifier = modifier.height(40.dp)
    ) {
        Row(Modifier.padding(3.dp), verticalAlignment = Alignment.CenterVertically) {
            options.forEachIndexed { idx, label ->
                val selected = idx == selectedIndex
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxHeight()
                        .clip(RoundedCornerShape(AppRadius.small))
                        .background(if (selected) AppColors.surfaceAlt else Color.Transparent)
                        .then(
                            if (selected) Modifier.border(
                                1.dp, AppColors.outlineStrong, RoundedCornerShape(AppRadius.small)
                            ) else Modifier
                        )
                        .clickable { onSelect(idx) },
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        label,
                        color = if (selected) AppColors.textPrimary else AppColors.textTertiary,
                        fontSize = 13.sp,
                        fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal
                    )
                }
            }
        }
    }
}

@Composable
fun TabButton(text: String, selected: Boolean, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(10.dp))
            .background(
                if (selected) AppGradients.primary
                else Brush.linearGradient(listOf(AppColors.surfaceHigh, AppColors.surfaceHigh))
            )
            .clickable(onClick = onClick)
    ) {
        Text(
            text,
            modifier = Modifier.padding(horizontal = 18.dp, vertical = 10.dp),
            color = if (selected) Color.White else AppColors.textSecondary,
            fontSize = 14.sp,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal
        )
    }
}

@Composable
fun ModeButton(text: String, selected: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(10.dp))
            .background(
                if (selected) AppGradients.primary
                else Brush.linearGradient(listOf(AppColors.surface, AppColors.surface))
            )
            .clickable(onClick = onClick)
    ) {
        Text(
            text,
            modifier = Modifier.padding(12.dp),
            color = if (selected) Color.White else AppColors.textSecondary,
            fontSize = 12.sp
        )
    }
}

@Composable
fun RingtoneRow(label: String, icon: String, onClick: () -> Unit, onPreview: () -> Unit) {
    Surface(
        shape = RoundedCornerShape(10.dp),
        color = AppColors.surfaceAlt,
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 6.dp)
    ) {
        Row(
            Modifier.padding(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(icon, fontSize = 18.sp)
            Spacer(Modifier.width(10.dp))
            Text(label, color = Color.White, fontSize = 14.sp, modifier = Modifier.weight(1f))
            // 预览
            Text(
                "▶ 试听",
                color = AppColors.success,
                fontSize = 12.sp,
                modifier = Modifier
                    .clickable { onPreview() }
                    .padding(horizontal = 8.dp, vertical = 4.dp)
            )
            // 选择
            Text(
                "更换",
                color = AppColors.primary,
                fontSize = 12.sp,
                modifier = Modifier
                    .clickable { onClick() }
                    .padding(horizontal = 8.dp, vertical = 4.dp)
            )
        }
    }
}

@Composable
fun textFieldColors() = OutlinedTextFieldDefaults.colors(
    focusedBorderColor = AppColors.textTertiary,
    unfocusedBorderColor = AppColors.surfaceAlt,
    focusedContainerColor = AppColors.surfaceHigh,
    unfocusedContainerColor = AppColors.surfaceHigh,
    cursorColor = AppColors.primary,
    focusedTextColor = Color.White,
    unfocusedTextColor = Color.White
)

fun getLocalIpAddress(): String {
    return try {
        NetworkInterface.getNetworkInterfaces().toList()
            .filter { it.isUp && !it.isLoopback }
            .flatMap { it.inetAddresses.toList() }
            .filterIsInstance<Inet4Address>()
            .firstOrNull { !it.isLoopbackAddress && it.hostAddress?.startsWith("192.168") == true }
            ?.hostAddress
            ?: try {
                NetworkInterface.getNetworkInterfaces().toList()
                    .filter { it.isUp && !it.isLoopback }
                    .flatMap { it.inetAddresses.toList() }
                    .filterIsInstance<Inet4Address>()
                    .firstOrNull { !it.isLoopbackAddress }
                    ?.hostAddress ?: "未知"
            } catch (_: Exception) { "未知" }
    } catch (_: Exception) { "未知" }
}

// ================= 设置页 =================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    deviceName: String,
    onNameChanged: (String) -> Unit,
    onRerollName: () -> String,
    relayUrl: String, relayHttp: String, relayRoom: String, relayPass: String,
    onSave: (String, String, String, String) -> Unit,
    onBack: (() -> Unit)? = null,
    onCheckUpdate: () -> Unit = {}
) {
    // 默认使用公网中继（未配置时预填 relay.vios.top）
    var url by remember { mutableStateOf(relayUrl.ifBlank { top.vios.chat.net.PublicRelay.WS_URL }) }
    var http by remember { mutableStateOf(relayHttp.ifBlank { top.vios.chat.net.PublicRelay.HTTP_URL }) }
    var room by remember { mutableStateOf(relayRoom.ifBlank { top.vios.chat.net.PublicRelay.ROOM }) }
    var pass by remember { mutableStateOf(relayPass.ifBlank { top.vios.chat.net.PublicRelay.PASSPHRASE }) }
    var nameInput by remember { mutableStateOf(deviceName) }
    val context = LocalContext.current

    // 铃声选择器
    var ringPickerKey by remember { mutableStateOf("") }
    val ringLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        val uri = result.data?.getParcelableExtra<Uri>(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
        if (uri != null && ringPickerKey.isNotEmpty()) {
            RingtoneHelper.saveUri(context, ringPickerKey, uri)
            Toast.makeText(context, "铃声已保存", Toast.LENGTH_SHORT).show()
        }
    }

    // ===== OTA 更新：从中继网检查并安装新版 APK =====
    var updateChecking by remember { mutableStateOf(false) }
    var statsText by remember { mutableStateOf("点击查询中继网安装量") }
    var showFeedbackDialog by remember { mutableStateOf(false) }
    var feedbackText by remember { mutableStateOf("") }
    // 开发者模式：日志查看 Dialog
    var devLogDialog by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    fun checkRelayStats() {
        val baseUrl = if (http.isNotBlank()) http.trimEnd('/')
            else {
                val u = url.trim().removeSuffix("/ws").removeSuffix("/")
                if (u.startsWith("ws://")) "http://" + u.removePrefix("ws://") else u
            }
        if (baseUrl.isBlank()) { Toast.makeText(context, "请先配置中继服务器", Toast.LENGTH_SHORT).show(); return }
        kotlinx.coroutines.MainScope().launch {
            try {
                val conn = java.net.URL("$baseUrl/apk/stats").openConnection() as java.net.HttpURLConnection
                conn.connectTimeout = 6000
                conn.readTimeout = 6000
                val resp = conn.inputStream.bufferedReader().use { it.readText() }
                val d = org.json.JSONObject(resp)
                statsText = "总下载 ${d.optInt("downloads", 0)} · Web访问 ${d.optInt("webViews", 0)} · Web下载 ${d.optInt("webDownloads", 0)} · v${d.optString("version", "?")}"
            } catch (e: Exception) {
                statsText = "查询失败: ${e.message}"
            }
        }
    }

    fun submitFeedback() {
        val msg = feedbackText.trim()
        if (msg.isEmpty()) { Toast.makeText(context, "请输入反馈内容", Toast.LENGTH_SHORT).show(); return }
        val baseUrl = if (http.isNotBlank()) http.trimEnd('/')
            else {
                val u = url.trim().removeSuffix("/ws").removeSuffix("/")
                if (u.startsWith("ws://")) "http://" + u.removePrefix("ws://") else u
            }
        if (baseUrl.isBlank()) { Toast.makeText(context, "请先配置中继服务器", Toast.LENGTH_SHORT).show(); return }
        kotlinx.coroutines.MainScope().launch {
            try {
                val conn = java.net.URL("$baseUrl/feedback").openConnection() as java.net.HttpURLConnection
                conn.requestMethod = "POST"
                conn.doOutput = true
                conn.setRequestProperty("Content-Type", "application/json")
                conn.connectTimeout = 6000
                val body = org.json.JSONObject()
                    .put("device", deviceName)
                    .put("type", "bug")
                    .put("msg", msg)
                    .toString()
                conn.outputStream.use { it.write(body.toByteArray()) }
                val code = conn.responseCode
                if (code == 200) {
                    Toast.makeText(context, "反馈已提交，感谢！", Toast.LENGTH_SHORT).show()
                    feedbackText = ""
                    showFeedbackDialog = false
                } else {
                    Toast.makeText(context, "提交失败 (HTTP $code)", Toast.LENGTH_SHORT).show()
                }
            } catch (e: Exception) {
                Toast.makeText(context, "提交失败: ${e.message}", Toast.LENGTH_SHORT).show()
            }
        }
    }

    Column(Modifier.fillMaxSize().background(AppGradients.bg)) {
        // 统一顶部栏
        AppTopBar(title = "设置", onBack = onBack)

        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            // ===== ① 用户卡（微信"我"页头部风格） =====
            Surface(
                shape = RoundedCornerShape(16.dp),
                color = AppColors.surface,
                border = androidx.compose.foundation.BorderStroke(1.dp, AppColors.outline),
                modifier = Modifier.fillMaxWidth()
            ) {
                Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                    AvatarCircle(name = deviceName, size = 52.dp)
                    Spacer(Modifier.width(14.dp))
                    Column(Modifier.weight(1f)) {
                        Text(deviceName, color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                        Spacer(Modifier.height(4.dp))
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("唯一 ID: ", color = AppColors.textSecondary, fontSize = 12.sp)
                            Text(
                                DeviceIdentity.shortId(DeviceIdentity.getDeviceId(context)),
                                color = AppColors.textTertiary, fontSize = 12.sp,
                                fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
                            )
                            Spacer(Modifier.width(6.dp))
                            Text(
                                "不可更改",
                                color = AppColors.warning, fontSize = 10.sp,
                                modifier = Modifier
                                    .background(AppColors.warningDim, RoundedCornerShape(4.dp))
                                    .padding(horizontal = 5.dp, vertical = 2.dp)
                            )
                        }
                    }
                }
            }

            // ===== ② 设备名称 =====
            SectionCard("设备名称", "改名后对端看到的是新名称") {
                OutlinedTextField(
                    value = nameInput,
                    onValueChange = { nameInput = it },
                    label = { Text("自定义名称", color = AppColors.textTertiary) },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    colors = textFieldColors()
                )
                Spacer(Modifier.height(8.dp))
                Row {
                    Button(
                        onClick = {
                            if (nameInput.trim().isNotEmpty()) onNameChanged(nameInput.trim())
                        },
                        modifier = Modifier.weight(1f).height(44.dp),
                        shape = RoundedCornerShape(12.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = AppColors.primary)
                    ) { Text("保存名称", fontSize = 13.sp) }
                    Spacer(Modifier.width(8.dp))
                    Button(
                        onClick = {
                            nameInput = onRerollName()
                        },
                        modifier = Modifier.weight(1f).height(44.dp),
                        shape = RoundedCornerShape(12.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = AppColors.surfaceAlt)
                    ) { Text("随机换名", fontSize = 13.sp) }
                }
            }

            // ===== 外观（EVO 双主题：珍珠白/深邃黑/跟随系统） =====
            Text("外观", color = AppColors.textTertiary, fontSize = 12.sp, modifier = Modifier.padding(start = 4.dp))
            Surface(
                shape = RoundedCornerShape(16.dp),
                color = AppColors.surface,
                border = androidx.compose.foundation.BorderStroke(1.dp, AppColors.outline),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(Modifier.padding(vertical = 4.dp)) {
                    listOf(
                        "system" to "跟随系统",
                        "light" to "珍珠白 · Pearl White",
                        "dark" to "深邃黑 · Deep Black"
                    ).forEach { (mode, label) ->
                        val selected = AppColors.themeMode == mode
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .clickable {
                                    context.getSharedPreferences("everett_chat", android.content.Context.MODE_PRIVATE)
                                        .edit().putString("theme_mode", mode).apply()
                                    AppColors.applyTheme(mode,
                                        (context.resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) == android.content.res.Configuration.UI_MODE_NIGHT_YES)
                                }
                                .padding(horizontal = 16.dp, vertical = 13.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(label, color = AppColors.textPrimary, fontSize = 15.sp, modifier = Modifier.weight(1f))
                            if (selected) {
                                Icon(Icons.Default.Check, contentDescription = null, tint = AppColors.primary, modifier = Modifier.size(15.dp))
                            }
                        }
                        if (mode != "dark") {
                            HorizontalDivider(color = AppColors.outline, thickness = 0.5.dp)
                        }
                    }
                }
            }

            // ===== ③ 通知与铃声 =====
            Text("通知与铃声", color = AppColors.textTertiary, fontSize = 12.sp, modifier = Modifier.padding(start = 4.dp))
            Surface(
                shape = RoundedCornerShape(16.dp),
                color = AppColors.surface,
                border = androidx.compose.foundation.BorderStroke(1.dp, AppColors.outline),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column {
                    RingtoneRow(
                        label = "消息通知音",
                        icon = "",
                        onClick = {
                            ringPickerKey = RingtoneHelper.KEY_NOTIFY
                            ringLauncher.launch(
                                RingtoneHelper.buildRingtonePicker(
                                    context,
                                    RingtoneManager.TYPE_NOTIFICATION,
                                    RingtoneHelper.getNotifyUri(context)
                                )
                            )
                        },
                        onPreview = { RingtoneHelper.playNotification(context) }
                    )
                    RingtoneRow(
                        label = "语音来电铃声",
                        icon = "",
                        onClick = {
                            ringPickerKey = RingtoneHelper.KEY_VOICE
                            ringLauncher.launch(
                                RingtoneHelper.buildRingtonePicker(
                                    context,
                                    RingtoneManager.TYPE_RINGTONE,
                                    RingtoneHelper.getVoiceCallUri(context)
                                )
                            )
                        },
                        onPreview = { RingtoneHelper.playIncomingCall(context, false) }
                    )
                    RingtoneRow(
                        label = "视频来电铃声",
                        icon = "",
                        onClick = {
                            ringPickerKey = RingtoneHelper.KEY_VIDEO
                            ringLauncher.launch(
                                RingtoneHelper.buildRingtonePicker(
                                    context,
                                    RingtoneManager.TYPE_RINGTONE,
                                    RingtoneHelper.getVideoCallUri(context)
                                )
                            )
                        },
                        onPreview = { RingtoneHelper.playIncomingCall(context, true) }
                    )
                }
            }

            // ===== ④ 后台保活 =====
            Text("通用", color = AppColors.textTertiary, fontSize = 12.sp, modifier = Modifier.padding(start = 4.dp))
            Surface(
                shape = RoundedCornerShape(16.dp),
                color = AppColors.surface,
                border = androidx.compose.foundation.BorderStroke(1.dp, AppColors.outline),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column {
                    SettingRow(
                        "", "后台保活",
                        "前台服务 + 电池白名单，防止断连",
                        onClick = {
                            try {
                                val intent = Intent(
                                    android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                    android.net.Uri.parse("package:" + context.packageName)
                                )
                                context.startActivity(intent)
                            } catch (_: Exception) {
                                Toast.makeText(context, "请在系统设置中允许后台运行", Toast.LENGTH_SHORT).show()
                            }
                        }
                    )
                    HorizontalDivider(color = AppColors.outline)
                    // 自动删除消息（TTL）
                    var autoDeleteDialog by remember { mutableStateOf(false) }
                    val autoDeleteDays = remember {
                        context.getSharedPreferences("everett_chat", Context.MODE_PRIVATE)
                            .getInt("auto_delete_days", 0)
                    }
                    val autoDeleteLabel = when (autoDeleteDays) {
                        1 -> "24 小时"
                        7 -> "7 天"
                        30 -> "30 天"
                        90 -> "90 天"
                        else -> "关闭"
                    }
                    SettingRow(
                        "⏱", "自动删除消息",
                        "到期自动清除聊天记录 · 当前：$autoDeleteLabel",
                        onClick = { autoDeleteDialog = true }
                    )
                    // 自动删除选择 Dialog
                    if (autoDeleteDialog) {
                        Dialog(onDismissRequest = { autoDeleteDialog = false }) {
                            Surface(
                                shape = RoundedCornerShape(20.dp),
                                color = AppColors.surface,
                                border = androidx.compose.foundation.BorderStroke(1.dp, AppColors.outline),
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Column(Modifier.padding(20.dp)) {
                                    Text("自动删除消息", color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                                    Spacer(Modifier.height(4.dp))
                                    Text("到期后本地消息将被自动清除，无法恢复", color = AppColors.textTertiary, fontSize = 12.sp)
                                    Spacer(Modifier.height(12.dp))
                                    val options = listOf(0 to "关闭", 1 to "24 小时", 7 to "7 天", 30 to "30 天", 90 to "90 天")
                                    options.forEach { (days, label) ->
                                        Row(
                                            Modifier.fillMaxWidth().clickable {
                                                context.getSharedPreferences("everett_chat", Context.MODE_PRIVATE)
                                                    .edit().putInt("auto_delete_days", days).apply()
                                                autoDeleteDialog = false
                                                Toast.makeText(context, "自动删除：$label", Toast.LENGTH_SHORT).show()
                                            }.padding(vertical = 12.dp),
                                            verticalAlignment = Alignment.CenterVertically
                                        ) {
                                            Text(label, color = if (days == autoDeleteDays) AppColors.primary else AppColors.textPrimary, fontSize = 15.sp, modifier = Modifier.weight(1f))
                                            if (days == autoDeleteDays) Text("●", color = AppColors.primary, fontSize = 12.sp)
                                        }
                                        HorizontalDivider(color = AppColors.outline)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ===== ⑤ 中继服务器（折叠式 + 本机作为中继） =====
            var relayExpanded by remember { mutableStateOf(false) }
            // 内置中继服务器状态（全局常驻，由 ChatService 前台服务管理，24h+ 持续在线）
            var relayServerOn by remember { mutableStateOf(ChatService.isRelayEnabled(context)) }
            var relayServerPort by remember { mutableStateOf(ChatService.RELAY_PORT) }
            val localIpForRelay = remember { getLocalIpAddress() }

            Text("连接", color = AppColors.textTertiary, fontSize = 12.sp, modifier = Modifier.padding(start = 4.dp))
            Surface(
                shape = RoundedCornerShape(16.dp),
                color = AppColors.surface,
                border = androidx.compose.foundation.BorderStroke(1.dp, AppColors.outline),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column {
                    // 本机作为中继开关（全局常驻：切换即持久化，由前台服务保持运行）
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {
                                relayServerOn = !relayServerOn
                                ChatService.setRelayEnabled(context, relayServerOn)
                            }
                            .padding(horizontal = 14.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(Icons.Default.Wifi, contentDescription = null, tint = AppColors.textSecondary, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text("本机作为中继", color = Color.White, fontSize = 14.sp)
                            Text(
                                if (relayServerOn) "中继已开启 · 其他设备填下面的地址即可连接"
                                else "打开后本机成为中继节点（无需电脑）",
                                color = if (relayServerOn) AppColors.success else AppColors.textTertiary,
                                fontSize = 11.sp
                            )
                        }
                        // 开关
                        Box(
                            modifier = Modifier
                                .width(44.dp)
                                .height(24.dp)
                                .clip(RoundedCornerShape(12.dp))
                                .background(
                                    if (relayServerOn) AppGradients.primary
                                    else Brush.linearGradient(listOf(AppColors.surfaceHigh, AppColors.surfaceHigh))
                                )
                        ) {
                            Box(
                                modifier = Modifier
                                    .size(20.dp)
                                    .offset(x = if (relayServerOn) 22.dp else 2.dp, y = 2.dp)
                                    .background(Color.White, CircleShape)
                            )
                        }
                    }
                    // 开启后显示中继地址 + 一键填入
                    if (relayServerOn) {
                        HorizontalDivider(color = AppColors.outline)
                        Column(Modifier.padding(horizontal = 14.dp, vertical = 10.dp)) {
                            Text("其他设备请填写：", color = AppColors.textSecondary, fontSize = 12.sp)
                            Spacer(Modifier.height(6.dp))
                            Text(
                                "WS:  ws://$localIpForRelay:$relayServerPort/ws",
                                color = AppColors.success, fontSize = 12.sp,
                                fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
                            )
                            Text(
                                "HTTP: http://$localIpForRelay:$relayServerPort",
                                color = AppColors.success, fontSize = 12.sp,
                                fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
                            )
                            Spacer(Modifier.height(8.dp))
                            Button(
                                onClick = {
                                    // 一键填入本机中继地址 + 默认房间/口令
                                    url = top.vios.chat.net.RelayServer.relayWsAddress(localIpForRelay, relayServerPort)
                                    http = top.vios.chat.net.RelayServer.relayHttpAddress(localIpForRelay, relayServerPort)
                                    if (room.isBlank()) room = "everett"
                                    if (pass.isBlank()) pass = "everett123"
                                },
                                modifier = Modifier.fillMaxWidth().height(40.dp),
                                shape = RoundedCornerShape(10.dp),
                                colors = ButtonDefaults.buttonColors(containerColor = AppColors.primary)
                            ) { Text("一键填入本机地址", fontSize = 13.sp) }
                        }
                    }
                    SettingRow(
                        "", "中继服务器配置",
                        if (url.isBlank()) "未配置 · 跨网络连接需要" else "已配置 · $url",
                        onClick = { relayExpanded = !relayExpanded }
                    )
                    // OTA 更新：从中继服务器检查并安装新版 APK
                    HorizontalDivider(color = AppColors.outline)
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onCheckUpdate() }
                            .padding(horizontal = 14.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(Icons.Default.Refresh, contentDescription = null, tint = AppColors.textSecondary, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text("检查中继更新", color = Color.White, fontSize = 14.sp)
                            Text(
                                if (updateChecking) "正在检查..." else "从中继网获取最新 APK 并安装",
                                color = if (updateChecking) AppColors.info else AppColors.textTertiary,
                                fontSize = 11.sp
                            )
                        }
                        if (updateChecking) {
                            CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = AppColors.primary)
                        }
                    }
                    // 安装量统计：从中继网查询
                    HorizontalDivider(color = AppColors.outline)
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { checkRelayStats() }
                            .padding(horizontal = 14.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(Icons.Default.BarChart, contentDescription = null, tint = AppColors.textSecondary, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text("中继网安装量", color = Color.White, fontSize = 14.sp)
                            Text(
                                statsText,
                                color = if (statsText.startsWith("安装")) AppColors.success else AppColors.textTertiary,
                                fontSize = 11.sp
                            )
                        }
                    }
                    // 反馈问题：提交 bug/建议到中继网
                    HorizontalDivider(color = AppColors.outline)
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { showFeedbackDialog = true }
                            .padding(horizontal = 14.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(Icons.Default.Edit, contentDescription = null, tint = AppColors.textSecondary, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text("反馈问题", color = Color.White, fontSize = 14.sp)
                            Text("提交 bug 或建议到中继网，帮助改进", color = AppColors.textTertiary, fontSize = 11.sp)
                        }
                        Text(">", color = AppColors.textTertiary)
                    }
                    // 中继启停由 ChatService（前台服务）管理，不随设置页生命周期变化
                    // 退出设置页、App 退后台，中继都持续运行（24h+ 常驻）
                    if (relayExpanded) {
                        Column(Modifier.padding(horizontal = 14.dp, vertical = 4.dp)) {
                            OutlinedTextField(
                                value = url,
                                onValueChange = { url = it },
                                label = { Text("WebSocket 地址", color = AppColors.textTertiary) },
                                placeholder = { Text("ws://your-server:8080/ws", color = AppColors.textTertiary) },
                                modifier = Modifier.fillMaxWidth(),
                                singleLine = true,
                                colors = textFieldColors()
                            )
                            Spacer(Modifier.height(8.dp))
                            OutlinedTextField(
                                value = http,
                                onValueChange = { http = it },
                                label = { Text("HTTP 文件服务地址", color = AppColors.textTertiary) },
                                placeholder = { Text("http://your-server:8080", color = AppColors.textTertiary) },
                                modifier = Modifier.fillMaxWidth(),
                                singleLine = true,
                                colors = textFieldColors()
                            )
                            Spacer(Modifier.height(8.dp))
                            OutlinedTextField(
                                value = room,
                                onValueChange = { room = it },
                                label = { Text("房间 ID", color = AppColors.textTertiary) },
                                modifier = Modifier.fillMaxWidth(),
                                singleLine = true,
                                colors = textFieldColors()
                            )
                            Spacer(Modifier.height(8.dp))
                            OutlinedTextField(
                                value = pass,
                                onValueChange = { pass = it },
                                label = { Text("加密口令（双方一致）", color = AppColors.textTertiary) },
                                modifier = Modifier.fillMaxWidth(),
                                singleLine = true,
                                colors = textFieldColors()
                            )
                            Spacer(Modifier.height(10.dp))
                            Button(
                                onClick = { onSave(url.trim(), http.trim(), room.ifBlank { "default" }.trim(), pass.trim()) },
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .height(48.dp),
                                shape = RoundedCornerShape(14.dp),
                                colors = ButtonDefaults.buttonColors(containerColor = AppColors.primary)
                            ) {
                                Text("保存配置", fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                            }
                            Spacer(Modifier.height(8.dp))
                        }
                    }
                }
            }

            // ===== 开发者模式（日志/崩溃远程调试） =====
            Text("开发者", color = AppColors.textTertiary, fontSize = 12.sp, modifier = Modifier.padding(start = 4.dp))
            Surface(
                shape = RoundedCornerShape(16.dp),
                color = AppColors.surface,
                border = androidx.compose.foundation.BorderStroke(1.dp, AppColors.outline),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column {
                    // 崩溃状态提示（有未上传崩溃时显示）
                    if (DevLog.hasPendingCrash(context)) {
                        Row(
                            Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text("检测到崩溃记录", color = AppColors.warning, fontSize = 12.sp, modifier = Modifier.weight(1f))
                            Text("上传后清除", color = AppColors.textTertiary, fontSize = 11.sp)
                        }
                        HorizontalDivider(color = AppColors.outline)
                    }
                    // 查看日志
                    SettingRow("", "查看日志", "最近 ${DevLog.getRecentLogs(1000).size} 条内存日志", onClick = {
                        devLogDialog = true
                    })
                    // 上传日志到云端
                    SettingRow("", "上传日志到云端", "远程调试（relay.vios.top/log）", onClick = {
                        scope.launch {
                            val result = DevLog.upload(context)
                            Toast.makeText(context, result, Toast.LENGTH_SHORT).show()
                        }
                    })
                    // 版本信息
                    Row(Modifier.padding(horizontal = 14.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text("版本", color = AppColors.textSecondary, fontSize = 13.sp, modifier = Modifier.weight(1f))
                        Text("v${BuildConfig.VERSION_NAME}", color = AppColors.textTertiary, fontSize = 12.sp, fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace)
                    }
                }
            }
        }
    }

    // 反馈 Dialog
    if (showFeedbackDialog) {
        Dialog(onDismissRequest = { showFeedbackDialog = false }) {
            Surface(
                shape = RoundedCornerShape(20.dp),
                color = AppColors.surface,
                border = androidx.compose.foundation.BorderStroke(1.dp, AppColors.outline),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(Modifier.padding(20.dp)) {
                    Text("反馈问题", color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(6.dp))
                    Text("告诉我们你遇到的问题或改进建议，将提交到中继网", color = AppColors.textSecondary, fontSize = 12.sp)
                    Spacer(Modifier.height(12.dp))
                    OutlinedTextField(
                        value = feedbackText,
                        onValueChange = { feedbackText = it },
                        placeholder = { Text("例如：中继连接 5 分钟后断开...", color = AppColors.textTertiary) },
                        modifier = Modifier.fillMaxWidth().height(120.dp),
                        colors = textFieldColors()
                    )
                    Spacer(Modifier.height(12.dp))
                    Row {
                        Button(
                            onClick = { showFeedbackDialog = false },
                            modifier = Modifier.weight(1f).height(44.dp),
                            shape = RoundedCornerShape(12.dp),
                            colors = ButtonDefaults.buttonColors(containerColor = AppColors.surfaceAlt)
                        ) { Text("取消", fontSize = 14.sp) }
                        Spacer(Modifier.width(10.dp))
                        Button(
                            onClick = { submitFeedback() },
                            modifier = Modifier.weight(1f).height(44.dp),
                            shape = RoundedCornerShape(12.dp),
                            colors = ButtonDefaults.buttonColors(containerColor = AppColors.primary)
                        ) { Text("提交反馈", fontSize = 14.sp) }
                    }
                }
            }
        }
    }

    // 开发者模式：日志查看 Dialog
    if (devLogDialog) {
        val logs = DevLog.getRecentLogs(200)
        Dialog(onDismissRequest = { devLogDialog = false }) {
            Surface(
                shape = RoundedCornerShape(20.dp),
                color = AppColors.surface,
                border = androidx.compose.foundation.BorderStroke(1.dp, AppColors.outline),
                modifier = Modifier.fillMaxWidth().heightIn(max = 480.dp)
            ) {
                Column(Modifier.padding(20.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("最近日志", color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                        Text("${logs.size} 条", color = AppColors.textTertiary, fontSize = 12.sp)
                    }
                    Spacer(Modifier.height(10.dp))
                    // 日志列表（简单文本，可滚动）
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .weight(1f, fill = false)
                            .heightIn(min = 200.dp, max = 360.dp)
                            .background(AppColors.surfaceHigh, RoundedCornerShape(12.dp))
                    ) {
                        if (logs.isEmpty()) {
                            Text("暂无日志", color = AppColors.textTertiary, fontSize = 13.sp, modifier = Modifier.padding(16.dp))
                        } else {
                            val sb = StringBuilder()
                            logs.forEach { l ->
                                val t = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault())
                                    .format(java.util.Date(l.optLong("t", 0)))
                                sb.append("[$t][${l.optString("lvl", "?")}] ").append(l.optString("msg", "")).append("\n\n")
                            }
                            Text(
                                sb.toString(),
                                color = AppColors.textSecondary,
                                fontSize = 11.sp,
                                fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .verticalScroll(rememberScrollState())
                                    .padding(12.dp)
                            )
                        }
                    }
                    Spacer(Modifier.height(14.dp))
                    Button(
                        onClick = {
                            devLogDialog = false
                            scope.launch {
                                val result = DevLog.upload(context)
                                Toast.makeText(context, result, Toast.LENGTH_SHORT).show()
                            }
                        },
                        modifier = Modifier.fillMaxWidth().height(44.dp),
                        shape = RoundedCornerShape(12.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = AppColors.primary)
                    ) { Text("上传到云端", fontSize = 14.sp) }
                }
            }
        }
    }
}

// ================= 中继网可视化 =================

/** 中继网实时拓扑可视化（WebView 加载中继节点网页 + 状态卡片） */
@Composable
fun NetMapScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    // 中继地址：优先自动发现节点，否则手动配置
    val relayUrlPref = remember {
        context.getSharedPreferences("everett_chat", Context.MODE_PRIVATE)
            .getString("relay_url", "").orEmpty()
    }
    val relayHttpPref = remember {
        context.getSharedPreferences("everett_chat", Context.MODE_PRIVATE)
            .getString("relay_http", "").orEmpty()
    }
    var mapUrl by remember { mutableStateOf<String?>(null) }
    var discoveredIp by remember { mutableStateOf<String?>(null) }
    var statusText by remember { mutableStateOf("正在发现中继节点...") }
    // 候选中继地址（优先级：手动配置 > 本机中继 > 自动发现）
    // 注意：本机访问自己的中继必须用 127.0.0.1 —— 局域网 IP 可能被 VPN（如 vivo 多屏协同隧道）拦截导致 ERR_CONNECTION_REFUSED
    val localRelayHttp = remember {
        if (ChatService.isRelayEnabled(context)) {
            "http://127.0.0.1:${top.vios.chat.net.RelayServer.DEFAULT_PORT}"
        } else null
    }
    // 本机局域网 IP（供显示）
    val localIpDisplay = remember { getLocalIpAddress() }
    var nodeCount by remember { mutableStateOf(0) }
    var userCount by remember { mutableStateOf(0) }
    var apkVer by remember { mutableStateOf("") }
    var downloads by remember { mutableStateOf(-1) }

    // 中继节点发现：优先手动配置 > 本机中继 > 自动发现（监听端口与后台服务冲突时静默跳过）
    val discovery = remember { top.vios.chat.net.RelayDiscovery(context) }
    LaunchedEffect(Unit) {
        // 1. 手动配置优先
        val manual = relayHttpPref.ifBlank { relayUrlPref.replace("ws", "http").removeSuffix("/ws") }
        if (manual.isNotBlank()) {
            mapUrl = manual.trimEnd('/')
            statusText = "使用已配置中继"
        } else if (localRelayHttp != null) {
            // 2. 本机中继（无需监听端口，直接访问本机）
            mapUrl = localRelayHttp
            statusText = "使用本机中继"
        } else {
            // 3. 自动发现（尝试监听广播；若端口被占用则跳过，不阻塞页面）
            try {
                discovery.startListen { node ->
                    if (discoveredIp == null) {
                        discoveredIp = node.ip
                        mapUrl = node.httpUrl
                    }
                }
            } catch (_: Exception) {}
            kotlinx.coroutines.delay(4000)
            if (mapUrl == null) {
                statusText = "未发现中继，请先开启中继或配置地址"
            }
        }
    }
    DisposableEffect(Unit) { onDispose { discovery.stopListen() } }

    // 轮询拓扑信息（网络请求在 IO 线程，避免 NetworkOnMainThreadException）
    LaunchedEffect(mapUrl) {
        while (true) {
            val base = mapUrl
            if (base != null) {
                kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                    try {
                        val conn = java.net.URL("$base/topology").openConnection() as java.net.HttpURLConnection
                        conn.connectTimeout = 5000
                        conn.readTimeout = 5000
                        val resp = conn.inputStream.bufferedReader().use { it.readText() }
                        val d = org.json.JSONObject(resp)
                        nodeCount = d.optJSONArray("peers")?.length() ?: 0
                        userCount = d.optJSONArray("users")?.length() ?: 0
                        val apk = d.optJSONObject("apk")
                        apkVer = apk?.optString("versionName", "") ?: ""
                        statusText = "节点在线 · 互联 ${nodeCount} 台 · 刷新于 " + java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.CHINA).format(java.util.Date())
                    } catch (e: Exception) {
                        statusText = "中继连接失败: ${e.message}"
                    }
                }
                // 统计下载量
                kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                    try {
                        val conn = java.net.URL("$base/apk/stats").openConnection() as java.net.HttpURLConnection
                        conn.connectTimeout = 5000
                        conn.readTimeout = 5000
                        val resp = conn.inputStream.bufferedReader().use { it.readText() }
                        downloads = org.json.JSONObject(resp).optInt("downloads", -1)
                    } catch (_: Exception) {}
                }
            }
            kotlinx.coroutines.delay(5000)
        }
    }

    Column(Modifier.fillMaxSize().background(AppGradients.bg)) {
        AppTopBar(title = "中继网可视化", onBack = onBack)

        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(12.dp)
        ) {
            // ===== 状态卡片 =====
            Surface(
                shape = RoundedCornerShape(16.dp),
                color = AppColors.surface,
                border = androidx.compose.foundation.BorderStroke(1.dp, AppColors.outline),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(Modifier.padding(14.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.Hub, contentDescription = null, tint = AppColors.textSecondary, modifier = Modifier.size(20.dp))
                        Spacer(Modifier.width(10.dp))
                        Text("中继网实时状态", color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                        Spacer(Modifier.weight(1f))
                        Box(
                            Modifier
                                .size(8.dp)
                                .background(if (mapUrl != null) AppColors.success else AppColors.error, CircleShape)
                        )
                    }
                    Spacer(Modifier.height(8.dp))
                    Text(statusText, color = AppColors.textSecondary, fontSize = 12.sp)
                    if (mapUrl != null) {
                        Spacer(Modifier.height(4.dp))
                        // 本机中继显示局域网 IP（其他设备可用），否则显示实际地址
                        val displayUrl = if (mapUrl == localRelayHttp && localIpDisplay != "未知") {
                            "http://$localIpDisplay:${top.vios.chat.net.RelayServer.DEFAULT_PORT}"
                        } else mapUrl
                        Text("中继地址: $displayUrl", color = AppColors.primary, fontSize = 11.sp,
                            fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace)
                    }
                    Spacer(Modifier.height(10.dp))
                    // 统计行
                    Row {
                        StatChip("互联节点", nodeCount.toString())
                        Spacer(Modifier.width(8.dp))
                        StatChip("在线用户", userCount.toString())
                        Spacer(Modifier.width(8.dp))
                        StatChip("安装量", if (downloads >= 0) downloads.toString() else "-")
                    }
                    if (apkVer.isNotEmpty()) {
                        Spacer(Modifier.height(8.dp))
                        Text("最新版本: v$apkVer", color = AppColors.success, fontSize = 12.sp)
                    }
                }
            }

            Spacer(Modifier.height(12.dp))

            // ===== 拓扑图（WebView 实时） =====
            if (mapUrl != null) {
                Surface(
                    shape = RoundedCornerShape(16.dp),
                    color = AppColors.surface,
                    border = androidx.compose.foundation.BorderStroke(1.dp, AppColors.outline),
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(420.dp)
                ) {
                    Box {
                        var wvRef by remember { mutableStateOf<android.webkit.WebView?>(null) }
                        val apkScope = rememberCoroutineScope()
                        AndroidView(
                            factory = { ctx ->
                                android.webkit.WebView(ctx).apply {
                                    settings.javaScriptEnabled = true
                                    settings.domStorageEnabled = true
                                    settings.mediaPlaybackRequiresUserGesture = false
                                    webViewClient = android.webkit.WebViewClient()
                                    // 拦截 APK 下载：WebView 默认不处理下载，这里直接下载并安装
                                    setDownloadListener { url, userAgent, contentDisposition, mimetype, contentLength ->
                                        if (url.contains(".apk")) {
                                            Toast.makeText(context, "开始下载 APK...", Toast.LENGTH_SHORT).show()
                                            apkScope.launch {
                                                try {
                                                    val conn = java.net.URL(url).openConnection()
                                                    conn.connectTimeout = 10000
                                                    conn.readTimeout = 120000
                                                    val apkFile = java.io.File(context.cacheDir, "everett-chat-web.apk")
                                                    conn.getInputStream().use { input ->
                                                        apkFile.outputStream().use { out -> input.copyTo(out) }
                                                    }
                                                    val uri = androidx.core.content.FileProvider.getUriForFile(
                                                        context, "${context.packageName}.fileprovider", apkFile
                                                    )
                                                    val installIntent = Intent(Intent.ACTION_VIEW).apply {
                                                        setDataAndType(uri, "application/vnd.android.package-archive")
                                                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                                    }
                                                    Toast.makeText(context, "下载完成，正在安装...", Toast.LENGTH_SHORT).show()
                                                    context.startActivity(installIntent)
                                                } catch (e: Exception) {
                                                    Toast.makeText(context, "下载失败: ${e.message}", Toast.LENGTH_LONG).show()
                                                }
                                            }
                                        } else {
                                            Toast.makeText(context, "不支持的文件类型", Toast.LENGTH_SHORT).show()
                                        }
                                    }
                                    wvRef = this
                                    loadUrl(mapUrl!!)
                                }
                            },
                            update = { wv ->
                                wvRef = wv
                                val current = mapUrl
                                if (current != null && wv.url != current) {
                                    wv.loadUrl(current)
                                }
                            }
                        )
                        // 右上角刷新按钮
                        Text(
                            "",
                            fontSize = 18.sp,
                            modifier = Modifier
                                .align(Alignment.TopEnd)
                                .padding(8.dp)
                                .background(AppColors.surfaceAlt, RoundedCornerShape(8.dp))
                                .padding(8.dp)
                                .clickable {
                                    wvRef?.reload()
                                }
                        )
                    }
                }
                Spacer(Modifier.height(8.dp))
                Text("浏览器同款页面 · 实时脉冲拓扑", color = AppColors.textTertiary, fontSize = 11.sp, modifier = Modifier.padding(horizontal = 4.dp))
            } else {
                Surface(
                    shape = RoundedCornerShape(16.dp),
                    color = AppColors.surface,
                    border = androidx.compose.foundation.BorderStroke(1.dp, AppColors.outline),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Column(
                        Modifier.padding(24.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Icon(Icons.Default.Hub, contentDescription = null, tint = AppColors.textSecondary, modifier = Modifier.size(40.dp))
                        Spacer(Modifier.height(10.dp))
                        Text("未发现中继节点", color = Color.White, fontSize = 15.sp)
                        Spacer(Modifier.height(6.dp))
                        Text(
                            "请先开启任意设备的中继服务（设置页 → 本机作为中继）\n或在设置中配置中继地址",
                            color = AppColors.textTertiary, fontSize = 12.sp,
                            textAlign = androidx.compose.ui.text.style.TextAlign.Center
                        )
                    }
                }
            }
        }
    }
}

/** 统计小徽章 */
@Composable
fun RowScope.StatChip(label: String, value: String) {
    Surface(
        shape = RoundedCornerShape(10.dp),
        color = AppColors.surfaceHigh,
        modifier = Modifier.weight(1f)
    ) {
        Column(
            Modifier.padding(vertical = 8.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(value, color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold)
            Text(label, color = AppColors.textSecondary, fontSize = 10.sp)
        }
    }
}

// ================= 聊天页 =================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatScreen(
    messages: androidx.compose.runtime.snapshots.SnapshotStateList<UiMessage>,
    transport: Transport?,
    peerConnected: Boolean,
    peerName: String,
    deviceName: String,
    onBack: () -> Unit,
    onMessage: (String) -> Unit = {},
    onStartCall: (Boolean) -> Unit = {},
    aiOnly: Boolean = false,
    peerDeviceId: String = "",   // 对端设备唯一 ID（定向通信路由）
    peerOnline: Boolean = false, // 对端是否在线（relay /users 轮询）
    onPersist: ((UiMessage, String) -> Unit)? = null,   // 消息持久化（消息, convId）
    onDeleteMsg: ((String) -> Unit)? = null             // 删除单条消息（消息 id）
) {
    val context = LocalContext.current
    val input = remember { mutableStateOf("") }
    val isSending = remember { mutableStateOf(false) }
    val listState = rememberLazyListState()
    // 自动滚动：用户位于底部时跟随 streaming；上滚后停止并显示跳转按钮
    val isAtBottom by remember {
        androidx.compose.runtime.derivedStateOf {
            val info = listState.layoutInfo
            val last = info.visibleItemsInfo.lastOrNull() ?: return@derivedStateOf true
            last.index >= info.totalItemsCount - 2
        }
    }
    val scope = rememberCoroutineScope()
    // 自动滚动跟随：新消息到达且用户位于底部时滚动到最新（streaming 实时跟随）
    // 首次进入用 scrollToItem 无动画（避免抖动），后续用 animateScrollToItem
    val isFirstLoad = remember { mutableStateOf(true) }
    androidx.compose.runtime.LaunchedEffect(messages.size) {
        if (isAtBottom && messages.isNotEmpty()) {
            if (isFirstLoad.value) {
                isFirstLoad.value = false
                listState.scrollToItem(messages.size - 1)
            } else {
                listState.animateScrollToItem(messages.size - 1)
            }
        }
    }
    val apiClient = remember { ChatApiClient() }
    val aiEnabled = remember { mutableStateOf(aiOnly) }  // AI 会话固定 AI 模式（与设备会话分开）
    val myDeviceId = remember { DeviceIdentity.getDeviceId(context) }
    val voiceRecorder = remember { VoiceRecorder(context) }
    val isRecording = remember { mutableStateOf(false) }
    val recordingDuration = remember { mutableStateOf(0L) }
    // 微信式录音浮层：是否显示 + 是否进入上滑取消区
    val recordingOverlay = remember { mutableStateOf(false) }
    val recordingCancelZone = remember { mutableStateOf(false) }
    val playingMsgId = remember { mutableStateOf<String?>(null) }
    val aiJob = remember { mutableStateOf<kotlinx.coroutines.Job?>(null) }
    var previewFile by remember { mutableStateOf<UiFile?>(null) }
    val voiceMode = remember { mutableStateOf(false) }  // false=文本, true=语音
    // AI 模型选择（持久化，默认 deepseek-v4-flash）
    val aiModel = remember { mutableStateOf(
        context.getSharedPreferences("everett_chat", android.content.Context.MODE_PRIVATE)
            .getString("ai_model", ApiConfig.MODEL) ?: ApiConfig.MODEL
    ) }
    fun selectModel(id: String) {
        aiModel.value = id
        context.getSharedPreferences("everett_chat", android.content.Context.MODE_PRIVATE)
            .edit().putString("ai_model", id).apply()
    }
    // 会话信息面板（对端/AI 通用，顶部 ℹ️ 触发）
    var sessionInfoVisible by remember { mutableStateOf(false) }
    // 消息长按操作（复制/删除）
    var actionMsg by remember { mutableStateOf<UiMessage?>(null) }

    // 停止录音并发送（先定义，供权限回调引用）
    fun stopRecording(send: Boolean) {
        if (!isRecording.value) return
        isRecording.value = false
        val data = voiceRecorder.stop()
        if (send && data != null) {
            messages.add(UiMessage(
                id = System.currentTimeMillis().toString() + "v",
                role = "peer",
                text = "[语音] ${data.size / 1024} KB",
                audio = data,
                audioDurationMs = recordingDuration.value,
                senderName = deviceName, senderId = myDeviceId
            ))
            transport?.sendAudio(data)
        } else {
            Toast.makeText(context, "已取消录音", Toast.LENGTH_SHORT).show()
        }
        recordingDuration.value = 0
    }

    // 相机权限请求（视频通话用）
    val cameraPermLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) {
            onStartCall(true)
        } else {
            Toast.makeText(context, "需要相机权限才能视频通话", Toast.LENGTH_SHORT).show()
        }
    }

    // 录音权限请求
    val audioPermLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) {
            // 开始录音
            isRecording.value = true
            voiceRecorder.start()
            scope.launch {
                while (isRecording.value) {
                    recordingDuration.value = voiceRecorder.currentDurationMs()
                    if (recordingDuration.value >= 60_000) {
                        // B8 修复: 60s 上限自动停止发送
                        stopRecording(true)
                        break
                    }
                    delay(100)
                }
            }
        } else {
            Toast.makeText(context, "需要麦克风权限才能发送语音", Toast.LENGTH_SHORT).show()
        }
    }

    // 开始录音
    fun startRecording() {
        if (transport == null || !peerConnected) {
            Toast.makeText(context, "请先连接对端", Toast.LENGTH_SHORT).show()
            return
        }
        if (android.os.Build.VERSION.SDK_INT >= 23) {
            val perm = android.Manifest.permission.RECORD_AUDIO
            val granted = androidx.core.content.ContextCompat.checkSelfPermission(context, perm) ==
                android.content.pm.PackageManager.PERMISSION_GRANTED
            if (granted) {
                isRecording.value = true
                voiceRecorder.start()
                scope.launch {
                    while (isRecording.value) {
                        recordingDuration.value = voiceRecorder.currentDurationMs()
                        if (recordingDuration.value >= 60_000) break
                        delay(100)
                    }
                }
            } else {
                audioPermLauncher.launch(perm)
            }
        } else {
            isRecording.value = true
            voiceRecorder.start()
        }
    }

    fun sendToAi(imageBase64: String? = null) {
        val text = input.value.trim().ifEmpty {
            if (imageBase64 != null) "[图片] 请查看" else ""
        }
        if (text.isEmpty() || isSending.value) return
        input.value = ""
        val userMsg = UiMessage(System.currentTimeMillis().toString(), "user", text)
        messages.add(userMsg)
        onPersist?.invoke(userMsg, if (aiOnly) MessageStore.CONV_AI_ID else peerDeviceId)
        isSending.value = true
        val aiIdx = messages.size
        messages.add(UiMessage("ai-" + System.currentTimeMillis().toString(), "ai", ""))

        aiJob.value = scope.launch {
            try {
                // B3 修复: 过滤错误消息和空占位，避免污染 AI 上下文
                val history = messages.take(aiIdx)
                    .filter { (it.role == "user" || it.role == "ai") && !it.isError && it.text.isNotBlank() }
                    .map { ChatMessage(if (it.role == "user") "user" else "assistant", it.text) }
                val result = apiClient.sendMessage(
                    history, text,
                    onDelta = { delta, isReasoning ->
                        if (isReasoning) {
                            messages[aiIdx] = UiMessage(
                                messages[aiIdx].id, "ai", messages[aiIdx].text,
                                reasoning = messages[aiIdx].reasoning + delta
                            )
                        } else {
                            messages[aiIdx] = UiMessage(
                                messages[aiIdx].id, "ai", messages[aiIdx].text + delta,
                                reasoning = messages[aiIdx].reasoning
                            )
                        }
                    },
                    imageBase64 = imageBase64,
                    model = aiModel.value
                )
                if (result == null) {
                    // 用户取消
                    messages[aiIdx] = UiMessage(messages[aiIdx].id, "ai", messages[aiIdx].text.ifEmpty { "⏹ 已停止生成" })
                } else if (result.isEmpty()) {
                    messages[aiIdx] = UiMessage(messages[aiIdx].id, "ai", "（无回复）", isError = true)
                }
            } catch (e: Exception) {
                messages[aiIdx] = UiMessage(messages[aiIdx].id, "ai", "${e.message ?: "网络错误"} · 点此重试", isError = true)
            } finally {
                isSending.value = false
                // 持久化 AI 回复（最终状态）
                if (messages.getOrNull(aiIdx)?.text?.isNotEmpty() == true) {
                    onPersist?.invoke(messages[aiIdx], if (aiOnly) MessageStore.CONV_AI_ID else peerDeviceId)
                }
            }
        }
    }

    fun stopAi() {
        apiClient.cancel()
        aiJob.value?.cancel()
        isSending.value = false
    }

    // 文件选择器
    val filePicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) {
            scope.launch {
                try {
                    val resolver = context.contentResolver
                    val name = resolver.query(uri, null, null, null, null)?.use { c ->
                        val idx = c.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                        if (idx >= 0 && c.moveToFirst()) c.getString(idx) else "file"
                    } ?: "file"
                    val mime = resolver.getType(uri) ?: "application/octet-stream"
                    val data = resolver.openInputStream(uri)?.use { it.readBytes() } ?: ByteArray(0)
                    val fileId = System.currentTimeMillis().toString() + "f"
                    val aiMode = aiOnly || aiEnabled.value

                    if (aiMode) {
                        // ===== AI 模式：图片走视觉模型，其他文件发附件+描述 =====
                        messages.add(UiMessage(
                            id = fileId,
                            role = "user",
                            text = if (mime.startsWith("image/")) "[图片] $name" else "[文件] $name (${data.size / 1024} KB)",
                            file = UiFile(name, data.size.toLong(), mime, data, false),
                            senderName = deviceName, senderId = myDeviceId
                        ))
                        if (mime.startsWith("image/")) {
                            val b64 = "data:$mime;base64," + android.util.Base64.encodeToString(data, android.util.Base64.NO_WRAP)
                            sendToAi(b64)
                        } else {
                            input.value = "请分析这个文件: $name (${data.size / 1024} KB)"
                            sendToAi()
                        }
                    } else {
                        // ===== 对端模式：加密传输 =====
                        if (transport == null || !transport.isConnected()) {
                            Toast.makeText(context, "未连接对端，请先建立连接再发送文件", Toast.LENGTH_SHORT).show()
                            return@launch
                        }
                        messages.add(UiMessage(
                            id = fileId,
                            role = "peer", text = "[发送中] $name",
                            file = UiFile(name, data.size.toLong(), mime, data, false),
                            senderName = deviceName, senderId = myDeviceId,
                            progress = 0f
                        ))
                        // 发送文件并更新进度
                        transport?.sendFile(name, mime, data)
                        // 显示进度（发送完成后转正式文件消息）
                        kotlinx.coroutines.delay(300)
                        val idx = messages.indexOfFirst { it.id == fileId }
                        if (idx >= 0) {
                            messages[idx] = UiMessage(
                                id = fileId, role = "peer",
                                text = "[文件] $name (${data.size / 1024} KB)",
                                file = UiFile(name, data.size.toLong(), mime, data, false)
                            )
                        }
                        Toast.makeText(context, "已发送: $name", Toast.LENGTH_SHORT).show()
                    }
                } catch (e: Exception) {
                    Toast.makeText(context, "发送失败: ${e.message}", Toast.LENGTH_SHORT).show()
                }
            }
        }
    }

    // 欢迎消息（仅 AI 会话添加；对端会话用居中灰色小提示，不显示 AI 欢迎气泡）
    LaunchedEffect(Unit) {
        if (aiOnly && messages.isEmpty()) {
            messages.add(UiMessage("w1", "ai",
                "你好，我是 EVO 助手\n\n直接输入问题与我对话，\n支持文字、图片、文件分析。"))
        }
    }

    // 自动滚动
    LaunchedEffect(messages.size) {
        if (messages.isNotEmpty()) listState.animateScrollToItem(messages.size - 1)
    }

    // 重试 AI 消息
    fun retryAi(msgId: String) {
        val idx = messages.indexOfFirst { it.id == msgId }
        if (idx < 0) return
        val question = messages.take(idx).lastOrNull { it.role == "user" }?.text ?: return
        messages[idx] = UiMessage(msgId, "ai", "")
        isSending.value = true
        val aiIdx = idx
        aiJob.value = scope.launch {
            try {
                // B3 修复: 同样过滤错误消息
                val history = messages.take(aiIdx)
                    .filter { (it.role == "user" || it.role == "ai") && !it.isError && it.text.isNotBlank() }
                    .map { ChatMessage(if (it.role == "user") "user" else "assistant", it.text) }
                val result = apiClient.sendMessage(
                    history, question,
                    onDelta = { delta, isReasoning ->
                        if (isReasoning) {
                            messages[aiIdx] = UiMessage(
                                messages[aiIdx].id, "ai", messages[aiIdx].text,
                                reasoning = messages[aiIdx].reasoning + delta
                            )
                        } else {
                            messages[aiIdx] = UiMessage(
                                messages[aiIdx].id, "ai", messages[aiIdx].text + delta,
                                reasoning = messages[aiIdx].reasoning
                            )
                        }
                    },
                    model = aiModel.value
                )
                if (result == null) {
                    messages[aiIdx] = UiMessage(messages[aiIdx].id, "ai", messages[aiIdx].text.ifEmpty { "⏹ 已停止生成" })
                } else if (result.isEmpty()) {
                    messages[aiIdx] = UiMessage(messages[aiIdx].id, "ai", "（无回复）", isError = true)
                }
            } catch (e: Exception) {
                messages[aiIdx] = UiMessage(messages[aiIdx].id, "ai", "${e.message ?: "网络错误"} · 点此重试", isError = true)
            } finally {
                isSending.value = false
            }
        }
    }

    fun sendToPeer() {
        val text = input.value.trim()
        if (text.isEmpty()) return
        // B4 修复: 未连接时明确提示
        if (transport == null || !transport.isConnected()) {
            Toast.makeText(context, "未连接对端，请先到\"连接\"页建立连接", Toast.LENGTH_SHORT).show()
            return
        }
        input.value = ""
        messages.add(UiMessage(
            id = System.currentTimeMillis().toString(),
            role = "peer", text = text,
            senderName = deviceName, senderId = myDeviceId
        ))
        // 定向发送：target = 对端设备唯一 ID（中继只转发给目标设备）
        transport.sendText(text, peerDeviceId.ifEmpty { null })
    }

    fun send() {
        if (aiEnabled.value) sendToAi() else sendToPeer()
    }

    // 文件全屏预览弹窗
    previewFile?.let { file ->
        if (file.mime.startsWith("image/")) {
            Dialog(
                onDismissRequest = { previewFile = null },
                properties = DialogProperties(usePlatformDefaultWidth = false)
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Color.Black)
                        .clickable { previewFile = null },
                    contentAlignment = Alignment.Center
                ) {
                    val data = file.data
                    if (data != null) {
                        val bitmap = remember(data) { decodeBitmap(data, 1200) }
                        if (bitmap != null) {
                            Image(
                                bitmap = bitmap.asImageBitmap(),
                                contentDescription = null,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(16.dp),
                                contentScale = ContentScale.Fit
                            )
                        }
                    }
                    Icon(Icons.Default.Close, contentDescription = null, tint = Color.White, modifier = Modifier
                            .size(28.dp)
                            .align(Alignment.TopEnd)
                            .padding(16.dp)
                            .clickable { previewFile = null })
                }
            }
        } else if (file.mime.startsWith("video/")) {
            // 视频 → 用系统播放器打开
            previewFile = null
            try {
                val tmp = File(context.cacheDir, "preview_${file.name}")
                file.data?.let { tmp.writeBytes(it) }
                val uri = androidx.core.content.FileProvider.getUriForFile(
                    context, "${context.packageName}.fileprovider", tmp
                )
                val intent = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, file.mime)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
            } catch (e: Exception) {
                Toast.makeText(context, "无法播放视频: ${e.message}", Toast.LENGTH_SHORT).show()
            }
        } else {
            // 普通文件 → 用系统方式打开
            previewFile = null
            try {
                val tmp = File(context.cacheDir, "preview_${file.name}")
                file.data?.let { tmp.writeBytes(it) }
                val uri = androidx.core.content.FileProvider.getUriForFile(
                    context, "${context.packageName}.fileprovider", tmp
                )
                val intent = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, file.mime)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
            } catch (e: Exception) {
                Toast.makeText(context, "无法打开文件: ${e.message}", Toast.LENGTH_SHORT).show()
            }
        }
    }

    Box(Modifier.fillMaxSize()) {
    Scaffold(
        containerColor = AppColors.bg,
        contentWindowInsets = WindowInsets.systemBars.only(WindowInsetsSides.Horizontal),
        topBar = {
            EvoTopBar(
                title = if (aiOnly) "AI 助手" else (peerName.ifEmpty { "EVO" }),
                subtitle = if (aiOnly) {
                    // AI 会话副标题：当前模型名
                    ApiConfig.MODELS.firstOrNull { it.id == aiModel.value }?.name ?: "DeepSeek V4"
                } else if (peerDeviceId.isNotEmpty()) {
                    // 对端会话副标题：在线状态 + 短 ID（标题=昵称，副标题=状态+ID）
                    val statusText = if (peerOnline) "在线 · " else "离线 · "
                    statusText + "ID: " + DeviceIdentity.shortId(peerDeviceId)
                } else {
                    "EVO"
                },
                onBack = onBack,
                actions = {
                    // 通话按钮（已连接且非 AI 模块时显示）
                    if (peerConnected && !aiOnly) {
                        IconButton(
                            onClick = { onStartCall(false) },
                            modifier = Modifier.size(40.dp),
                            colors = IconButtonDefaults.iconButtonColors(contentColor = AppColors.primary)
                        ) {
                            Icon(Icons.Default.Phone, contentDescription = "语音通话", modifier = Modifier.size(20.dp))
                        }
                        IconButton(
                            onClick = {
                                // 视频通话需相机权限
                                if (android.os.Build.VERSION.SDK_INT >= 23) {
                                    val granted = androidx.core.content.ContextCompat.checkSelfPermission(
                                        context, android.Manifest.permission.CAMERA
                                    ) == android.content.pm.PackageManager.PERMISSION_GRANTED
                                    if (granted) {
                                        onStartCall(true)
                                    } else {
                                        cameraPermLauncher.launch(android.Manifest.permission.CAMERA)
                                    }
                                } else {
                                    onStartCall(true)
                                }
                            },
                            modifier = Modifier.size(40.dp),
                            colors = IconButtonDefaults.iconButtonColors(contentColor = AppColors.primary)
                        ) {
                            Icon(Icons.Default.Videocam, contentDescription = "视频通话", modifier = Modifier.size(20.dp))
                        }
                    }
                    // 会话信息入口（对端/AI 通用：查看更多信息）
                    IconButton(
                        onClick = { sessionInfoVisible = true },
                        modifier = Modifier.size(40.dp),
                        colors = IconButtonDefaults.iconButtonColors(contentColor = AppColors.textSecondary)
                    ) {
                        Icon(Icons.Default.Info, contentDescription = "查看更多信息", modifier = Modifier.size(20.dp))
                    }
                    Spacer(Modifier.width(4.dp))
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            // ===== 连接状态条（重连时短暂提示，非消息） =====
            var showConnBanner by remember { mutableStateOf(false) }
            val prevConnected = remember { mutableStateOf(peerConnected) }
            LaunchedEffect(peerConnected) {
                // 从离线 → 在线（重连成功）：显示 2 秒提示
                if (peerConnected && !prevConnected.value && !aiOnly) {
                    showConnBanner = true
                    delay(2000)
                    showConnBanner = false
                }
                prevConnected.value = peerConnected
            }
            androidx.compose.animation.AnimatedVisibility(
                visible = showConnBanner,
                enter = androidx.compose.animation.fadeIn() + androidx.compose.animation.expandVertically(),
                exit = androidx.compose.animation.fadeOut() + androidx.compose.animation.shrinkVertically()
            ) {
                Box(
                    Modifier.fillMaxWidth().background(AppColors.primaryDim),
                    contentAlignment = Alignment.Center
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 7.dp)) {
                        Icon(Icons.Default.Lock, contentDescription = null,
                            tint = AppColors.primary, modifier = Modifier.size(13.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("已重新连接 · 端到端加密", fontSize = 12.sp, color = AppColors.primary)
                    }
                }
            }
            // 消息列表 + 浮动跳转按钮（叠加层）
            Box(Modifier.weight(1f).fillMaxWidth()) {
                LazyColumn(
                    state = listState,
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(horizontal = 14.dp, vertical = 10.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                // 顶部居中灰色小提示（微信风格：字体小、气泡小、不明显）
                item {
                    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                        Surface(
                            shape = RoundedCornerShape(10.dp),
                            color = AppColors.surfaceHigh.copy(alpha = 0.5f)
                        ) {
                            Text(
                                if (aiOnly) "与 AI 助手对话 · 经云端中继" else "端到端加密 · 消息仅双方可见",
                                color = AppColors.textTertiary,
                                fontSize = 10.sp,
                                modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp)
                            )
                        }
                    }
                }
                items(messages.size) { index ->
                    val msg = messages[index]
                    // 同发送者合并分组：组首显示头像+昵称，组末显示时间，间隔 >5 分钟视为新组
                    // senderKey：user=me / ai=ai / peer=对方ID（避免空 senderId 误合并）
                    val senderKey = when {
                        msg.role == "ai" -> "ai"
                        msg.role == "user" -> "me"
                        else -> msg.senderId.ifEmpty { "peer" }
                    }
                    val prev = messages.getOrNull(index - 1)
                    val next = messages.getOrNull(index + 1)
                    val prevKey = when {
                        prev?.role == "ai" -> "ai"
                        prev?.role == "user" -> "me"
                        else -> prev?.senderId?.ifEmpty { "peer" }
                    }
                    val nextKey = when {
                        next?.role == "ai" -> "ai"
                        next?.role == "user" -> "me"
                        else -> next?.senderId?.ifEmpty { "peer" }
                    }
                    val showHeader = prev == null || prevKey != senderKey ||
                        (msg.createdAt - prev.createdAt) > 5 * 60_000L
                    val showTime = next == null || nextKey != senderKey ||
                        (next.createdAt - msg.createdAt) > 5 * 60_000L
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .animateItem(
                                fadeInSpec = androidx.compose.animation.core.tween(250),
                                placementSpec = androidx.compose.animation.core.spring(0.6f, 400f)
                            )
                    ) {
                    ChatBubble(
                        msg = msg,
                        deviceName = deviceName,
                        peerName = peerName,
                        myDeviceId = myDeviceId,
                        playedMsgId = playingMsgId.value,
                        showHeader = showHeader,
                        showTime = showTime,
                        onPlayAudio = { audioData ->
                            playingMsgId.value = msg.id
                            voiceRecorder.play(audioData) {
                                playingMsgId.value = null
                            }
                        },
                        onRetry = { retryAi(it) },
                        onOpenFile = { file ->
                            previewFile = file
                        },
                        onLongPress = { actionMsg = it }
                    )
                    }
                }
                }   // 闭 LazyColumn
                // 用户上滚后显示「跳转到最新」浮动按钮（Box 内叠加层）
                androidx.compose.animation.AnimatedVisibility(
                    visible = !isAtBottom,
                    modifier = Modifier.align(Alignment.BottomEnd),
                    enter = androidx.compose.animation.fadeIn(androidx.compose.animation.core.tween(150)) +
                        androidx.compose.animation.slideInVertically { it / 2 },
                    exit = androidx.compose.animation.fadeOut(androidx.compose.animation.core.tween(120))
                ) {
                    Surface(
                        shape = RoundedCornerShape(AppRadius.floating),
                        color = AppColors.glass,
                        shadowElevation = 8.dp,
                        border = androidx.compose.foundation.BorderStroke(1.dp, AppColors.outline),
                        modifier = Modifier
                            .padding(end = 12.dp, bottom = 10.dp)
                            .clickable {
                                scope.launch { listState.animateScrollToItem(messages.size - 1) }
                            }
                    ) {
                        Text(
                            "↓ 跳转到最新",
                            color = AppColors.textPrimary,
                            fontSize = 11.sp,
                            modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp)
                        )
                    }
                }
            }
            // 输入区（语音/文本切换模式）
            Surface(color = AppColors.glass, tonalElevation = 4.dp) {
                Column(Modifier.fillMaxWidth().imePadding()) {
                    // ===== AI 模型选择（胶囊 → Bottom Sheet，仅 AI 会话） =====
                    if (aiOnly) {
                        var modelSheetVisible by remember { mutableStateOf(false) }
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp),
                            horizontalArrangement = Arrangement.Start,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            val curModel = ApiConfig.MODELS.firstOrNull { it.id == aiModel.value }
                            // 当前模型胶囊（点击弹 Sheet）
                            Surface(
                                shape = RoundedCornerShape(14.dp),
                                color = AppColors.primary.copy(alpha = 0.15f),
                                border = androidx.compose.foundation.BorderStroke(1.dp, AppColors.primary.copy(alpha = 0.35f)),
                                modifier = Modifier.clickable { modelSheetVisible = true }
                            ) {
                                Text(
                                    "${curModel?.name ?: "DeepSeek V4"} ▾",
                                    color = AppColors.primary,
                                    fontSize = 11.sp,
                                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp)
                                )
                            }
                            Spacer(Modifier.width(8.dp))
                            Text("切换模型", color = AppColors.textTertiary, fontSize = 10.sp)
                        }
                        // 模型选择 Bottom Sheet
                        if (modelSheetVisible) {
                            androidx.compose.material3.ModalBottomSheet(
                                onDismissRequest = { modelSheetVisible = false },
                                containerColor = AppColors.surface,
                                dragHandle = { Box(Modifier.padding(top = 10.dp).size(36.dp, 4.dp).background(AppColors.surfaceAlt, RoundedCornerShape(2.dp))) }
                            ) {
                                Column(Modifier.padding(bottom = 36.dp)) {
                                    Text("选择模型", color = AppColors.textPrimary, fontSize = 17.sp, fontWeight = FontWeight.SemiBold,
                                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 10.dp))
                                    ApiConfig.MODELS.forEach { m ->
                                        val selected = aiModel.value == m.id
                                        Row(
                                            Modifier.fillMaxWidth().clickable {
                                                selectModel(m.id)
                                                modelSheetVisible = false
                                            }.padding(horizontal = 20.dp, vertical = 14.dp),
                                            verticalAlignment = Alignment.CenterVertically
                                        ) {
                                            Icon(if (m.vision) Icons.Default.Visibility else Icons.Default.SmartToy, contentDescription = null, modifier = Modifier.size(20.dp))
                                            Spacer(Modifier.width(14.dp))
                                            Column(Modifier.weight(1f)) {
                                                Text(m.name, color = if (selected) AppColors.primary else AppColors.textPrimary, fontSize = 15.sp, fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal)
                                                Text(m.desc, color = AppColors.textTertiary, fontSize = 11.sp)
                                            }
                                            if (selected) Text("●", color = AppColors.primary, fontSize = 12.sp)
                                        }
                                        HorizontalDivider(color = AppColors.outline, modifier = Modifier.padding(horizontal = 20.dp))
                                    }
                                }
                            }
                        }
                    }
                    // ===== 微信式单行输入区：切换按钮 + 输入框/按住说话 + 附件 + 发送 =====
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        // 左侧：语音/文本切换按钮（圆形，点击切换）
                        if (!aiOnly) {
                            IconButton(
                                onClick = { voiceMode.value = !voiceMode.value },
                                modifier = Modifier.size(40.dp),
                                colors = IconButtonDefaults.iconButtonColors(
                                    contentColor = if (voiceMode.value) AppColors.primary else AppColors.textSecondary
                                )
                            ) {
                                Icon(if (voiceMode.value) Icons.Default.Keyboard else Icons.Default.Mic, contentDescription = if (voiceMode.value) "键盘" else "语音", modifier = Modifier.size(20.dp))
                            }
                        }

                        if (voiceMode.value && !aiOnly) {
                            // ===== 语音模式：按住说话胶囊（微信式，上滑取消） =====
                            Box(
                                modifier = Modifier
                                    .weight(1f)
                                    .height(44.dp)
                                    .clip(RoundedCornerShape(22.dp))
                                    .background(
                                        if (isRecording.value) AppColors.error else AppColors.surfaceAlt
                                    )
                                    .pointerInput(Unit) {
                                        awaitPointerEventScope {
                                            awaitFirstDown()
                                            startRecording()
                                            recordingOverlay.value = true
                                            recordingCancelZone.value = false
                                            try {
                                                // 跟踪手指移动：上滑超过阈值进入取消区
                                                while (true) {
                                                    val event = awaitPointerEvent()
                                                    val pos = event.changes.firstOrNull()?.position ?: break
                                                    // 屏幕上滑超过 120dp 视为取消区
                                                    val upThreshold = size.height * 0.25f
                                                    recordingCancelZone.value = pos.y < upThreshold
                                                    if ((event.changes.firstOrNull()?.pressed ?: false).not()) break
                                                }
                                                stopRecording(!recordingCancelZone.value)
                                            } catch (e: kotlinx.coroutines.CancellationException) {
                                                stopRecording(false)
                                            } finally {
                                                recordingOverlay.value = false
                                                recordingCancelZone.value = false
                                            }
                                        }
                                    },
                                contentAlignment = Alignment.Center
                            ) {
                                Text(
                                    when {
                                        isRecording.value -> "松开发送 · ${recordingDuration.value / 1000}s"
                                        peerConnected -> "按住说话"
                                        else -> "请先连接对端"
                                    },
                                    color = Color.White,
                                    fontSize = 14.sp,
                                    fontWeight = FontWeight.SemiBold
                                )
                            }
                        } else {
                            // ===== 文本模式：胶囊输入框（微信式） =====
                            OutlinedTextField(
                                value = input.value,
                                onValueChange = { input.value = it },
                                modifier = Modifier.weight(1f),
                                placeholder = {
                                    Text(
                                        if (aiEnabled.value) "向 AI 提问..." else if (peerConnected) "加密消息给 $peerName..." else "输入消息...",
                                        color = AppColors.textTertiary
                                    )
                                },
                                maxLines = 4,
                                shape = RoundedCornerShape(22.dp),
                                colors = textFieldColors(),
                                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
                                keyboardActions = KeyboardActions(onSend = { send() })
                            )
                            // 附件按钮（+号）
                            IconButton(
                                onClick = { filePicker.launch(arrayOf("*/*")) },
                                modifier = Modifier.size(40.dp),
                                colors = IconButtonDefaults.iconButtonColors(contentColor = AppColors.textSecondary)
                            ) {
                                Text("＋", fontSize = 22.sp, color = AppColors.textSecondary)
                            }
                            // 发送按钮（紫色圆形，微信式）
                            FilledIconButton(
                                onClick = {
                                    if (isSending.value && aiEnabled.value) stopAi() else send()
                                },
                                enabled = isSending.value || input.value.isNotBlank(),
                                modifier = Modifier.size(42.dp),
                                colors = IconButtonDefaults.filledIconButtonColors(
                                    containerColor = if (isSending.value) AppColors.error else AppColors.primary,
                                    contentColor = Color.White
                                )
                            ) {
                                if (isSending.value && aiEnabled.value) {
                                    Icon(Icons.Default.Close, contentDescription = "停止生成")
                                } else if (isSending.value) {
                                    CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = Color.White)
                                } else {
                                    Icon(Icons.Default.Send, contentDescription = "发送")
                                }
                            }
                        }
                    }
                    // 录音状态提示（语音模式，录音中显示）
                    if (voiceMode.value && !aiOnly && isRecording.value) {
                        Text(
                            "录音中 · 松开发送 · 上滑取消",
                            color = AppColors.error,
                            fontSize = 10.sp,
                            textAlign = TextAlign.Center,
                            modifier = Modifier.fillMaxWidth().padding(bottom = 4.dp)
                        )
                    }
                }
            }
        }
    }

    // ===== 微信式录音浮层（绿色气泡 + 松手发语音 + 上滑取消） =====
    if (recordingOverlay.value) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color(0x33000000))
                .clickable(enabled = false) { },
            contentAlignment = Alignment.Center
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                // 顶部的取消提示（上滑进入取消区后显示）
                if (recordingCancelZone.value) {
                    Surface(
                        shape = RoundedCornerShape(12.dp),
                        color = Color(0xCCE53935),
                        modifier = Modifier.padding(bottom = 24.dp)
                    ) {
                        Text(
                            "松开 取消",
                            color = Color.White, fontSize = 13.sp,
                            modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp)
                        )
                    }
                }
                // 绿色语音气泡（微信风格）
                Surface(
                    shape = RoundedCornerShape(20.dp),
                    color = if (recordingCancelZone.value) Color(0xFFE53935) else Color(0xFF07C160),
                    shadowElevation = 8.dp
                ) {
                    Column(
                        Modifier.padding(horizontal = 40.dp, vertical = 32.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        // 语音波形图标（近似微信风格）
                        Text(
                            when {
                                recordingCancelZone.value -> ""
                                else -> ""
                            },
                            fontSize = 36.sp
                        )
                        Spacer(Modifier.height(12.dp))
                        Text(
                            if (recordingCancelZone.value) "松开 取消" else "松手 发语音",
                            color = Color.White,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Bold
                        )
                        Spacer(Modifier.height(8.dp))
                        Text(
                            "${recordingDuration.value / 1000}s",
                            color = Color.White.copy(alpha = 0.7f),
                            fontSize = 12.sp
                        )
                    }
                }
            }
        }
    }

    // ===== 消息长按操作 Sheet（复制 / 删除） =====
    actionMsg?.let { am ->
        androidx.compose.material3.ModalBottomSheet(
            onDismissRequest = { actionMsg = null },
            containerColor = AppColors.surface,
            dragHandle = { Box(Modifier.padding(top = 10.dp).size(36.dp, 4.dp).background(AppColors.surfaceAlt, RoundedCornerShape(2.dp))) }
        ) {
            Column(Modifier.padding(bottom = 36.dp)) {
                Text(
                    if (am.text.isNotEmpty()) am.text.take(40) + if (am.text.length > 40) "…" else "" else if (am.file != null) am.file.name else "消息",
                    color = AppColors.textSecondary,
                    fontSize = 13.sp,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(horizontal = 20.dp, vertical = 10.dp)
                )
                HorizontalDivider(color = AppColors.outline)
                // 复制
                Row(
                    Modifier.fillMaxWidth().clickable {
                        val cm = context.getSystemService(android.content.Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
                        cm.setPrimaryClip(android.content.ClipData.newPlainText("msg", am.text))
                        Toast.makeText(context, "已复制", Toast.LENGTH_SHORT).show()
                        actionMsg = null
                    }.padding(horizontal = 20.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Default.ContentCopy, contentDescription = null, tint = AppColors.textPrimary, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(14.dp))
                    Text("复制", color = AppColors.textPrimary, fontSize = 15.sp)
                }
                // 转发（仅对端会话，AI 消息不转发）
                if (!aiOnly && am.text.isNotEmpty()) {
                    HorizontalDivider(color = AppColors.outline)
                    Row(
                        Modifier.fillMaxWidth().clickable {
                            Toast.makeText(context, "转发功能开发中", Toast.LENGTH_SHORT).show()
                            actionMsg = null
                        }.padding(horizontal = 20.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(Icons.Default.Share, contentDescription = null, tint = AppColors.textPrimary, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(14.dp))
                        Text("转发", color = AppColors.textPrimary, fontSize = 15.sp)
                    }
                }
                // 删除
                HorizontalDivider(color = AppColors.outline)
                Row(
                    Modifier.fillMaxWidth().clickable {
                        onDeleteMsg?.invoke(am.id)
                        actionMsg = null
                        Toast.makeText(context, "已删除", Toast.LENGTH_SHORT).show()
                    }.padding(horizontal = 20.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Default.Delete, contentDescription = null, tint = AppColors.error, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(14.dp))
                    Text("删除", color = AppColors.error, fontSize = 15.sp)
                }
            }
        }
    }

    // ===== 会话信息面板（顶部 ℹ️ 查看更多信息） =====
    if (sessionInfoVisible) {
        androidx.compose.material3.ModalBottomSheet(
            onDismissRequest = { sessionInfoVisible = false },
            containerColor = AppColors.surface,
            dragHandle = { Box(Modifier.padding(top = 10.dp).size(36.dp, 4.dp).background(AppColors.surfaceAlt, RoundedCornerShape(2.dp))) }
        ) {
            Column(Modifier.padding(start = 20.dp, end = 20.dp, bottom = 36.dp)) {
                // 会话身份区
                Row(verticalAlignment = Alignment.CenterVertically) {
                    AvatarCircle(
                        name = if (aiOnly) "AI 助手" else peerName.ifEmpty { "对端" },
                        size = 52.dp
                    )
                    Spacer(Modifier.width(14.dp))
                    Column {
                        Text(
                            if (aiOnly) "AI 助手" else peerName.ifEmpty { "对端" },
                            color = AppColors.textPrimary,
                            fontSize = 17.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                        Spacer(Modifier.height(3.dp))
                        Text(
                            if (aiOnly) "云端 AI · 非端到端加密"
                            else "ID: ${if (peerDeviceId.isNotEmpty()) peerDeviceId else "未连接"}",
                            color = AppColors.textTertiary,
                            fontSize = 12.sp,
                            fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
                        )
                    }
                }
                Spacer(Modifier.height(18.dp))
                HorizontalDivider(color = AppColors.outline)
                Spacer(Modifier.height(6.dp))

                if (aiOnly) {
                    // ===== AI 会话信息 =====
                    val curModel = ApiConfig.MODELS.firstOrNull { it.id == aiModel.value }
                    SettingRow("", "当前模型", curModel?.name ?: "DeepSeek V4", onClick = {})
                    SettingRow("", "加密说明", "AI 对话经云端中继代理，非端到端加密", onClick = {})
                    SettingRow("", "清除对话", "清空当前 AI 会话历史", onClick = {
                        messages.clear()
                        sessionInfoVisible = false
                        Toast.makeText(context, "AI 对话已清空", Toast.LENGTH_SHORT).show()
                    })
                } else {
                    // ===== 对端会话信息 =====
                    SettingRow("", "复制对方 ID", DeviceIdentity.shortId(peerDeviceId), onClick = {
                        val cm = context.getSystemService(android.content.Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
                        cm.setPrimaryClip(android.content.ClipData.newPlainText("peerId", peerDeviceId))
                        Toast.makeText(context, "对方 ID 已复制", Toast.LENGTH_SHORT).show()
                    })
                    SettingRow(
                        "", "连接状态",
                        if (peerConnected) "● 已连接" else "○ 未连接",
                        valueColor = if (peerConnected) AppColors.success else AppColors.textTertiary,
                        onClick = {}
                    )
                    SettingRow("", "加密说明", "端到端加密 · 消息仅双方可见", onClick = {})
                    SettingRow("", "删除会话", "清空与对方的聊天记录", onClick = {
                        messages.clear()
                        sessionInfoVisible = false
                        Toast.makeText(context, "会话已清空", Toast.LENGTH_SHORT).show()
                    })
                }
            }
        }
    }
    }
}

@Composable
fun ModeChip(text: String, selected: Boolean, onClick: () -> Unit) {
    Text(
        text,
        modifier = Modifier
            .clip(RoundedCornerShape(16.dp))
            .background(
                if (selected) AppGradients.primary
                else Brush.linearGradient(listOf(Color.Transparent, Color.Transparent))
            )
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 5.dp),
        color = if (selected) Color.White else AppColors.textSecondary,
        fontSize = 12.sp,
        fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal
    )
}

@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
fun ChatBubble(
    msg: UiMessage,
    deviceName: String,
    peerName: String,
    myDeviceId: String,
    playedMsgId: String?,
    onPlayAudio: ((ByteArray) -> Unit)? = null,
    onRetry: ((String) -> Unit)? = null,
    onOpenFile: ((UiFile) -> Unit)? = null,
    onLongPress: ((UiMessage) -> Unit)? = null,
    showHeader: Boolean = true,   // 是否显示头像+昵称（同发送者合并：仅组首条 true）
    showTime: Boolean = true      // 是否显示时间（仅组末条 true）
) {
    val context = LocalContext.current
    val isAi = msg.role == "ai"
    // 双视角核心：用设备唯一 ID 判断是否本人消息（不再靠 role/名字）
    val isMine = msg.senderId == myDeviceId || msg.role == "user"
    val showName = if (isAi) "AI 助手" else if (isMine) deviceName else (msg.senderName.ifEmpty { peerName.ifEmpty { "对端" } })

    val bgColor = when {
        isMine && !isAi -> AppColors.bubbleMine
        isAi -> AppColors.bubbleAi
        else -> AppColors.bubblePeer
    }
    val fgColor = when {
        isMine && !isAi -> Color.White
        isAi -> AppColors.bubbleAiText
        else -> AppColors.bubblePeerText
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 1.dp)
            .then(
                if (onLongPress != null) Modifier.combinedClickable(
                    onClick = {},
                    onLongClick = { onLongPress(msg) }
                ) else Modifier
            )
    ) {
        // 左竖列 44dp：对方头像（恒占位，保证气泡不越过该列；同发送者合并时隐藏头像仅留空位）
        Box(
            modifier = Modifier.width(44.dp),
            contentAlignment = Alignment.TopStart
        ) {
            if (!isMine && showHeader) {
                AvatarCircle(name = showName, size = 36.dp, modifier = Modifier.padding(end = 8.dp))
            }
        }
        Column(
            horizontalAlignment = if (isMine) Alignment.End else Alignment.Start,
            modifier = Modifier.weight(1f)   // fill=true：占满中列，气泡绝不越过两侧头像竖列
        ) {
            // 发送者名称（同发送者合并：仅组首条显示）
            if (showHeader) {
                Text(
                    if (isMine) "我 · $deviceName" else showName,
                    fontSize = 10.sp,
                    color = if (isAi) AppColors.info else if (isMine) AppColors.primary else AppColors.textSecondary,
                    modifier = Modifier.padding(start = 4.dp, bottom = 3.dp)
                )
            }
            // 气泡（自己=渐变紫，对方=深灰+描边）
            Box(
                modifier = Modifier
                    .widthIn(max = if (isAi) 340.dp else 280.dp)
                    .clip(
                        RoundedCornerShape(
                            topStart = if (isMine) 16.dp else 4.dp,
                            topEnd = if (isMine) 4.dp else 16.dp,
                            bottomStart = 16.dp,
                            bottomEnd = 16.dp
                        )
                    )
                    .background(
                        // 自己=纯色紫（克制），AI/对方=纯色 surface（Document Style 极轻）
                        bgColor
                    )
                    .then(
                        if (!isMine && !isAi) Modifier.border(
                            1.dp, AppColors.outlineStrong,
                            RoundedCornerShape(
                                topStart = 4.dp, topEnd = 16.dp,
                                bottomStart = 16.dp, bottomEnd = 16.dp
                            )
                        ) else Modifier
                    )
            ) {
                Column(Modifier.padding(horizontal = 12.dp, vertical = 10.dp)) {
                    // 文件传输进度（进行中）
                    if (msg.progress >= 0f && msg.progress < 1f) {
                        Column(Modifier.fillMaxWidth()) {
                            Text(msg.text, color = fgColor, fontSize = 13.sp)
                            Spacer(Modifier.height(8.dp))
                            LinearProgressIndicator(
                                progress = { msg.progress.coerceIn(0f, 1f) },
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .height(6.dp)
                                    .clip(RoundedCornerShape(3.dp)),
                                color = AppColors.primary,
                                trackColor = AppColors.surfaceAlt
                            )
                            Spacer(Modifier.height(4.dp))
                            Text(
                                "${(msg.progress * 100).toInt()}%",
                                color = AppColors.textSecondary,
                                fontSize = 11.sp,
                                modifier = Modifier.fillMaxWidth(),
                                textAlign = TextAlign.End
                            )
                        }
                    }
                    // 图片消息 → 缩略图
                    if (msg.file?.mime?.startsWith("image/") == true) {
                        val data = msg.file.data
                        if (data != null) {
                            val bitmap = remember(data) { decodeBitmap(data, 600) }
                            if (bitmap != null) {
                                Image(
                                    bitmap = bitmap.asImageBitmap(),
                                    contentDescription = msg.file.name,
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .heightIn(max = 240.dp)
                                        .clip(RoundedCornerShape(12.dp))
                                        .clickable { onOpenFile?.invoke(msg.file) },
                                    contentScale = ContentScale.Fit
                                )
                            }
                        }
                        Spacer(Modifier.height(6.dp))
                        Text("[图片] ${msg.file.name}", color = fgColor, fontSize = 12.sp)
                    }
                    // 视频消息 → 缩略图 + 播放按钮
                    else if (msg.file?.mime?.startsWith("video/") == true) {
                        val data = msg.file.data
                        if (data != null) {
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .height(180.dp)
                                    .clip(RoundedCornerShape(12.dp))
                                    .background(Color.Black)
                                    .clickable { onOpenFile?.invoke(msg.file) },
                                contentAlignment = Alignment.Center
                            ) {
                                // 视频首帧缩略图
                                val thumb = remember(data) { extractVideoFrame(data, context) }
                                if (thumb != null) {
                                    Image(
                                        bitmap = thumb.asImageBitmap(),
                                        contentDescription = null,
                                        modifier = Modifier.fillMaxSize(),
                                        contentScale = ContentScale.Crop
                                    )
                                }
                                // 播放按钮
                                Surface(
                                    shape = RoundedCornerShape(28.dp),
                                    color = AppColors.scrim
                                ) {
                                    Text("▶", fontSize = 28.sp, color = Color.White, modifier = Modifier.padding(12.dp))
                                }
                            }
                        }
                        Spacer(Modifier.height(6.dp))
                        Text("[视频] ${msg.file.name}", color = fgColor, fontSize = 12.sp)
                    }
                    // 语音消息
                    else if (msg.audio != null) {
                        VoiceBubble(msg, playedMsgId, fgColor, onPlayAudio)
                    }
                    // 文件消息 → 图标 + 名称
                    else if (msg.file != null) {
                        FileRow(msg.file, fgColor) { onOpenFile?.invoke(msg.file) }
                    }
                    // 普通文本
                    else {
                        // AI 思考过程（reasoning_content）— 灰色小字折叠显示
                        if (isAi && msg.reasoning.isNotEmpty()) {
                            var showReasoning by remember { mutableStateOf(false) }
                            Column(Modifier.fillMaxWidth()) {
                                Text(
                                    text = if (msg.text.isEmpty()) "思考过程"
                                    else "思考过程 ${if (showReasoning) "▾" else "▸"}",
                                    color = AppColors.textTertiary,
                                    fontSize = 11.sp,
                                    modifier = Modifier
                                        .clickable { showReasoning = !showReasoning }
                                        .padding(vertical = 2.dp)
                                )
                                if (showReasoning) {
                                    Spacer(Modifier.height(2.dp))
                                    Text(
                                        text = msg.reasoning,
                                        color = AppColors.textTertiary,
                                        fontSize = 12.sp,
                                        lineHeight = 17.sp
                                    )
                                    Spacer(Modifier.height(6.dp))
                                    Box(
                                        Modifier
                                            .fillMaxWidth()
                                            .height(1.dp)
                                            .background(AppColors.outlineStrong)
                                    )
                                    Spacer(Modifier.height(6.dp))
                                }
                            }
                        }
                        if (isAi) {
                            // AI 消息：非端到端加密徽标（视觉区分，仅组首条显示）
                            if (showHeader) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Surface(
                                        shape = RoundedCornerShape(6.dp),
                                        color = AppColors.primary.copy(alpha = 0.12f),
                                        border = androidx.compose.foundation.BorderStroke(0.5.dp, AppColors.primary.copy(alpha = 0.3f))
                                    ) {
                                        Text(
                                            "云端 AI",
                                            color = AppColors.primary,
                                            fontSize = 9.sp,
                                            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                                        )
                                    }
                                    Spacer(Modifier.width(6.dp))
                                    Text("非端到端加密", color = AppColors.textTertiary, fontSize = 9.sp)
                                }
                                Spacer(Modifier.height(4.dp))
                            }
                            // AI 消息：Document Style 富文本渲染（Markdown/代码/表格/列表）
                            // AI 生成中 → 显示 Lottie 思考动画
                            if (isAi && msg.text.isEmpty()) {
                                top.vios.chat.ui.EvoLottieView(
                                    rawResId = top.vios.chat.R.raw.ai_thinking,
                                    modifier = Modifier.size(48.dp)
                                )
                            }
                            if (msg.text.isNotEmpty()) {
                                RichMessageContent(text = msg.text, baseColor = fgColor)
                            }
                        } else {
                            Text(
                                text = msg.text.ifEmpty { "…" },
                                color = fgColor,
                                fontSize = 15.sp,
                                lineHeight = 21.sp
                            )
                        }
                    }
                    // AI 错误重试
                    if (msg.isError && msg.audio == null && msg.file == null) {
                        Spacer(Modifier.height(6.dp))
                        Text(
                            "↻ 重新发送",
                            color = AppColors.primary,
                            fontSize = 12.sp,
                            modifier = Modifier
                                .clickable { onRetry?.invoke(msg.id) }
                                .padding(vertical = 4.dp)
                        )
                    }
                }
            }
            // 时间（同发送者合并：仅组末条显示）
            if (showTime) {
                Text(
                    SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(msg.createdAt)),
                    fontSize = 9.sp,
                    color = AppColors.textTertiary,
                    modifier = Modifier.padding(top = 2.dp, end = 4.dp)
                )
            }
        }
        // 右竖列 44dp：自己头像（恒占位，气泡不越过该列；合并时隐藏头像仅留空位）
        Box(
            modifier = Modifier.width(44.dp),
            contentAlignment = Alignment.TopEnd
        ) {
            if (isMine && showHeader) {
                AvatarCircle(name = deviceName, size = 36.dp, modifier = Modifier.padding(start = 8.dp))
            }
        }
    }
}

/** 语音气泡 */
@Composable
fun VoiceBubble(
    msg: UiMessage,
    playedMsgId: String?,
    fgColor: Color,
    onPlayAudio: ((ByteArray) -> Unit)?
) {
    val isPlaying = playedMsgId == msg.id
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.clickable {
            if (!isPlaying) onPlayAudio?.invoke(msg.audio!!)
        }.padding(4.dp)
    ) {
        Text(if (isPlaying) "⏹" else "▶️", fontSize = 24.sp)
        Spacer(Modifier.width(12.dp))
        // 波形
        Surface(shape = RoundedCornerShape(4.dp), color = AppColors.surfaceAlt, modifier = Modifier.width(80.dp).height(32.dp)) {
            Row(
                Modifier.fillMaxSize().padding(horizontal = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceEvenly
            ) {
                repeat(8) {
                    val h = (8 + kotlin.math.abs(it - 4) * 6).dp
                    Box(
                        Modifier
                            .width(4.dp)
                            .height(if (isPlaying) h else 8.dp)
                            .background(if (isPlaying) AppColors.primary else AppColors.textTertiary, RoundedCornerShape(2.dp))
                    )
                }
            }
        }
        Spacer(Modifier.width(10.dp))
        val audio = msg.audio
        Text("${(audio?.size ?: 0) / 1024} KB", color = fgColor, fontSize = 12.sp)
    }
}

/** 文件消息行 */
@Composable
fun FileRow(file: UiFile, fgColor: Color, onClick: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .clip(RoundedCornerShape(10.dp))
            .background(AppColors.scrimLight)
            .clickable(onClick = onClick)
            .padding(10.dp)
    ) {
        // 文件类型图标（Material Symbols，无 emoji）
        val icon = when {
            file.mime.startsWith("image/") -> Icons.Default.Image
            file.mime.startsWith("video/") -> Icons.Default.Movie
            file.mime.startsWith("audio/") -> Icons.Default.MusicNote
            file.mime.contains("pdf") -> Icons.Default.Description
            file.mime.contains("zip") || file.mime.contains("rar") -> Icons.Default.FolderZip
            file.mime.contains("word") || file.name.endsWith(".docx") || file.name.endsWith(".doc") -> Icons.Default.Description
            file.mime.contains("sheet") || file.name.endsWith(".xlsx") || file.name.endsWith(".xls") -> Icons.Default.TableChart
            file.name.endsWith(".txt") || file.name.endsWith(".md") -> Icons.Default.Article
            else -> Icons.Default.Folder
        }
        Icon(icon, contentDescription = null, tint = AppColors.textSecondary, modifier = Modifier.size(28.dp))
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Text(file.name, color = fgColor, fontSize = 13.sp, maxLines = 2)
            Text(formatFileSize(file.size), color = AppColors.textSecondary, fontSize = 11.sp)
        }
        Icon(Icons.Default.Visibility, contentDescription = null, tint = AppColors.textSecondary, modifier = Modifier.size(14.dp))
    }
}

/** 圆形头像（首字母 + 稳定品牌色，无 emoji，与 iOS 一致） */
@Composable
fun AvatarCircle(name: String, size: androidx.compose.ui.unit.Dp, modifier: Modifier = Modifier) {
    val letter = AvatarManager.getLetter(name)
    val bgColor = AvatarManager.getBackgroundColor(name)
    val fgColor = AvatarManager.getForegroundColor(name)
    Box(
        modifier = modifier
            .size(size)
            .background(Color(bgColor), CircleShape)
            .clip(CircleShape),
        contentAlignment = Alignment.Center
    ) {
        Text(letter, fontSize = (size.value * 0.45).sp, fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold,
            color = Color(fgColor))
    }
}

/** 解码图片字节为 Bitmap */
fun decodeBitmap(data: ByteArray, maxSize: Int = 800): android.graphics.Bitmap? {
    return try {
        val opts = android.graphics.BitmapFactory.Options().apply { inJustDecodeBounds = true }
        android.graphics.BitmapFactory.decodeByteArray(data, 0, data.size, opts)
        var sample = 1
        while (opts.outWidth / sample > maxSize || opts.outHeight / sample > maxSize) {
            sample *= 2
        }
        val decodeOpts = android.graphics.BitmapFactory.Options().apply { inSampleSize = sample }
        android.graphics.BitmapFactory.decodeByteArray(data, 0, data.size, decodeOpts)
    } catch (_: Exception) { null }
}

/** 提取视频首帧（context 从调用处传入） */
fun extractVideoFrame(data: ByteArray, context: Context): android.graphics.Bitmap? {
    return try {
        val tmp = File(context.cacheDir, "thumb_${System.currentTimeMillis()}.mp4")
        tmp.writeBytes(data)
        val retriever = android.media.MediaMetadataRetriever()
        retriever.setDataSource(tmp.absolutePath)
        val frame = retriever.getFrameAtTime(1000, android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
        retriever.release()
        tmp.delete()
        frame
    } catch (_: Exception) { null }
}

fun formatFileSize(bytes: Long): String {
    return when {
        bytes >= 1024 * 1024 * 1024 -> String.format("%.1f GB", bytes / 1024.0 / 1024 / 1024)
        bytes >= 1024 * 1024 -> String.format("%.1f MB", bytes / 1024.0 / 1024)
        bytes >= 1024 -> String.format("%.1f KB", bytes / 1024.0)
        else -> "$bytes B"
    }
}