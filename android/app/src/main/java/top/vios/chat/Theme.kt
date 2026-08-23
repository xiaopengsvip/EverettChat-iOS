package top.vios.chat

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * EVO 2026 · Native Liquid Glass Design System
 * 设计语言：系统做骨架，Liquid Glass 做材质，Evo 做品牌，AI 做核心。
 * 双主题：Pearl White 珍珠白（默认）/ Deep Black 深邃黑（跟随系统或手动切换）。
 * 原则：珍珠白是底，Liquid Glass 是浮层，Evo Purple 是灵魂（仅强调 5-10%），内容层保持干净。
 */
object AppColors {
    // ===== 主题状态（Compose 状态：切换即时重组） =====
    private val isDarkState = mutableStateOf(false)
    /** 当前是否为深色主题（由 setTheme 控制，默认跟随系统） */
    var isDark: Boolean
        get() = isDarkState.value
        set(v) { isDarkState.value = v }
    /** 主题模式：light / dark / system */
    var themeMode: String = "system"
        private set
    /** 系统深色状态（跟随系统时使用） */
    var systemDark: Boolean = false
        private set

    /** 应用主题模式。mode: light|dark|system */
    fun applyTheme(mode: String, sysDark: Boolean = systemDark) {
        themeMode = mode
        systemDark = sysDark
        isDark = when (mode) {
            "dark" -> true
            "light" -> false
            else -> sysDark
        }
    }

    // ===== 背景层次 =====
    val bg: Color get() = if (isDark) Color(0xFF050507) else Color(0xFFF7F7F5)
    val bgAlt: Color get() = if (isDark) Color(0xFF0A0A0E) else Color(0xFFF1F1EF)
    val surface: Color get() = if (isDark) Color(0xFF111114) else Color(0xFFFFFFFF)
    val surfaceHigh: Color get() = if (isDark) Color(0xFF16161A) else Color(0xFFFAFAF9)
    val surfaceAlt: Color get() = if (isDark) Color(0xFF1B1B20) else Color(0xFFF4F4F2)
    val elevated: Color get() = if (isDark) Color(0xFF1B1B20) else Color(0xFFFFFFFF)
    /** 毛玻璃（顶栏/底栏/Composer，Liquid Glass 独立功能层） */
    val glass: Color get() = if (isDark) Color(0xB81C1C20) else Color(0xB8FFFFFF)
    /** 聊天区背景氛围 */
    val bgGlow: Color get() = if (isDark) Color(0xFF0D0D12) else Color(0xFFFDFDFC)

    // ===== 品牌色（Evo Purple，仅强调 5-10%） =====
    val primary: Color get() = if (isDark) Color(0xFF8B72FF) else Color(0xFF7657FF)
    val secondary: Color get() = if (isDark) Color(0xFF7C6CFF) else Color(0xFF9B78FF)
    val primaryDim: Color get() = if (isDark) Color(0xFF2A2150) else Color(0xFFE9E4FF)

    // ===== 文字层级 =====
    val textPrimary: Color get() = if (isDark) Color(0xFFF5F5F7) else Color(0xFF171717)
    val textSecondary: Color get() = if (isDark) Color(0xFFA1A1A6) else Color(0xFF6F7075)
    val textTertiary: Color get() = if (isDark) Color(0xFF6E6E73) else Color(0xFF9A9BA0)

    // ===== 功能色 =====
    val success: Color get() = if (isDark) Color(0xFF32D583) else Color(0xFF34C759)
    val successDim: Color get() = if (isDark) Color(0xFF0F2E22) else Color(0xFFE3F6E9)
    val successText: Color get() = if (isDark) Color(0xFFA8F0CE) else Color(0xFF1E7A3C)
    val error: Color get() = if (isDark) Color(0xFFFF5C6C) else Color(0xFFFF3B30)
    val errorDim: Color get() = if (isDark) Color(0xFF3A1620) else Color(0xFFFFE9E7)
    val warning: Color get() = if (isDark) Color(0xFFF5B84B) else Color(0xFFFF9F0A)
    val warningDim: Color get() = if (isDark) Color(0xFF3A2C12) else Color(0xFFFFF4E0)
    val info: Color get() = if (isDark) Color(0xFF6D9DF5) else Color(0xFF007AFF)

    // ===== 描边/遮罩（浅色用黑边，深色用白边） =====
    val outline: Color get() = if (isDark) Color(0x1AFFFFFF) else Color(0x14000000)
    val outlineStrong: Color get() = if (isDark) Color(0x26FFFFFF) else Color(0x26000000)
    val scrim: Color get() = Color(0x99000000)
    val scrimLight: Color get() = if (isDark) Color(0x26000000) else Color(0x14000000)

    // ===== 消息 =====
    val bubbleMine: Color get() = if (isDark) Color(0xFF7C5CF0) else Color(0xFF7657FF)
    val bubbleAi: Color get() = if (isDark) Color(0xFF16161C) else Color(0xFFF0EFF7)
    val bubblePeer: Color get() = if (isDark) Color(0xFF1B1B20) else Color(0xFFE8E8EC)
    val bubbleAiText: Color get() = if (isDark) Color(0xFFE8E8F0) else Color(0xFF1A1A1A)
    val bubblePeerText: Color get() = if (isDark) Color(0xFFE8E8F0) else Color(0xFF1A1A1A)
}

/** 间距 Token（4/8/12/16/20/24/32/40/48） */
object AppSpacing {
    val xs = 4.dp
    val sm = 8.dp
    val md = 12.dp
    val lg = 16.dp
    val xl = 20.dp
    val xxl = 24.dp
    val xxxl = 32.dp
    val huge = 40.dp
    val page = 20.dp
}

/** 圆角 Token（List/Card 16 / Glass 20 / Input 22 / Sheet 24 / Floating 24+） */
object AppRadius {
    val small = 10.dp
    val medium = 14.dp
    val large = 18.dp
    val glass = 20.dp
    val sheet = 24.dp
    val floating = 24.dp
}

/** 字号 Token（12/13/15/16/17/20/22/28/34） */
object AppType {
    val pageTitle = 30.sp
    val section = 16.sp
    val body = 15.sp
    val secondary = 13.sp
    val caption = 12.sp
    val micro = 10.sp
}

/** 动效 Token */
object AppMotion {
    const val button = 150
    const val tab = 200
    const val page = 280
    const val sheet = 320
}

/** 渐变 —— 仅用于背景氛围与极少数 CTA（克制使用） */
object AppGradients {
    val primary: Brush get() = Brush.linearGradient(listOf(AppColors.primary, AppColors.secondary))
    val success: Brush get() = Brush.linearGradient(listOf(AppColors.success, if (AppColors.isDark) Color(0xFF10B981) else Color(0xFF2FB65C)))
    val error: Brush get() = Brush.linearGradient(listOf(AppColors.error, if (AppColors.isDark) Color(0xFFEF4444) else Color(0xFFE0261B)))
    val bg: Brush get() = Brush.verticalGradient(listOf(AppColors.bgGlow, AppColors.bg))
}
