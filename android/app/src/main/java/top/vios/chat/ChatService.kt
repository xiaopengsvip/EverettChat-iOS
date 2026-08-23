package top.vios.chat

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.net.ConnectivityManager
import android.util.Log
import kotlinx.coroutines.launch
import top.vios.chat.net.RelayDiscovery
import top.vios.chat.net.RelayServer

/**
 * 前台服务：保活 + 后台持续运行 + 常驻中继服务
 * - 常驻通知（低优先级，不打扰）
 * - 持有 WakeLock 防止 CPU 休眠
 * - 中继服务（RelayServer + 局域网广播）随服务常驻，24h+ 持续在线
 * - 中继开关状态持久化，重启 App 自动恢复
 */
class ChatService : Service() {

    companion object {
        private const val TAG = "ChatService"
        const val CHANNEL_ID = "everett_chat_keepalive"
        const val NOTIFICATION_ID = 1001
        const val ACTION_STOP = "top.vios.chat.STOP"
        const val ACTION_START_RELAY = "top.vios.chat.START_RELAY"
        const val ACTION_STOP_RELAY = "top.vios.chat.STOP_RELAY"
        const val PREF_RELAY_ENABLED = "relay_server_enabled"
        const val RELAY_PORT = RelayServer.DEFAULT_PORT

        fun start(context: Context) {
            val intent = Intent(context, ChatService::class.java)
            if (Build.VERSION.SDK_INT >= 26) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, ChatService::class.java))
        }

        /** 中继开关状态（默认开启 —— 中继网长期存在） */
        fun isRelayEnabled(context: Context): Boolean =
            context.getSharedPreferences("everett_chat", Context.MODE_PRIVATE)
                .getBoolean(PREF_RELAY_ENABLED, true)

        /** 切换中继开关（持久化 + 通知服务启停） */
        fun setRelayEnabled(context: Context, enabled: Boolean) {
            context.getSharedPreferences("everett_chat", Context.MODE_PRIVATE)
                .edit().putBoolean(PREF_RELAY_ENABLED, enabled).apply()
            val intent = Intent(context, ChatService::class.java)
                .setAction(if (enabled) ACTION_START_RELAY else ACTION_STOP_RELAY)
            if (Build.VERSION.SDK_INT >= 26) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            Log.i(TAG, "中继开关: $enabled")
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var relayServer: RelayServer? = null
    private var relayDiscovery: RelayDiscovery? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
        startForegroundCompat()

        // 持有 WakeLock（PARTIAL_WAKE_LOCK，仅持有不强制亮屏）持续保活
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "EVO:keepalive").apply {
            setReferenceCounted(false)
            acquire()
        }

        // 网络变化监听：Wi-Fi ↔ 移动网络切换/恢复后立即通知 App 重连（长连接保活）
        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            networkCallback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: android.net.Network) {
                    top.vios.chat.DevLog.i("Net", "网络已恢复，触发中继重连")
                    // 通知 MainActivity 立即重连
                    sendBroadcast(Intent("top.vios.chat.NET_RESTORED"))
                }
            }
            networkCallback?.let { cm.registerDefaultNetworkCallback(it) }
        } catch (_: Exception) {}
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopRelay()
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_START_RELAY -> startRelay()
            ACTION_STOP_RELAY -> stopRelay()
            else -> {
                // 常规启动：根据持久化状态恢复中继
                if (isRelayEnabled(this)) {
                    startRelay()
                }
            }
        }
        // 若被系统杀掉则重启（START_STICKY），重启后 onStartCommand(null) 自动恢复中继
        return START_STICKY
    }

    /** 启动常驻中继服务（消息中继 + APK 分发 + 局域网广播） */
    private fun startRelay() {
        try {
            if (relayServer == null) {
                val server = RelayServer(this, RELAY_PORT)
                if (server.startServer()) {
                    relayServer = server
                    // 自动发布本机 APK 到中继网（OTA 更新源）
                    kotlinx.coroutines.MainScope().launch {
                        try {
                            val apkPath = packageManager.getApplicationInfo(packageName, 0).sourceDir
                            server.publishApk(java.io.File(apkPath).readBytes(), BuildConfig.VERSION_CODE, BuildConfig.VERSION_NAME)
                        } catch (_: Exception) {}
                    }
                    // 局域网广播 + 扫描邻居中继（业务网自动互联）
                    val name = DeviceNameManager.getDeviceName(this)
                    val ip = getLocalIpAddress()
                    server.nodeName = name
                    relayDiscovery = RelayDiscovery(this).apply {
                        // 广播（10s 间隔，含 nodeId 用于单向互联判断）
                        startAnnounce(name, ip, RELAY_PORT, server.nodeId)
                        // 监听其他中继节点广播 → 自动互联（单向规则：nodeId 大者主动连，避免双向两连接）
                        startListen { node ->
                            if (node.ip != ip) {
                                // 单向互联：只有本节点 nodeId 大于对方时主动连接
                                // （双方都执行此规则，确保只有一条连接）
                                if (server.nodeId > node.nodeId) {
                                    Log.i(TAG, "主动互联: ${node.nodeId.take(8)} (${node.ip})")
                                    server.connectToNode(node.ip, node.port)
                                }
                            }
                        }
                    }
                    Log.i(TAG, "中继服务已常驻启动 @ $ip:$RELAY_PORT")
                } else {
                    Log.e(TAG, "中继启动失败（端口可能被占用）")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "中继启动异常: ${e.message}")
        }
    }

    /** 停止中继服务 */
    private fun stopRelay() {
        try {
            relayDiscovery?.dispose()
            relayDiscovery = null
            relayServer?.stopServer()
            relayServer = null
            Log.i(TAG, "中继服务已停止")
        } catch (_: Exception) {}
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= 26) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Everett Chat 后台运行",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "保持连接与消息接收"
                setShowBadge(false)
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }

    private fun startForegroundCompat() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(): Notification {
        val openIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val stopIntent = PendingIntent.getService(
            this, 1,
            Intent(this, ChatService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("Everett Chat")
            .setContentText(if (isRelayEnabled(this)) "中继服务运行中 · 保持连接与消息接收" else "后台运行中 · 保持连接与消息接收")
            .setSmallIcon(R.drawable.ic_launcher)
            .setContentIntent(openIntent)
            .setOngoing(true)
            .setPriority(Notification.PRIORITY_LOW)
            .addAction(0, "退出后台", stopIntent)
            .build()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // 用户划掉任务卡片：前台服务通常会被系统停止，这里主动重启保证持续在线
        super.onTaskRemoved(rootIntent)
        try {
            val restart = Intent(applicationContext, ChatService::class.java)
            if (Build.VERSION.SDK_INT >= 26) {
                applicationContext.startForegroundService(restart)
            } else {
                applicationContext.startService(restart)
            }
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        stopRelay()
        try {
            networkCallback?.let { cb ->
                val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                cm.unregisterNetworkCallback(cb)
            }
        } catch (_: Exception) {}
        networkCallback = null
        try { wakeLock?.release() } catch (_: Exception) {}
        wakeLock = null
        super.onDestroy()
    }
}
