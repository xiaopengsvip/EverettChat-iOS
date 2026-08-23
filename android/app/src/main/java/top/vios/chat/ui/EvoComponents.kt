package top.vios.chat.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Message
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
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
import top.vios.chat.AppRadius
import top.vios.chat.AppSpacing

/** 底部导航 Tab 定义 */
enum class EvoTab(val title: String, val icon: ImageVector, val selectedIcon: ImageVector) {
    MESSAGES("消息", Icons.Filled.Message, Icons.Filled.Message),
    CONTACTS("通讯录", Icons.Filled.Group, Icons.Filled.Group),
    DISCOVER("发现", Icons.Filled.GridView, Icons.Filled.GridView),
    MINE("我的", Icons.Filled.Person, Icons.Filled.Person)
}

/** 顶部栏 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EvoTopBar(
    title: String,
    subtitle: String = "",
    onBack: (() -> Unit)? = null,
    actions: @Composable RowScope.() -> Unit = {}
) {
    TopAppBar(
        title = {
            Column {
                Text(title, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = AppColors.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (subtitle.isNotEmpty()) {
                    Text(subtitle, fontSize = 11.sp, color = AppColors.textTertiary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        },
        navigationIcon = {
            if (onBack != null) IconButton(onClick = onBack) { Icon(Icons.Filled.ArrowBack, contentDescription = "返回", tint = AppColors.textPrimary) }
        },
        actions = actions,
        colors = TopAppBarDefaults.topAppBarColors(containerColor = AppColors.bgAlt, scrolledContainerColor = AppColors.bgAlt)
    )
}

@Composable
fun EvoIconButton(icon: ImageVector, contentDescription: String?, onClick: () -> Unit) {
    IconButton(onClick = onClick) { Icon(icon, contentDescription, tint = AppColors.textPrimary) }
}

/** 统一搜索框 */
@Composable
fun EvoSearchBar(value: String, onValueChange: (String) -> Unit, placeholder: String) {
    Row(Modifier.fillMaxWidth().padding(horizontal = AppSpacing.lg, vertical = AppSpacing.sm).height(36.dp)
        .background(AppColors.surfaceAlt, RoundedCornerShape(10.dp)).padding(horizontal = 10.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Filled.Search, contentDescription = null, tint = AppColors.textTertiary, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(8.dp))
        TextField(value = value, onValueChange = onValueChange,
            placeholder = { Text(placeholder, color = AppColors.textTertiary, fontSize = 15.sp) },
            singleLine = true,
            colors = TextFieldDefaults.colors(focusedContainerColor = Color.Transparent, unfocusedContainerColor = Color.Transparent,
                focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent,
                cursorColor = AppColors.primary, focusedTextColor = AppColors.textPrimary, unfocusedTextColor = AppColors.textPrimary),
            textStyle = androidx.compose.ui.text.TextStyle(fontSize = 15.sp),
            modifier = Modifier.weight(1f))
        if (value.isNotEmpty()) {
            IconButton(onClick = { onValueChange("") }, modifier = Modifier.size(20.dp)) {
                Icon(Icons.Filled.Clear, contentDescription = "清除", tint = AppColors.textTertiary, modifier = Modifier.size(14.dp))
            }
        }
    }
}

/** 会话行 */
@Composable
fun EvoConversationRow(
    avatarName: String, title: String, subtitle: String, timeText: String,
    unread: Int = 0, accent: Boolean = false, avatarColor: Color = AppColors.surfaceAlt, onClick: () -> Unit,
    isOnline: Boolean = false
) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = AppSpacing.lg, vertical = AppSpacing.md),
        verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(48.dp).background(if (accent) AppColors.primaryDim else avatarColor, CircleShape), contentAlignment = Alignment.Center) {
            Text(avatarName.take(1), fontSize = 18.sp, fontWeight = FontWeight.SemiBold,
                color = if (accent) AppColors.primary else AppColors.textSecondary)
            // 在线状态点（右上角小圆点：绿=在线，灰=离线）
            Box(
                Modifier
                    .align(Alignment.BottomEnd)
                    .size(13.dp)
                    .background(if (isOnline) Color(0xFF34C759) else Color(0xFF9E9E9E), CircleShape)
                    .border(2.dp, AppColors.bg, CircleShape)
            )
        }
        Spacer(Modifier.width(AppSpacing.md))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(title, fontSize = 16.sp, fontWeight = FontWeight.SemiBold,
                    color = if (accent) AppColors.primary else AppColors.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                if (isOnline) {
                    Spacer(Modifier.width(6.dp))
                    Text("在线", fontSize = 10.sp, color = Color(0xFF34C759))
                }
                if (timeText.isNotEmpty()) { Spacer(Modifier.width(6.dp)); Text(timeText, fontSize = 11.sp, color = AppColors.textTertiary) }
            }
            Spacer(Modifier.height(3.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(subtitle, fontSize = 13.sp, color = AppColors.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                if (unread > 0) {
                    Spacer(Modifier.width(8.dp))
                    Box(Modifier.background(AppColors.error, RoundedCornerShape(10.dp)).padding(horizontal = 6.dp, vertical = 2.dp)) {
                        Text(if (unread > 99) "99+" else "$unread", color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.SemiBold)
                    }
                }
            }
        }
    }
    HorizontalDivider(color = AppColors.outline, thickness = 0.5.dp)
}

/** 设置行 */
@Composable
fun EvoSettingsRow(icon: ImageVector, title: String, subtitle: String = "", onClick: () -> Unit, tint: Color = AppColors.primary) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = AppSpacing.lg, vertical = AppSpacing.md),
        verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(AppSpacing.md))
        Column(Modifier.weight(1f)) {
            Text(title, fontSize = 15.sp, color = AppColors.textPrimary)
            if (subtitle.isNotEmpty()) { Spacer(Modifier.height(2.dp)); Text(subtitle, fontSize = 12.sp, color = AppColors.textSecondary) }
        }
        Icon(Icons.Filled.ChevronRight, contentDescription = null, tint = AppColors.textTertiary, modifier = Modifier.size(20.dp))
    }
}

/** 功能行 */
@Composable
fun EvoFeatureRow(icon: ImageVector, name: String, desc: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = AppSpacing.lg, vertical = AppSpacing.md),
        verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, contentDescription = null, tint = AppColors.primary, modifier = Modifier.size(24.dp))
        Spacer(Modifier.width(AppSpacing.md))
        Column(Modifier.weight(1f)) {
            Text(name, fontSize = 15.sp, color = AppColors.textPrimary)
            Spacer(Modifier.height(2.dp)); Text(desc, fontSize = 12.sp, color = AppColors.textTertiary)
        }
        Icon(Icons.Filled.ChevronRight, contentDescription = null, tint = AppColors.textTertiary, modifier = Modifier.size(20.dp))
    }
}

/** 空状态 */
@Composable
fun EvoEmptyState(icon: ImageVector, title: String, subtitle: String = "") {
    Column(Modifier.fillMaxWidth().padding(top = 64.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(icon, contentDescription = null, tint = AppColors.textTertiary, modifier = Modifier.size(44.dp))
        Spacer(Modifier.height(14.dp))
        Text(title, color = AppColors.textSecondary, fontSize = 14.sp, fontWeight = FontWeight.Medium)
        if (subtitle.isNotEmpty()) {
            Spacer(Modifier.height(6.dp))
            Text(subtitle, color = AppColors.textTertiary, fontSize = 12.sp, modifier = Modifier.padding(horizontal = 40.dp), textAlign = TextAlign.Center)
        }
    }
}

/** 时间格式化 */
fun formatEvoTime(time: Long): String {
    if (time <= 0) return ""
    val cal = java.util.Calendar.getInstance().apply { timeInMillis = time }
    val now = java.util.Calendar.getInstance()
    return when {
        cal.get(java.util.Calendar.DAY_OF_YEAR) == now.get(java.util.Calendar.DAY_OF_YEAR) && cal.get(java.util.Calendar.YEAR) == now.get(java.util.Calendar.YEAR) ->
            java.text.SimpleDateFormat("HH:mm", java.util.Locale.getDefault()).format(java.util.Date(time))
        cal.get(java.util.Calendar.YEAR) == now.get(java.util.Calendar.YEAR) ->
            java.text.SimpleDateFormat("M月d日", java.util.Locale.getDefault()).format(java.util.Date(time))
        else -> java.text.SimpleDateFormat("yyyy/M/d", java.util.Locale.getDefault()).format(java.util.Date(time))
    }
}