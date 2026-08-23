package top.vios.chat

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.ContextCompat

/**
 * 权限管理器
 * 记录各权限的最后请求时间，用户可设定提醒间隔（天）
 * 不到间隔不重复请求，避免频繁打扰
 */
object PermissionManager {

    private const val PREFS = "everett_permissions"
    private const val KEY_INTERVAL = "perm_interval_days"     // 默认 7 天
    private const val KEY_FIRST_RUN = "first_run_done"
    private const val KEY_NOTIFICATION_SHOWN = "perm_notification_last"
    private const val KEY_CAMERA_SHOWN = "perm_camera_last"
    private const val KEY_AUDIO_SHOWN = "perm_audio_last"
    private const val KEY_BATTERY_SHOWN = "perm_battery_last"

    val REQUIRED_PERMISSIONS = mutableListOf(
        android.Manifest.permission.RECORD_AUDIO,
        android.Manifest.permission.CAMERA,
        android.Manifest.permission.POST_NOTIFICATIONS
    ).apply {
        if (Build.VERSION.SDK_INT >= 34) {
            add(android.Manifest.permission.FOREGROUND_SERVICE_DATA_SYNC)
        }
    }

    /** 权限描述（中文） */
    data class PermInfo(
        val permission: String,
        val label: String,
        val desc: String,
        val icon: String
    )

    val PERM_INFO_LIST = listOf(
        PermInfo(android.Manifest.permission.RECORD_AUDIO, "麦克风", "发送语音消息", "🎤"),
        PermInfo(android.Manifest.permission.CAMERA, "相机", "视频通话", "📷"),
        PermInfo(android.Manifest.permission.POST_NOTIFICATIONS, "通知", "后台保活通知", "🔔"),
        PermInfo("battery_optimization", "电池白名单", "防止系统杀后台", "🔋")
    )

    /** 获取权限提醒间隔（天），默认 7 */
    fun getIntervalDays(context: Context): Int {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getInt(KEY_INTERVAL, 7)
    }

    /** 设置权限提醒间隔（天） */
    fun setIntervalDays(context: Context, days: Int) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putInt(KEY_INTERVAL, days).apply()
    }

    /** 是否首次运行（首次运行显示引导页） */
    fun isFirstRun(context: Context): Boolean {
        return !context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_FIRST_RUN, false)
    }

    fun setFirstRunDone(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_FIRST_RUN, true).apply()
    }

    /** 检查权限是否已授予 */
    fun isGranted(context: Context, permission: String): Boolean {
        if (permission == "battery_optimization") {
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            return pm.isIgnoringBatteryOptimizations(context.packageName)
        }
        return ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
    }

    /** 是否应该请求该权限（距上次请求超过间隔天） */
    fun shouldRequest(context: Context, permission: String): Boolean {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val key = when (permission) {
            android.Manifest.permission.RECORD_AUDIO -> KEY_AUDIO_SHOWN
            android.Manifest.permission.CAMERA -> KEY_CAMERA_SHOWN
            android.Manifest.permission.POST_NOTIFICATIONS -> KEY_NOTIFICATION_SHOWN
            "battery_optimization" -> KEY_BATTERY_SHOWN
            else -> return true
        }
        val lastTime = prefs.getLong(key, 0L)
        val intervalMs = getIntervalDays(context) * 24L * 60L * 60L * 1000L
        return System.currentTimeMillis() - lastTime > intervalMs
    }

    /** 记录权限请求时间 */
    fun markRequested(context: Context, permission: String) {
        val key = when (permission) {
            android.Manifest.permission.RECORD_AUDIO -> KEY_AUDIO_SHOWN
            android.Manifest.permission.CAMERA -> KEY_CAMERA_SHOWN
            android.Manifest.permission.POST_NOTIFICATIONS -> KEY_NOTIFICATION_SHOWN
            "battery_optimization" -> KEY_BATTERY_SHOWN
            else -> return
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putLong(key, System.currentTimeMillis()).apply()
    }

    /** 打开系统权限设置页 */
    fun openAppSettings(context: Context) {
        try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            intent.data = Uri.parse("package:" + context.packageName)
            context.startActivity(intent)
        } catch (_: Exception) {
            try {
                context.startActivity(Intent(Settings.ACTION_MANAGE_APPLICATIONS_SETTINGS))
            } catch (_: Exception) {}
        }
    }
}