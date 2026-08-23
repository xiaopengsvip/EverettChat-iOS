package top.vios.chat

import android.content.Context
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 开发者模式：内存环形日志 + 崩溃捕获 + 远程上报（无 adb 设备远程调试）
 *
 * 用法：
 *   DevLog.i("Chat", "消息")
 *   DevLog.e("Chat", "错误", exception)
 *   DevLog.upload(context)          // 手动上传
 *   DevLog.getRecentLogs()          // 查看内存日志
 *
 * 云端：POST https://relay.vios.top/log   （relay-worker.js /log 端点）
 * 查看：GET  https://relay.vios.top/log?device=<deviceId>
 */
object DevLog {

    private const val MAX_BUFFER = 500          // 内存环形缓冲上限
    private const val CRASH_FILE = "dev_crash.log"
    private const val CRASH_FLAG = "dev_crash_flag"

    private val buffer = ArrayDeque<JSONObject>()   // {t, lvl, msg}

    @Synchronized
    fun i(tag: String, msg: String) = append("info", tag, msg)

    @Synchronized
    fun w(tag: String, msg: String) = append("warn", tag, msg)

    @Synchronized
    fun e(tag: String, msg: String, tr: Throwable? = null) {
        val full = if (tr != null) "$msg\n${android.util.Log.getStackTraceString(tr)}" else msg
        append("error", tag, full)
    }

    @Synchronized
    private fun append(lvl: String, tag: String, msg: String) {
        val entry = JSONObject()
            .put("t", System.currentTimeMillis())
            .put("lvl", lvl)
            .put("msg", "[$tag] $msg")
        buffer.addLast(entry)
        while (buffer.size > MAX_BUFFER) buffer.removeFirst()
    }

    /** 最近日志（新在前） */
    @Synchronized
    fun getRecentLogs(limit: Int = 100): List<JSONObject> {
        val list = buffer.toList()
        return list.takeLast(limit).reversed()
    }

    /** 初始化崩溃捕获（MainActivity onCreate 调用） */
    fun initCrashHandler(context: Context) {
        val prev = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                val stack = android.util.Log.getStackTraceString(throwable)
                val crash = StringBuilder()
                    .append("=== CRASH ")
                    .append(SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date()))
                    .append(" ===\n")
                    .append("Thread: ").append(thread.name).append('\n')
                    .append("Version: ").append(BuildConfig.VERSION_NAME).append('\n')
                    .append("SDK: ").append(Build.VERSION.SDK_INT).append(" / ").append(Build.MODEL).append('\n')
                    .append(stack)
                // 存文件（下次启动上传）
                context.openFileOutput(CRASH_FILE, Context.MODE_APPEND).use { it.write((crash.toString() + "\n\n").toByteArray()) }
                context.getSharedPreferences("dev_log", Context.MODE_PRIVATE)
                    .edit().putBoolean(CRASH_FLAG, true).apply()
                append("error", "Crash", crash.toString())
            } catch (_: Exception) {}
            prev?.uncaughtException(thread, throwable)
        }
    }

    /** 是否有未上传的崩溃日志 */
    fun hasPendingCrash(context: Context): Boolean =
        context.getSharedPreferences("dev_log", Context.MODE_PRIVATE).getBoolean(CRASH_FLAG, false)

    /** 读取崩溃日志文件 */
    fun readCrashLog(context: Context): String {
        return try {
            context.openFileInput(CRASH_FILE).bufferedReader().use { it.readText() }
        } catch (_: Exception) { "" }
    }

    /** 上传日志到云端（网络请求，主线程外调用） */
    suspend fun upload(context: Context): String {
        return kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
            try {
                val deviceId = DeviceIdentity.getDeviceId(context)
                val deviceName = DeviceNameManager.getDeviceName(context)

                // 崩溃日志合并进上传内容
                val crash = readCrashLog(context)
                val logs = JSONArray()
                buffer.toList().forEach { logs.put(it) }
                if (crash.isNotBlank()) {
                    logs.put(JSONObject()
                        .put("t", System.currentTimeMillis())
                        .put("lvl", "error")
                        .put("msg", "--- 历史崩溃 ---\n$crash"))
                }
                if (logs.length() == 0) return@withContext "无日志可上传"

                val body = JSONObject()
                    .put("deviceId", deviceId)
                    .put("device", deviceName)
                    .put("version", BuildConfig.VERSION_NAME)
                    .put("logs", logs)
                    .toString()

                val conn = java.net.URL("${top.vios.chat.net.PublicRelay.HTTP_URL}/log").openConnection() as java.net.HttpURLConnection
                conn.requestMethod = "POST"
                conn.doOutput = true
                conn.setRequestProperty("Content-Type", "application/json")
                conn.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36")
                conn.connectTimeout = 10000
                conn.readTimeout = 10000
                conn.outputStream.use { it.write(body.toByteArray()) }
                val resp = conn.inputStream?.bufferedReader()?.use { it.readText() } ?: "{}"
                val ok = org.json.JSONObject(resp).optBoolean("ok", false)

                if (ok) {
                    // 上传成功后清除崩溃标记与文件
                    context.getSharedPreferences("dev_log", Context.MODE_PRIVATE)
                        .edit().putBoolean(CRASH_FLAG, false).apply()
                    context.deleteFile(CRASH_FILE)
                    "已上传 ${logs.length()} 条日志"
                } else {
                    "上传失败: $resp"
                }
            } catch (e: Exception) {
                "上传失败: ${e.message ?: "网络错误"}"
            }
        }
    }
}
