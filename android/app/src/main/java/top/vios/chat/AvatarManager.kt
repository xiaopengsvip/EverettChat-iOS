package top.vios.chat

import android.graphics.Color

/**
 * 首字母头像生成器（与 iOS ConversationRow 同算法）
 * 基于名字哈希生成稳定背景色 + 首字母，无 emoji，两端一致
 */
object AvatarManager {

    // 稳定品牌色系（8 组，bg: 浅色底，fg: 深色字）
    private val PALETTE = arrayOf(
        intArrayOf(0xFFE9E4FF.toInt(), 0xFF7657FF.toInt()),  // 品牌紫
        intArrayOf(0xFFE0F2FE.toInt(), 0xFF0369A1.toInt()),  // 天蓝
        intArrayOf(0xFFDCFCE7.toInt(), 0xFF15803D.toInt()),  // 绿
        intArrayOf(0xFFFFEDD5.toInt(), 0xFFC2410C.toInt()),  // 橙
        intArrayOf(0xFFFAE8FF.toInt(), 0xFFA21CAF.toInt()),  // 紫红
        intArrayOf(0xFFCFFAFE.toInt(), 0xFF0E7490.toInt()),  // 青
        intArrayOf(0xFFFEE2E2.toInt(), 0xFFB91C1C.toInt()),  // 红
        intArrayOf(0xFFECFCCB.toInt(), 0xFF4D7C0F.toInt()),  // 黄绿
    )

    /** 稳定哈希（与 iOS stableHash 一致） */
    private fun stableHash(str: String): Int {
        var h = 0L
        for (c in str) {
            h = (h * 31 + c.code) % 100000
        }
        return h.toInt()
    }

    /** 获取首字母（取第一个非空白字符，中文取第一个字） */
    fun getLetter(name: String): String {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return "?"
        return trimmed.first().uppercase().toString()
    }

    /** 获取背景色（ARGB） */
    fun getBackgroundColor(name: String): Int {
        val idx = stableHash(name) % PALETTE.size
        return PALETTE[idx][0]
    }

    /** 获取前景色（文字颜色，ARGB） */
    fun getForegroundColor(name: String): Int {
        val idx = stableHash(name) % PALETTE.size
        return PALETTE[idx][1]
    }
}