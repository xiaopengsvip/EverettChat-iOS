package top.vios.chat.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.SystemUpdate
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import top.vios.chat.AppColors

/**
 * EVO 更新服务弹窗（Material 3 自定义设计）
 * 对应 iOS 风格：品牌紫图标 + 圆角卡片 + 清晰来源信息
 */
@Composable
fun EvoUpdateDialog(
    apkFile: java.io.File,
    apkName: String,
    fromServer: Boolean,
    onDismiss: () -> Unit,
    onInstall: () -> Unit
) {
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Surface(
            shape = RoundedCornerShape(20.dp),
            color = AppColors.surface,
            tonalElevation = 0.dp,
            shadowElevation = 24.dp,
            modifier = Modifier.fillMaxWidth(0.86f)
        ) {
            Column(
                modifier = Modifier.padding(horizontal = 24.dp, vertical = 28.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                // 顶部：品牌紫圆形图标（下载/更新符号）
                Box(
                    modifier = Modifier
                        .size(64.dp)
                        .background(AppColors.primaryDim, CircleShape),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        Icons.Filled.SystemUpdate,
                        contentDescription = null,
                        tint = AppColors.primary,
                        modifier = Modifier.size(32.dp)
                    )
                }
                Spacer(Modifier.height(16.dp))

                // 标题：区分更新服务 / 好友发送
                Text(
                    if (fromServer) "EVO 更新服务" else "收到更新包",
                    fontSize = 18.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = AppColors.textPrimary,
                    textAlign = TextAlign.Center
                )
                Spacer(Modifier.height(6.dp))

                // 文件名
                Text(
                    apkName,
                    fontSize = 14.sp,
                    color = AppColors.textSecondary,
                    textAlign = TextAlign.Center,
                    maxLines = 2
                )
                Spacer(Modifier.height(4.dp))

                // 大小 + 来源
                Text(
                    "${apkFile.length() / 1024 / 1024} MB · ${if (fromServer) "EVO 云端更新" else "好友发送"}",
                    fontSize = 12.sp,
                    color = AppColors.textTertiary
                )

                Spacer(Modifier.height(24.dp))

                // 按钮
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    // 稍后
                    OutlinedButton(
                        onClick = onDismiss,
                        modifier = Modifier.weight(1f).height(44.dp),
                        shape = RoundedCornerShape(14.dp),
                        colors = ButtonDefaults.outlinedButtonColors(
                            contentColor = AppColors.textSecondary
                        ),
                        border = androidx.compose.foundation.BorderStroke(1.dp, AppColors.outline)
                    ) {
                        Text("稍后", fontSize = 15.sp)
                    }
                    // 安装（品牌紫）
                    Button(
                        onClick = onInstall,
                        modifier = Modifier.weight(1.4f).height(44.dp),
                        shape = RoundedCornerShape(14.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = AppColors.primary,
                            contentColor = Color.White
                        )
                    ) {
                        Text("立即安装", fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                    }
                }
            }
        }
    }
}
