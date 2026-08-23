package top.vios.chat

import android.content.Context
import java.util.UUID

/**
 * 设备唯一身份标识
 *
 * 核心设计：
 * - 首次启动生成 UUID，持久化存储，**永不可更改**（无 setter）
 * - 与设备名（可自定义）完全分离：deviceId 用于身份区分，deviceName 仅用于显示
 * - 所有消息携带 deviceId，双视角判断基于 deviceId 而非名字
 */
object DeviceIdentity {

    private const val PREFS = "everett_identity"
    private const val KEY_DEVICE_ID = "device_id"

    /** 获取设备唯一 ID（首次调用生成并持久化） */
    fun getDeviceId(context: Context): String {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val existing = prefs.getString(KEY_DEVICE_ID, null)
        if (existing != null && existing.isNotEmpty()) {
            return existing
        }
        // 生成 UUID v4 并持久化
        val newId = UUID.randomUUID().toString()
        prefs.edit().putString(KEY_DEVICE_ID, newId).apply()
        return newId
    }

    /** 判断两个 ID 是否同一设备 */
    fun isSameDevice(id1: String?, id2: String?): Boolean {
        if (id1.isNullOrEmpty() || id2.isNullOrEmpty()) return false
        return id1 == id2
    }

    /** 短 ID（用于展示/日志，如 ab12cd34） */
    fun shortId(id: String): String {
        return if (id.length >= 8) id.substring(0, 8) else id
    }
}