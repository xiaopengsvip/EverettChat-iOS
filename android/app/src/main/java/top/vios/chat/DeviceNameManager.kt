package top.vios.chat

import android.content.Context
import java.util.Random

/**
 * 设备名称管理
 * 首次安装随机分配，用户可自定义
 */
object DeviceNameManager {

    // 随机名称池（中文 + 英文）
    private val PREFIX_ZH = arrayOf(
        "银河", "量子", "星辰", "极光", "幻影", "苍穹", "烈焰", "寒冰",
        "闪电", "雷霆", "霓虹", "深空", "曙光", "月光", "流星", "赤霞"
    )
    private val SUFFIX_ZH = arrayOf(
        "之翼", "行者", "信使", "猎手", "骑士", "飞鱼", "狐狸", "苍狼",
        "猎鹰", "鲨鱼", "白虎", "凤凰", "麒麟", "玄龟", "独角兽", "蜂鸟"
    )
    private val PREFIX_EN = arrayOf(
        "Silver", "Quantum", "Neon", "Cosmic", "Shadow", "Crimson",
        "Electric", "Phantom", "Aurora", "Storm", "Nova", "Orbit"
    )
    private val SUFFIX_EN = arrayOf(
        "Fox", "Wolf", "Falcon", "Shark", "Tiger", "Phoenix",
        "Raven", "Lynx", "Eagle", "Panda", "Dragon", "Comet"
    )

    private const val PREFS = "everett_chat"
    private const val KEY_NAME = "device_name"
    private const val KEY_NAME_CUSTOM = "device_name_custom"

    private val random = Random()

    /** 获取设备名（无则随机生成） */
    fun getDeviceName(context: Context): String {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val existing = prefs.getString(KEY_NAME, null)
        if (existing != null) return existing
        return generateRandomName(context)
    }

    /** 生成随机名称并保存 */
    fun generateRandomName(context: Context): String {
        val name = if (random.nextBoolean()) {
            PREFIX_ZH[random.nextInt(PREFIX_ZH.size)] + SUFFIX_ZH[random.nextInt(SUFFIX_ZH.size)]
        } else {
            PREFIX_EN[random.nextInt(PREFIX_EN.size)] + " " + SUFFIX_EN[random.nextInt(SUFFIX_EN.size)]
        }
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.edit().putString(KEY_NAME, name).putBoolean(KEY_NAME_CUSTOM, false).apply()
        return name
    }

    /** 用户自定义名称 */
    fun setCustomName(context: Context, name: String) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.edit().putString(KEY_NAME, name).putBoolean(KEY_NAME_CUSTOM, true).apply()
    }

    /** 是否用户自定义 */
    fun isCustom(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return prefs.getBoolean(KEY_NAME_CUSTOM, false)
    }

    /** 重新随机分配 */
    fun rerollName(context: Context): String = generateRandomName(context)
}