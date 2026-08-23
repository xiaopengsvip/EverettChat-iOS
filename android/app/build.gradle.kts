plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// 版本号自动生成：YY.MMDD.XXXX（年2位.月日4位.构建序号4位，当天递增，跨天重置为0001）
// 例：26.0823.0001 → 当天第二次构建 26.0823.0002 → 次日 26.0824.0001
import java.util.Calendar
import java.io.File
val buildCal = Calendar.getInstance()
val yy = String.format("%02d", buildCal.get(Calendar.YEAR) % 100)
val mmdd = String.format("%02d%02d", buildCal.get(Calendar.MONTH) + 1, buildCal.get(Calendar.DAY_OF_MONTH))
// 当天构建计数器：读 build_counter.txt（格式: YYMMDD count），同一天递增，跨天重置为 1
val counterFile = File(rootDir, "build_counter.txt")
val todayKey = yy + mmdd
var buildCount = 1
try {
    val lines = counterFile.readLines()
    if (lines.isNotEmpty()) {
        val parts = lines[0].trim().split(" ")
        if (parts.size == 2 && parts[0] == todayKey) {
            buildCount = parts[1].toInt() + 1
        }
    }
} catch (_: Exception) { /* 首次构建 */ }
try { counterFile.writeText("$todayKey $buildCount") } catch (_: Exception) {}
val versionNameDate = String.format("%s.%s.%04d", yy, mmdd, buildCount)
val appVersionCode = (System.currentTimeMillis() / 10000).toInt()

android {
    namespace = "top.vios.chat"
    compileSdk = 36

    defaultConfig {
        applicationId = "top.vios.chat"
        minSdk = 33
        targetSdk = 36
        versionCode = appVersionCode
        versionName = versionNameDate
        // 只打包 arm64（当前所有设备都是 64 位），减小 APK 体积
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2024.12.01"))
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    // 网络：WebSocket 中继 + HTTP 文件上传下载
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    // 内置中继服务器（NanoHTTPD：WebSocket + HTTP 一体，纯 Java，Android 兼容）
    implementation("org.nanohttpd:nanohttpd:2.3.1")
    implementation("org.nanohttpd:nanohttpd-websocket:2.3.1")
    // WebRTC：音视频通话
    implementation("io.github.webrtc-sdk:android:125.6422.03")
    // 二维码：生成（zxing core）+ 扫描（zxing-android-embedded，纯本地解码，不依赖 GMS）
    implementation("com.google.zxing:core:3.5.1")
    implementation("com.journeyapps:zxing-android-embedded:4.3.0")
    // PQC 后量子加密：ML-KEM-768（NIST FIPS 203，BouncyCastle 1.78+）
    implementation("org.bouncycastle:bcprov-jdk18on:1.85.2")
    // Android 12+ 官方 SplashScreen API（统一系统启动页与自定义封面）
    implementation("androidx.core:core-splashscreen:1.0.1")
}