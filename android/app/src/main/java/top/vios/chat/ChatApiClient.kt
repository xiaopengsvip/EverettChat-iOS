package top.vios.chat

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import javax.net.ssl.HttpsURLConnection

/**
 * 聊天 API 客户端 — 内置 b.ai 配置
 */
object ApiConfig {
    const val BASE_URL = "https://relay.vios.top/ai"   // 经 Cloudflare 中继代理访问 b.ai（国内直连可用）
    // 不带 key：relay 自动使用服务端 AI_KEYS 轮询池（账号A），key 不写入 APK
    const val API_KEY = ""
    const val MODEL = "deepseek-v4-flash"              // 默认文本模型
    const val VISION_MODEL = "deepseek-v4-flash-vision-exp"  // 视觉模型（图片分析）
    const val HY3_MODEL = "hy3"                        // 混合模型 hy3
    const val SYSTEM_PROMPT = "你是 Everett 的 AI 助手，一个乐于助人、知识渊博的智能助手。请用简洁清晰的语言回答问题。"

    /** 可选模型列表（App 内切换） */
    data class AiModelInfo(val id: String, val name: String, val desc: String, val vision: Boolean)
    val MODELS = listOf(
        AiModelInfo("deepseek-v4-flash", "DeepSeek V4", "通用文本 · 快", vision = false),
        AiModelInfo("deepseek-v4-flash-vision-exp", "DeepSeek 视觉", "图片/文件分析", vision = true),
        AiModelInfo("hy3", "Hy3", "混合模型", vision = false)
    )
}

data class ChatMessage(
    val role: String,      // "user" | "assistant"
    val content: String,
    val imageBase64: String? = null   // 图片附件（base64 data URI，仅 user 消息）
)

class ChatApiClient {

    private var currentConn: HttpURLConnection? = null
    private val cancelFlag = java.util.concurrent.atomic.AtomicBoolean(false)

    /** 取消当前流式请求 */
    fun cancel() {
        cancelFlag.set(true)
        try { currentConn?.disconnect() } catch (_: Exception) {}
    }

    /**
     * 发送消息，通过回调流式接收回复
     * @param history 历史消息
     * @param userMessage 用户新消息
     * @param onDelta 流式增量回调
     * @return 完整回复（null = 已取消）
     */
    suspend fun sendMessage(
        history: List<ChatMessage>,
        userMessage: String,
        onDelta: (String, Boolean) -> Unit,   // (增量文本, 是否思考过程 reasoning)
        imageBase64: String? = null,
        model: String = ApiConfig.MODEL       // 模型 ID（默认 deepseek-v4-flash）
    ): String? = withContext(Dispatchers.IO) {
        cancelFlag.set(false)
        val messages = JSONArray()
        messages.put(JSONObject().put("role", "system").put("content", ApiConfig.SYSTEM_PROMPT))
        history.forEach { m ->
            if (m.imageBase64 != null) {
                val content = JSONArray()
                content.put(JSONObject().put("type", "text").put("text", m.content))
                content.put(JSONObject().put("type", "image_url")
                    .put("image_url", JSONObject().put("url", m.imageBase64)))
                messages.put(JSONObject().put("role", m.role).put("content", content))
            } else {
                messages.put(JSONObject().put("role", m.role).put("content", m.content))
            }
        }
        // 当前用户消息：图片走 vision 模型
        val hasImage = imageBase64 != null
        if (hasImage) {
            val content = JSONArray()
            content.put(JSONObject().put("type", "text").put("text", userMessage))
            content.put(JSONObject().put("type", "image_url")
                .put("image_url", JSONObject().put("url", imageBase64)))
            messages.put(JSONObject().put("role", "user").put("content", content))
        } else {
            messages.put(JSONObject().put("role", "user").put("content", userMessage))
        }

        val body = JSONObject()
            .put("model", if (hasImage) ApiConfig.VISION_MODEL else model)   // 图片强制视觉模型
            .put("messages", messages)
            .put("stream", true)
            .put("temperature", 0.7)
            .put("max_tokens", 2048)   // 推理模型需要足够 token（思考+回答）

        val conn = URL("${ApiConfig.BASE_URL}/chat/completions").openConnection() as HttpsURLConnection
        currentConn = conn
        try {
            conn.requestMethod = "POST"
            conn.connectTimeout = 30000
            conn.readTimeout = 120000
            conn.setRequestProperty("Content-Type", "application/json")
            // 带 key 才发 Authorization；不带则 relay 自动用服务端 AI_KEYS 轮询池
            if (ApiConfig.API_KEY.isNotEmpty()) {
                conn.setRequestProperty("Authorization", "Bearer ${ApiConfig.API_KEY}")
            }
            conn.setRequestProperty("Accept-Encoding", "identity")   // 禁用 gzip（流式 SSE 需要实时解压）
            conn.doOutput = true

            OutputStreamWriter(conn.outputStream, "UTF-8").use { it.write(body.toString()) }

            val responseCode = conn.responseCode
            if (responseCode != 200) {
                val err = conn.errorStream?.bufferedReader()?.use { it.readText() } ?: "HTTP $responseCode"
                throw RuntimeException("API 错误 ($responseCode): $err")
            }

            val full = StringBuilder()          // 最终内容（content，优先）
            val reasoningFull = StringBuilder()  // 思考过程（reasoning_content）
            val reader = BufferedReader(InputStreamReader(conn.inputStream, "UTF-8"))
            var line: String?
            var lineCount = 0
            // ===== Streaming 节流：50ms 合并一次 UI 更新（避免每 Token 全量重组） =====
            val deltaBuf = StringBuilder()
            val reasoningBuf = StringBuilder()
            var lastFlush = System.currentTimeMillis()
            suspend fun flushDelta() {
                if (deltaBuf.isEmpty() && reasoningBuf.isEmpty()) return
                val d = deltaBuf.toString()
                val r = reasoningBuf.toString()
                deltaBuf.clear()
                reasoningBuf.clear()
                if (r.isNotEmpty()) withContext(Dispatchers.Main) { onDelta(r, true) }
                if (d.isNotEmpty()) withContext(Dispatchers.Main) { onDelta(d, false) }
            }
            while (reader.readLine().also { line = it } != null) {
                if (cancelFlag.get()) return@withContext null
                val l = line ?: continue
                lineCount++
                if (lineCount <= 3) {
                    android.util.Log.i("ChatApiDebug", "SSE line: ${l.take(200)}")
                }
                if (!l.startsWith("data:")) continue
                val data = l.removePrefix("data:").trim()
                if (data.isEmpty() || data == "[DONE]") continue
                try {
                    val json = JSONObject(data)
                    // choices 是 JSON 数组！不是对象！（optJSONObject 会静默返回 null → 解析全丢）
                    val choices = json.optJSONArray("choices")
                    val d = choices?.optJSONObject(0)?.optJSONObject("delta")
                    if (d == null) continue
                    // 推理模型（deepseek-v4-flash）先输出 reasoning_content，再输出 content
                    // content 进 full（最终回复）；reasoning 进 reasoningFull（思考过程也流式显示）
                    // ⚠️ 显式 null 时 optString 返回字符串 "null"！必须用 isNull 判断
                    val content = if (d.isNull("content")) "" else d.optString("content", "")
                    val reasoning = if (d.isNull("reasoning_content")) "" else d.optString("reasoning_content", "")
                    if (reasoning.isNotEmpty()) {
                        reasoningFull.append(reasoning)
                        reasoningBuf.append(reasoning)
                    }
                    if (content.isNotEmpty()) {
                        full.append(content)
                        deltaBuf.append(content)
                    }
                    val now = System.currentTimeMillis()
                    if (now - lastFlush >= 50) {
                        flushDelta()
                        lastFlush = now
                    }
                } catch (_: Exception) {
                    // 跳过解析失败的行
                }
            }
            flushDelta()   // 循环结束 flush 剩余
            android.util.Log.i("ChatApiDebug", "SSE done, lines=$lineCount, fullLen=${full.length}, reasoningLen=${reasoningFull.length}, full=${full.take(100)}")
            full.toString()
        } finally {
            currentConn = null
            conn.disconnect()
        }
    }
}