package top.vios.chat.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.material3.Typography
import androidx.compose.material3.Shapes
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import top.vios.chat.AppColors
import top.vios.chat.AppRadius
import top.vios.chat.AppSpacing
import top.vios.chat.AppType

/**
 * EVO 统一 Design System（Android 端）
 * ============================================
 * 与 iOS 版共享同一套 Design Token（颜色/间距/圆角/字号/图标语义），
 * 但用 Material 3 原生组件表达，不复制 iOS 截图、不用 WebView/HTML。
 *
 * 原则：
 * - CONTENT = 清晰、平面、轻量（白/浅灰/系统背景）
 * - SYSTEM UI = 材质、层级、动态（Navigation/Toolbar/FAB）
 * - 紫色仅用于 Selected / Active / Primary Action / AI
 *
 * 颜色 Token 映射（iOS ↔ Android 对应）：
 *   iOS Theme.bg          ↔ Android AppColors.bg（systemGroupedBackground）
 *   iOS Theme.surface     ↔ Android AppColors.surface
 *   iOS Theme.textPrimary ↔ Android AppColors.textPrimary（.primary）
 *   iOS Theme.primary     ↔ Android AppColors.primary（品牌紫）
 */

/** M3 Light ColorScheme —— 珍珠白（映射 AppColors + 系统语义） */
private val LightColors = lightColorScheme(
    primary = AppColors.primary,
    onPrimary = Color.White,
    primaryContainer = AppColors.primaryDim,
    onPrimaryContainer = AppColors.textPrimary,
    secondary = AppColors.primary,
    onSecondary = Color.White,
    secondaryContainer = AppColors.primaryDim,
    onSecondaryContainer = AppColors.textPrimary,
    background = AppColors.bg,
    onBackground = AppColors.textPrimary,
    surface = AppColors.surface,
    onSurface = AppColors.textPrimary,
    surfaceVariant = AppColors.surfaceHigh,
    onSurfaceVariant = AppColors.textSecondary,
    surfaceContainerHighest = AppColors.surfaceAlt,
    surfaceContainerHigh = AppColors.surfaceHigh,
    surfaceContainer = AppColors.surfaceHigh,
    surfaceContainerLow = AppColors.bgAlt,
    surfaceContainerLowest = AppColors.surface,
    outline = AppColors.outlineStrong,
    outlineVariant = AppColors.outline,
    error = AppColors.error,
    onError = Color.White,
    errorContainer = AppColors.errorDim,
    onErrorContainer = AppColors.error
)

/** M3 Dark ColorScheme —— 深邃黑（映射 AppColors） */
private val DarkColors = darkColorScheme(
    primary = AppColors.primary,
    onPrimary = Color.White,
    primaryContainer = AppColors.primaryDim,
    onPrimaryContainer = AppColors.textPrimary,
    secondary = AppColors.primary,
    onSecondary = Color.White,
    secondaryContainer = AppColors.primaryDim,
    onSecondaryContainer = AppColors.textPrimary,
    background = AppColors.bg,
    onBackground = AppColors.textPrimary,
    surface = AppColors.surface,
    onSurface = AppColors.textPrimary,
    surfaceVariant = AppColors.surfaceHigh,
    onSurfaceVariant = AppColors.textSecondary,
    surfaceContainerHighest = AppColors.surfaceAlt,
    surfaceContainerHigh = AppColors.surfaceHigh,
    surfaceContainer = AppColors.surfaceHigh,
    surfaceContainerLow = AppColors.bgAlt,
    surfaceContainerLowest = AppColors.surface,
    outline = AppColors.outlineStrong,
    outlineVariant = AppColors.outline,
    error = AppColors.error,
    onError = Color.White,
    errorContainer = AppColors.errorDim,
    onErrorContainer = AppColors.error
)

/** M3 Typography —— 字号体系与 iOS 一致（Large Title/Body/Subheadline/Caption） */
private val EvoTypography = Typography(
    displayLarge = TextStyle(fontSize = 34.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.sp),
    displayMedium = TextStyle(fontSize = 28.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.sp),
    headlineLarge = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.sp),
    headlineMedium = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.sp),
    titleLarge = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.sp),
    titleMedium = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.sp),
    titleSmall = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.Medium, letterSpacing = 0.sp),
    bodyLarge = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.Normal, letterSpacing = 0.sp),
    bodyMedium = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.Normal, letterSpacing = 0.sp),
    bodySmall = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.Normal, letterSpacing = 0.sp),
    labelLarge = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Medium, letterSpacing = 0.sp),
    labelMedium = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Medium, letterSpacing = 0.sp),
    labelSmall = TextStyle(fontSize = 10.sp, fontWeight = FontWeight.Medium, letterSpacing = 0.sp)
)

/** M3 Shapes —— 圆角体系（Small/Medium/Large/ExtraLarge，与 iOS 一致） */
private val EvoShapes = Shapes(
    extraSmall = RoundedCornerShape(AppRadius.small),
    small = RoundedCornerShape(AppRadius.small),
    medium = RoundedCornerShape(AppRadius.medium),
    large = RoundedCornerShape(AppRadius.large),
    extraLarge = RoundedCornerShape(AppRadius.sheet)
)

/** 应用主题入口 */
@Composable
fun EvoTheme(
    darkTheme: Boolean = AppColors.isDark,
    content: @Composable () -> Unit
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        typography = EvoTypography,
        shapes = EvoShapes,
        content = content
    )
}
