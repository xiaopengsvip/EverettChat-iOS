package top.vios.chat

import android.graphics.Bitmap
import androidx.compose.ui.graphics.Color
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.json.JSONObject

/**
 * 二维码好友系统
 * 协议：{"t":"evt","id":"<deviceId>","n":"<设备名>"}
 * 生成：ZXing QRCodeWriter（纯本地）
 * 扫描：zxing-android-embedded CaptureActivity（纯本地解码，不依赖 GMS）
 */

object QrContact {
    const val TYPE = "evt"

    /** 生成我的二维码内容（JSON） */
    fun encode(deviceId: String, name: String): String {
        return try {
            JSONObject()
                .put("t", TYPE)
                .put("id", deviceId)
                .put("n", name)
                .toString()
        } catch (_: Exception) { "" }
    }

    /** 解析二维码内容；返回 null 表示不是 Everett 好友码 */
    fun decode(content: String): Pair<String, String>? {
        return try {
            val j = JSONObject(content)
            if (j.optString("t", "") != TYPE) return null
            val id = j.optString("id", "")
            val name = j.optString("n", "设备")
            if (id.isBlank()) null else (id to name)
        } catch (_: Exception) { null }
    }
}

/** 用 ZXing 生成二维码 Bitmap（纯色，白底） */
fun generateQrBitmap(content: String, sizePx: Int = 720): Bitmap? {
    return try {
        val writer = QRCodeWriter()
        val matrix = writer.encode(content, BarcodeFormat.QR_CODE, sizePx, sizePx)
        val bmp = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        for (x in 0 until sizePx) {
            for (y in 0 until sizePx) {
                val px = if (matrix.get(x, y)) android.graphics.Color.BLACK else android.graphics.Color.WHITE
                bmp.setPixel(x, y, px)
            }
        }
        bmp
    } catch (_: Exception) { null }
}

/** 我的二维码页（全屏）：大二维码 + 设备名 + 唯一 ID */
@Composable
fun QrCodeScreen(
    deviceName: String,
    myDeviceId: String,
    onBack: () -> Unit
) {
    val qrText = remember(myDeviceId, deviceName) { QrContact.encode(myDeviceId, deviceName) }
    val qrBitmap = remember(qrText) { generateQrBitmap(qrText) }

    Column(Modifier.fillMaxSize().background(AppGradients.bg)) {
        AppTopBar(title = "我的二维码", onBack = onBack)
        Column(
            Modifier.fillMaxSize().padding(horizontal = AppSpacing.xxl),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(Modifier.height(40.dp))
            // 二维码（白底圆角，扫描稳定）
            Surface(
                shape = RoundedCornerShape(AppRadius.large),
                color = Color.White,
                shadowElevation = 12.dp,
                modifier = Modifier.size(280.dp)
            ) {
                Box(Modifier.padding(16.dp), contentAlignment = Alignment.Center) {
                    if (qrBitmap != null) {
                        Image(
                            bitmap = qrBitmap.asImageBitmap(),
                            contentDescription = "我的二维码",
                            modifier = Modifier.fillMaxSize()
                        )
                    } else {
                        Text("生成失败", color = Color.Black, fontSize = 14.sp)
                    }
                }
            }
            Spacer(Modifier.height(24.dp))
            Text(deviceName, color = AppColors.textPrimary, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(6.dp))
            Text(
                "ID: " + DeviceIdentity.shortId(myDeviceId),
                color = AppColors.textTertiary, fontSize = 13.sp,
                fontFamily = FontFamily.Monospace
            )
            Spacer(Modifier.height(32.dp))
            // 操作提示
            Surface(
                shape = RoundedCornerShape(AppRadius.medium),
                color = AppColors.surfaceHigh,
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(Modifier.padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("📲 让对方打开「消息 / 通讯录」右上角 +", color = AppColors.textSecondary, fontSize = 13.sp)
                    Spacer(Modifier.height(4.dp))
                    Text("点击「扫一扫」扫描此二维码即可添加好友", color = AppColors.textSecondary, fontSize = 13.sp)
                }
            }
        }
    }
}
