package top.vios.chat.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import top.vios.chat.AppColors

/**
 * EVO 主框架：系统 NavigationBar（M3）+ 4 Tab 内容区
 * 对应 iOS TabView —— 用 Android 原生组件表达。
 */
@Composable
fun EvoRootScaffold(
    currentTab: EvoTab,
    unreadCount: Int = 0,
    onTabSelected: (EvoTab) -> Unit,
    content: @Composable () -> Unit
) {
    Scaffold(
        containerColor = AppColors.bg,
        contentWindowInsets = WindowInsets.safeDrawing.only(WindowInsetsSides.Horizontal),
        bottomBar = {
            NavigationBar(containerColor = AppColors.surface, tonalElevation = 0.dp) {
                EvoTab.entries.forEach { tab ->
                    val selected = tab == currentTab
                    NavigationBarItem(
                        selected = selected,
                        onClick = { onTabSelected(tab) },
                        icon = {
                            Icon(imageVector = if (selected) tab.selectedIcon else tab.icon,
                                contentDescription = tab.title,
                                tint = if (selected) AppColors.primary else AppColors.textTertiary)
                        },
                        label = {
                            Text(tab.title, fontSize = 11.sp,
                                color = if (selected) AppColors.primary else AppColors.textTertiary,
                                fontWeight = if (selected) androidx.compose.ui.text.font.FontWeight.SemiBold else androidx.compose.ui.text.font.FontWeight.Normal)
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
    ) { padding ->
        Box(Modifier.padding(padding)) { content() }
    }
}