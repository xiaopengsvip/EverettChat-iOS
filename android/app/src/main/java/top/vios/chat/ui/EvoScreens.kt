package top.vios.chat.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import top.vios.chat.AppColors
import top.vios.chat.BuildConfig
import top.vios.chat.AppSpacing
import top.vios.chat.Contact
import top.vios.chat.Conversation

// ============================================================
// EVO 四主 Tab 页面（Material3 原生，与 iOS 结构一致）
// ============================================================

/** 消息页：AI 助手 + 对端会话列表（对应 iOS MessagesView） */
@Composable
fun EvoMessagesScreen(
    conversations: List<Conversation>,
    aiLastText: String = "",
    aiGenerating: Boolean = false,
    deviceLastText: String = "",
    deviceHasMessages: Boolean = false,
    onlineDeviceIds: Set<String> = emptySet(),
    onOpenAI: () -> Unit,
    onOpenDevice: () -> Unit,
    onOpenConversation: (Conversation) -> Unit,
    onAddFriend: () -> Unit
) {
    Column(Modifier.fillMaxSize().background(AppColors.bg)) {
        EvoTopBar(
            title = "消息",
            actions = {
                EvoIconButton(Icons.Filled.Add, "添加好友", onClick = onAddFriend)
            }
        )
        LazyColumn(Modifier.fillMaxSize()) {
            item {
                EvoConversationRow(
                    avatarName = "AI",
                    title = "AI 助手",
                    subtitle = when {
                        aiGenerating -> "正在生成…"
                        aiLastText.isNotEmpty() -> aiLastText
                        else -> "开始聊天吧"
                    },
                    timeText = if (aiLastText.isNotEmpty()) "现在" else "",
                    accent = true,
                    onClick = onOpenAI
                )
            }
            item {
                EvoConversationRow(
                    avatarName = "H",
                    title = "Hermes 设备",
                    subtitle = deviceLastText.ifEmpty { "开始使用 Hermes 设备互联" },
                    timeText = if (deviceHasMessages) "刚刚" else "",
                    accent = false,
                    avatarColor = AppColors.surfaceAlt,
                    onClick = onOpenDevice
                )
            }
            val peerConvs = conversations
                .filter { it.type != "ai" }
                .groupBy { it.name }
                .map { (_, group) -> group.maxBy { it.lastTime } }
                .sortedByDescending { it.lastTime }
            if (peerConvs.isEmpty()) {
                item {
                    EvoEmptyState(
                        icon = Icons.Filled.Message,
                        title = "还没有聊天记录",
                        subtitle = "在「发现」连接设备，或在「通讯录」添加好友后开始加密聊天"
                    )
                }
            } else {
                items(peerConvs) { conv ->
                    EvoConversationRow(
                        avatarName = conv.name,
                        title = conv.name,
                        subtitle = conv.lastText.ifEmpty { "开始聊天吧" },
                        timeText = formatEvoTime(conv.lastTime),
                        unread = conv.unread,
                        isOnline = conv.id in onlineDeviceIds,
                        onClick = { onOpenConversation(conv) }
                    )
                }
            }
        }
    }
}

/** 通讯录页（内部自取在线用户，Material3 原生） */
@Composable
fun EvoContactsScreen(
    deviceName: String,
    myDeviceId: String,
    relayHttp: String,
    contacts: List<Contact>,
    onAddFriend: () -> Unit = {},
    onAddContact: (id: String, name: String) -> Unit = { _, _ -> },
    onOpenChat: (id: String, name: String) -> Unit = { _, _ -> }
) {
    var searchQuery by remember { mutableStateOf("") }
    var onlineUsers by remember { mutableStateOf<List<Pair<String, String>>>(emptyList()) }
    LaunchedEffect(Unit) {
        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
            try {
                val base = if (relayHttp.isNotBlank()) relayHttp.trimEnd('/') else "https://relay.vios.top"
                val conn = java.net.URL("$base/users").openConnection() as java.net.HttpURLConnection
                conn.connectTimeout = 6000; conn.readTimeout = 6000
                val resp = conn.inputStream.bufferedReader().use { it.readText() }
                val arr = org.json.JSONObject(resp).optJSONArray("users") ?: org.json.JSONArray()
                val list = mutableListOf<Pair<String, String>>()
                for (i in 0 until arr.length()) {
                    val u = arr.getJSONObject(i)
                    val id = u.optString("deviceId", ""); if (id != myDeviceId) list.add(id to u.optString("name", ""))
                }
                onlineUsers = list
            } catch (_: Exception) {}
        }
    }
    val filteredUsers = if (searchQuery.isEmpty()) onlineUsers else onlineUsers.filter { it.second.contains(searchQuery) }
    val filteredContacts = if (searchQuery.isEmpty()) contacts else contacts.filter { it.name.contains(searchQuery) }

    Column(Modifier.fillMaxSize().background(AppColors.bg)) {
        EvoTopBar(title = "通讯录", actions = {
            EvoIconButton(Icons.Filled.Add, "添加好友", onClick = onAddFriend)
        })
        EvoSearchBar(searchQuery, { searchQuery = it }, "搜索联系人")
        LazyColumn(Modifier.fillMaxSize()) {
            item {
                Row(Modifier.fillMaxWidth().padding(horizontal = AppSpacing.lg, vertical = AppSpacing.md),
                    verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(44.dp).background(AppColors.surfaceAlt, CircleShape), contentAlignment = Alignment.Center) {
                        Icon(Icons.Filled.Person, contentDescription = null, tint = AppColors.textSecondary, modifier = Modifier.size(22.dp))
                    }
                    Spacer(Modifier.width(AppSpacing.md))
                    Column {
                        Text(deviceName, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = AppColors.textPrimary)
                        Text("我的 ID: ${myDeviceId.take(8)}", fontSize = 12.sp, color = AppColors.textTertiary)
                    }
                }
            }
            item { HorizontalDivider(color = AppColors.outline, thickness = 0.5.dp) }
            item { Text("我的联系人 (${filteredContacts.size})", fontSize = 12.sp, color = AppColors.textTertiary, modifier = Modifier.padding(horizontal = AppSpacing.lg, vertical = AppSpacing.sm)) }
            if (filteredContacts.isEmpty()) {
                item { Text("暂无联系人，添加后可长期通信", fontSize = 12.sp, color = AppColors.textTertiary, modifier = Modifier.padding(AppSpacing.lg)) }
            }
            items(filteredContacts) { c ->
                EvoConversationRow(avatarName = c.name, title = c.name, subtitle = "ID: ${c.deviceId.take(8)}", timeText = "",
                    onClick = { onOpenChat(c.deviceId, c.name) })
            }
            if (filteredUsers.isNotEmpty()) {
                item { Text("在线用户", fontSize = 12.sp, color = AppColors.textTertiary, modifier = Modifier.padding(horizontal = AppSpacing.lg, vertical = AppSpacing.sm)) }
                items(filteredUsers) { (id, name) ->
                    Row(Modifier.fillMaxWidth().padding(horizontal = AppSpacing.lg, vertical = AppSpacing.md),
                        verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(40.dp).background(AppColors.surfaceAlt, CircleShape), contentAlignment = Alignment.Center) {
                            Icon(Icons.Filled.Person, contentDescription = null, tint = AppColors.textSecondary, modifier = Modifier.size(20.dp))
                        }
                        Spacer(Modifier.width(AppSpacing.md))
                        Column(Modifier.weight(1f)) {
                            Text(name, fontSize = 15.sp, color = AppColors.textPrimary)
                            Text("ID: ${id.take(8)}", fontSize = 12.sp, color = AppColors.textTertiary)
                        }
                        TextButton(onClick = { onAddContact(id, name) }) { Text("添加", fontSize = 13.sp, color = AppColors.primary) }
                    }
                }
            }
        }
    }
}

/** 发现页 */
@Composable
fun EvoDiscoverScreen(
    onGame: () -> Unit, onFileTransfer: () -> Unit, onDeviceLink: () -> Unit,
    onLan: () -> Unit, onRelay: () -> Unit, onBluetooth: () -> Unit,
    onTopology: () -> Unit, onMyQr: () -> Unit, onScan: () -> Unit
) {
    Column(Modifier.fillMaxSize().background(AppColors.bg)) {
        EvoTopBar(title = "发现")
        LazyColumn(Modifier.fillMaxSize()) {
            item { SectionHeader("功能") }
            item { EvoFeatureRow(Icons.Filled.SportsEsports, "游戏中心", "game.vios.top", onGame) }
            item { EvoFeatureRow(Icons.Filled.SwapHoriz, "文件互传", "NFC 碰一碰 / 蓝牙 / 局域网", onFileTransfer) }
            item { EvoFeatureRow(Icons.Filled.DesktopWindows, "设备互联", "连接本机 Hermes AI 助手", onDeviceLink) }
            item { SectionHeader("网络") }
            item { EvoFeatureRow(Icons.Filled.Wifi, "局域网直连", "同一 Wi-Fi · 配对码/扫描", onLan) }
            item { EvoFeatureRow(Icons.Filled.Cloud, "云中继", "公网跨网络 · 在线设备", onRelay) }
            item { EvoFeatureRow(Icons.Filled.Bluetooth, "蓝牙直连", "近距离 · 无需 Wi-Fi", onBluetooth) }
            item { EvoFeatureRow(Icons.Filled.AccountTree, "中继网可视化", "实时拓扑 / 在线用户", onTopology) }
            item { SectionHeader("更多") }
            item { EvoFeatureRow(Icons.Filled.QrCode, "我的二维码", "扫码互加好友", onMyQr) }
            item { EvoFeatureRow(Icons.Filled.QrCodeScanner, "扫一扫", "扫描二维码添加好友", onScan) }
        }
    }
}

/** 设置页 */
@Composable
fun EvoMineScreen(
    deviceName: String, deviceId: String,
    onProfileEdit: () -> Unit, onAppearance: () -> Unit, onDeviceSettings: () -> Unit,
    onStorage: () -> Unit, onIdentity: () -> Unit, onAbout: () -> Unit,
    onCheckUpdate: () -> Unit = {},
    debugMode: Boolean = false, onDebugModeChanged: (Boolean) -> Unit = {}
) {
    Column(Modifier.fillMaxSize().background(AppColors.bg)) {
        EvoTopBar(title = "我的")
        LazyColumn(Modifier.fillMaxSize()) {
            item {
                Row(Modifier.fillMaxWidth().clickable(onClick = onProfileEdit).padding(horizontal = AppSpacing.lg, vertical = AppSpacing.lg),
                    verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(56.dp).background(AppColors.primaryDim, CircleShape), contentAlignment = Alignment.Center) {
                        Icon(Icons.Filled.Person, contentDescription = null, tint = AppColors.primary, modifier = Modifier.size(28.dp))
                    }
                    Spacer(Modifier.width(AppSpacing.md))
                    Column {
                        Text(deviceName, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = AppColors.textPrimary)
                        Spacer(Modifier.height(2.dp))
                        Text("唯一 ID: ${deviceId.take(8)}", fontSize = 12.sp, color = AppColors.textSecondary)
                    }
                }
            }
            item { HorizontalDivider(color = AppColors.outline, thickness = 0.5.dp) }
            item { SectionHeader("外观") }
            item { EvoSettingsRow(Icons.Filled.Palette, "主题外观", "跟随系统 / 珍珠白 / 深邃黑", onAppearance) }
            item { SectionHeader("设备与通用") }
            item { EvoSettingsRow(Icons.Filled.Devices, "设备管理", "音频设备 / 蓝牙 / Hermes", onDeviceSettings) }
            item { EvoSettingsRow(Icons.Filled.Storage, "存储管理", "清理缓存与媒体文件", onStorage) }
            item { SectionHeader("身份") }
            item { EvoSettingsRow(Icons.Filled.Security, "身份与恢复密钥", "恢复密钥 / 换机迁移", onIdentity) }
            item { SectionHeader("开发者") }
            item {
                Row(
                    Modifier.fillMaxWidth().clickable { onDebugModeChanged(!debugMode) }
                        .padding(horizontal = AppSpacing.lg, vertical = AppSpacing.md),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Filled.BugReport, contentDescription = null, tint = AppColors.primary,
                        modifier = Modifier.size(22.dp))
                    Spacer(Modifier.width(AppSpacing.md))
                    Column(Modifier.weight(1f)) {
                        Text("调试模式", fontSize = 15.sp, fontWeight = FontWeight.Medium, color = AppColors.textPrimary)
                        Text(if (debugMode) "已开启 · 显示调试通道（EVO 测试通道）" else "关闭 · 调试通道不可见",
                            fontSize = 11.sp, color = AppColors.textTertiary)
                    }
                    androidx.compose.material3.Switch(
                        checked = debugMode,
                        onCheckedChange = { onDebugModeChanged(it) },
                        colors = androidx.compose.material3.SwitchDefaults.colors(
                            checkedThumbColor = AppColors.primary
                        )
                    )
                }
            }
            item { SectionHeader("关于") }
            item { EvoSettingsRow(Icons.Filled.Info, "关于 EVO", "版本与开发者信息", onAbout) }
            item { EvoSettingsRow(Icons.Filled.SystemUpdate, "检测更新", "检查中继网是否有新版本", onCheckUpdate) }
            item {
                // 版本信息（应用版本 / 系统版本 / OS 版本）
                val osVer = android.os.Build.VERSION.RELEASE ?: "?"
                val sdk = android.os.Build.VERSION.SDK_INT
                val sdkName = when (sdk) {
                    33 -> "13"; 34 -> "14"; 35 -> "15"; 36 -> "16"; 37 -> "17"
                    else -> sdk.toString()
                }
                Column(Modifier.padding(horizontal = AppSpacing.lg, vertical = AppSpacing.sm)) {
                    Text("EVO ${BuildConfig.VERSION_NAME} · $deviceName · ${deviceId.take(8)} · E2Ev1",
                        fontSize = 11.sp, color = AppColors.textTertiary)
                    Text("系统: Android $osVer (API $sdk) · 设备: ${android.os.Build.MODEL}",
                        fontSize = 11.sp, color = AppColors.textTertiary,
                        modifier = Modifier.padding(top = 2.dp))
                }
            }
        }
    }
}

@Composable
fun SectionHeader(text: String) {
    Text(text, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = AppColors.textTertiary,
        modifier = Modifier.padding(horizontal = AppSpacing.lg, vertical = AppSpacing.sm))
}