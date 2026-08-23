package top.vios.chat

import android.content.Context
import java.util.Random

/**
 * 随机头像生成器
 * 基于设备名/字符串哈希生成稳定的 emoji + 颜色组合
 * 同一设备名永远得到同一头像
 */
object AvatarManager {

    private val EMOJIS = arrayOf(
        "🦊", "🐼", "🦁", "🐯", "🐸", "🦉", "🐺", "🐨",
        "🦄", "🐳", "🦈", "🐬", "🦋", "🐝", "🦜", "🐙",
        "🤖", "👾", "🦖", "🐉", "🦅", "🐧", "🦭", "🐢",
        "🐹", "🦔", "🐿️", "🦇", "🐆", "🦒", "🐘", "🦩"
    )

    // 头像背景色（深色系，与 UI 匹配）
    private val COLORS = intArrayOf(
        0xFF7C4DFF.toInt(), 0xFF2979FF.toInt(), 0xFF00C853.toInt(), 0xFFFF6D00.toInt(),
        0xFFE53935.toInt(), 0xFF00ACC1.toInt(), 0xFF8E24AA.toInt(), 0xFF43A047.toInt(),
        0xFFF4511E.toInt(), 0xFF3949AB.toInt(), 0xFF00897B.toInt(), 0xFFC0CA33.toInt(),
        0xFFD81B60.toInt(), 0xFF5E35B1.toInt(), 0xFF1E88E5.toInt(), 0xFF6D4C41.toInt()
    )

    /** 根据字符串生成稳定索引 */
    private fun hashIndex(str: String, size: Int): Int {
        var h = 0L
        for (c in str) {
            h = (h * 31 + c.code) % 100000
        }
        return (h % size).toInt()
    }

    /** 获取头像 emoji */
    fun getEmoji(name: String): String {
        return EMOJIS[hashIndex(name, EMOJIS.size)]
    }

    /** 获取头像背景色 ARGB */
    fun getColor(name: String): Int {
        return COLORS[hashIndex(name, COLORS.size)]
    }

    /** 获取头像背景色（带透明度） */
    fun getColorWithAlpha(name: String, alpha: Int = 26): Int {
        val base = getColor(name)
        return (alpha shl 24) or (base and 0xFFFFFF)
    }
}