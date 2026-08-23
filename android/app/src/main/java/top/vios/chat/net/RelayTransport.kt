package top.vios.chat.net

import kotlinx.coroutines.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import top.vios.chat.BuildConfig
import top.vios.chat.crypto.CryptoEngine
import java.io.File
import java.util.UUID
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * 云中继传输（WebSocket 中继，端到端加密）
 *
 * 架构:
 *   App → WebSocket → 中继服务器 → WebSocket → App
 *   文件: App → HTTP POST /upload → 中继 → HTTP GET /download → App
 *
 * 加密: 双方使用相同口令派生 AES-256-GCM 密钥（口令即密钥，中继不可见明文）
 * 中继仅转发密文，实现端到端安全
 *
 * 中继服务器地址在应用内配置（settings），默认留空（未配置时不可用）
 */
class RelayTransport(
    private val deviceName: String,
    override val deviceId: String,
    private val relayUrl: String,        // ws://host:port/ws
    private val httpBaseUrl: String,     // http://host:port (文件上传下载)
    private val roomId: String,
    private val passphrase: String
) : Transport {

    override val modeName = "云中继"

    private val connected = AtomicBoolean(false)
    private val connectStarted = AtomicBoolean(false)
    private var listener: TransportListener? = null
    private var webSocket: WebSocket? = null
    // 自动重连（长连接保活：断线指数退避重连）
    private var reconnectJob: Job? = null
    private var reconnectDelay = 5_000L
    private var manualDisconnect = false
    private var aesKey = CryptoEngine.deriveKeyFromPassphrase(passphrase, CryptoEngine.roomSalt(roomId))
    private var peerName = ""
    /** 更新服务推送的元信息（type="update" 时设置，MainActivity 读取后弹安装框） */
    @Volatile var updateMeta: FileMeta? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var heartbeatJob: Job? = null
    @Volatile private var lastPongTime = System.currentTimeMillis()
    @Volatile private var peerReady = false    // 对方已加入房间（配对完成）才启用超时检测
    private var reconnectAttempts = 0

    // 文件接收缓冲（按 fileId）
    private data class PendingFile(val name: String, val mime: String, val size: Long, val buf: java.io.ByteArrayOutputStream)
    private val pendingFiles = HashMap<String, PendingFile>()

    private val okHttp by lazy {
        OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(300, TimeUnit.SECONDS)
            .writeTimeout(300, TimeUnit.SECONDS)
            .build()
    }

    override fun isConnected() = connected.get()
    override fun peerName() = peerName

    override fun connect(listener: TransportListener) {
        // 防重复 connect（ChatScreen DisposableEffect 会再次调用）
        if (connectStarted.getAndSet(true)) {
            // 更新监听器（后续消息交给新 listener），不重复发起连接
            this.listener = listener
            if (connected.get()) {
                listener.onConnected(peerName)
            }
            return
        }
        this.listener = listener
        val request = Request.Builder().url(relayUrl).build()
        top.vios.chat.DevLog.i("Relay", "连接中 $relayUrl (room=$roomId)")
        val wsListener = object : WebSocketListener() {
            override fun onOpen(ws: WebSocket, response: Response) {
                // 加入房间
                val join = E2EMessage(
                    type = "join", id = UUID.randomUUID().toString(),
                    from = deviceName,
                        senderId = deviceId,
                    payload = JSONObject().apply {
                        put("room", roomId)
                        put("platform", "android")
                        put("version", BuildConfig.VERSION_NAME)
                    }
                )
                // join 用明文（仅含房间ID和名字，不含内容）
                ws.send(join.toJson().toString())
            }

            override fun onMessage(ws: WebSocket, text: String) {
                handleWsMessage(text)
            }

            override fun onClosed(ws: WebSocket, code: Int, reason: String) {
                connected.set(false)
                top.vios.chat.DevLog.w("Relay", "连接关闭 code=$code reason=$reason")
                listener?.onDisconnected("连接关闭: $reason")
                scheduleReconnect()
            }

            override fun onFailure(ws: WebSocket, t: Throwable, response: Response?) {
                connected.set(false)
                top.vios.chat.DevLog.e("Relay", "连接失败: ${t.message}", t)
                listener?.onError("中继连接失败: ${t.message}")
                scheduleReconnect()
            }
        }
        webSocket = okHttp.newWebSocket(request, wsListener)
    }

    override fun disconnect() {
        manualDisconnect = true
        reconnectJob?.cancel()
        connected.set(false)
        heartbeatJob?.cancel()
        try {
            webSocket?.close(1000, "bye")
        } catch (_: Exception) {}
        webSocket = null
    }

    /** 断线自动重连（指数退避 5s→10s→30s→60s，保持长连接） */
    private fun scheduleReconnect() {
        if (manualDisconnect) return
        reconnectJob?.cancel()
        reconnectJob = scope.launch {
            delay(reconnectDelay)
            if (!connected.get() && !manualDisconnect) {
                val savedListener = listener
                if (savedListener != null) {
                    connectStarted.set(false)
                    connect(savedListener)
                    reconnectDelay = minOf(reconnectDelay * 2, 60_000L)
                }
            }
        }
    }

    /** 启动应用层心跳保活 */
    private fun startHeartbeat() {
        heartbeatJob?.cancel()
        heartbeatJob = scope.launch {
            while (connected.get()) {
                delay(10_000)
                // 超时检测：仅在已配对（对方在房间）时启用。
                // 单人房间时 ping 无人应答，若检测会导致误断 —— 组网稳定关键！
                if (peerReady && System.currentTimeMillis() - lastPongTime > 45_000) {
                    connected.set(false)
                    listener?.onDisconnected("中继连接超时")
                    break
                }
                try {
                    sendPlain(type = "ping", payload = JSONObject().put("t", System.currentTimeMillis()))
                } catch (_: Exception) {
                    connected.set(false)
                    listener?.onDisconnected("中继连接异常")
                    break
                }
            }
        }
    }

    private fun handleWsMessage(text: String) {
        val msg = E2EMessage.fromJson(text)
        when (msg.type) {
            // 好友请求/同意（中继 HTTP API 推送的明文消息，非加密通道）
            "friend-request", "friend-accept", "friend-reject" -> {
                // 直接透传给上层（AppRoot 的 onTextMessage 会识别 JSON 并弹窗）
                listener?.onTextMessage(msg.from, msg.senderId, text)
            }
            // 远程命令（云端推送，明文）→ 透传上层执行并回复
            "__cmd__" -> {
                listener?.onTextMessage(msg.from, msg.senderId, text)
            }
            "welcome" -> {
                // 服务器确认加入，握手完成（双方口令相同即密钥相同）
                connected.set(true)
                reconnectDelay = 5_000L   // 连接成功重置重连退避
                lastPongTime = System.currentTimeMillis()
                // welcome 的 peer 字段是发送方自己的名字，不是对端名称
                // peerName 只通过 peer-joined 事件获取（对端真实名称）
                val wPeer = msg.payload.optString("peer", "")
                peerReady = !wPeer.contains("等待") && wPeer.isNotBlank() && wPeer != "对端"
                if (peerReady) lastPongTime = System.currentTimeMillis()
                listener?.onConnected(peerName.ifEmpty { "对端" })
                // 启动心跳保活（WebSocket 应用层 ping/pong，10s 间隔）
                startHeartbeat()
            }
            "peer-joined" -> {
                peerName = msg.payload.optString("name", "对端")
                peerReady = true
                lastPongTime = System.currentTimeMillis()   // 配对完成，重置超时计时
                listener?.onConnected(peerName)
            }
            "ping" -> {
                // 收到心跳 → 回 pong
                lastPongTime = System.currentTimeMillis()
                sendPlain(type = "pong", id = msg.id)
            }
            "pong" -> {
                lastPongTime = System.currentTimeMillis()
            }
            "text" -> {
                val content = decryptPayload(msg)
                if (content != null && content.isNotEmpty()) {
                    // 收到业务消息 → 自动回 ACK（与 iOS 一致，payload.ackId=原消息 id）
                    val ackId = msg.payload.optString("messageId", "")
                    if (ackId.isNotEmpty()) {
                        sendPlain(type = "ack", payload = JSONObject().put("ackId", ackId).put("target", msg.senderId))
                    }
                    listener?.onTextMessage(msg.from, msg.senderId, content)
                }
            }
            "ack" -> {
                // 送达确认：标记对端消息已送达（iOS 发来）
                val ackId = msg.payload.optString("ackId", "")
                if (ackId.isNotEmpty()) {
                    top.vios.chat.DevLog.i("Relay", "收到 ACK: $ackId")
                }
            }
            "audio" -> {
                // iOS type "voice" — 当前仅记录
                val data = decryptPayload(msg)
                if (data != null) {
                    val b64 = data
                    val mime = "audio/mp4"
                    if (b64.isNotEmpty()) {
                        try {
                            val audioData = java.util.Base64.getDecoder().decode(b64)
                            val meta = FileMeta(
                                fileId = msg.id,
                                name = "voice-${msg.id.take(8)}.m4a",
                                size = audioData.size.toLong(),
                                mime = mime
                            )
                            listener?.onFileReceived(meta, audioData)
                        } catch (_: Exception) {}
                    }
                }
            }
            "voice" -> {
                // iOS 语音：data=E2E加密的 {"data":"<b64>","mime":"...","durationMs":N}
                val content = decryptPayload(msg)
                if (content != null) {
                    try {
                        val inner = JSONObject(content)
                        val b64 = inner.optString("data", "")
                        val mime = inner.optString("mime", "audio/mp4")
                        if (b64.isNotEmpty()) {
                            val audioData = java.util.Base64.getDecoder().decode(b64)
                            val meta = FileMeta(
                                fileId = msg.id,
                                name = "voice-${msg.id.take(8)}.m4a",
                                size = audioData.size.toLong(),
                                mime = mime
                            )
                            listener?.onFileReceived(meta, audioData)
                        }
                    } catch (_: Exception) {}
                }
            }
            "image" -> {
                // iOS 图片：data=E2E加密的 {"data":"<b64>","name":..,"mime":..}
                val content = decryptPayload(msg)
                if (content != null) {
                    try {
                        val inner = JSONObject(content)
                        val b64 = inner.optString("data", "")
                        val name = inner.optString("name", "image.jpg")
                        val mime = inner.optString("mime", "image/jpeg")
                        if (b64.isNotEmpty()) {
                            val imgData = java.util.Base64.getDecoder().decode(b64)
                            val meta = FileMeta(fileId = msg.id, name = name, size = imgData.size.toLong(), mime = mime)
                            listener?.onFileReceived(meta, imgData)
                        }
                    } catch (_: Exception) {}
                }
            }
            "file" -> {
                val data = decryptPayload(msg)
                if (data != null) {
                    try {
                        val meta = FileMeta.fromJson(JSONObject(data))
                        pendingFiles[meta.fileId] = PendingFile(meta.name, meta.mime, meta.size, java.io.ByteArrayOutputStream())
                        scope.launch { downloadFile(meta) }
                    } catch (_: Exception) {}
                }
            }
            "update" -> {
                // EVO 更新服务推送（Hermes → relay 广播 → 设备弹安装）
                val data = decryptPayload(msg)
                if (data != null) {
                    try {
                        val meta = FileMeta.fromJson(JSONObject(data))
                        pendingFiles[meta.fileId] = PendingFile(meta.name, meta.mime, meta.size, java.io.ByteArrayOutputStream())
                        // 标记为更新包（带来源信息）
                        updateMeta = meta
                        scope.launch { downloadFile(meta) }
                    } catch (_: Exception) {}
                }
            }
        }
    }

    private fun decryptPayload(msg: E2EMessage): String? {
        return CryptoEngine.parseV1Payload(msg.payload, aesKey)
    }

    /** 加密并发送消息（v1：PBKDF2+AES-GCM envelope，与 iOS 一致） */
    private fun sendEncrypted(type: String, content: String, target: String? = null, messageId: String = "") {
        val payload = CryptoEngine.makeV1Payload(content, aesKey, CryptoEngine.roomSalt(roomId), target ?: "", messageId)
        val wrapper = E2EMessage(
            type = type, id = UUID.randomUUID().toString(),
            from = deviceName,
                        senderId = deviceId,
            payload = payload
        )
        webSocket?.send(wrapper.toJson().toString())
    }

    /** 发送明文帧（心跳/加入/在线查询等控制消息，与 iOS sendRaw 一致） */
    private fun sendPlain(type: String, payload: JSONObject = JSONObject(), id: String = UUID.randomUUID().toString(), target: String = "") {
        val msg = E2EMessage(
            type = type, id = id,
            from = deviceName,
                        senderId = deviceId,
            payload = payload
        )
        if (target.isNotEmpty()) msg.payload.put("target", target)
        webSocket?.send(msg.toJson().toString())
    }

    /** 发送加密文本（target=目标设备唯一ID，与 iOS sendText 一致） */
    override fun sendText(text: String, target: String?) {
        sendEncrypted(type = "text", content = text, target = target, messageId = UUID.randomUUID().toString())
    }

    /** 发送语音（与 iOS sendVoice 一致：JSON 打包后整体加密） */
    override fun sendAudio(audioData: ByteArray, mime: String, target: String?) {
        val b64 = java.util.Base64.getEncoder().encodeToString(audioData)
        val content = JSONObject().put("data", b64).put("mime", mime).put("durationMs", 0).toString()
        sendEncrypted(type = "voice", content = content, target = target, messageId = UUID.randomUUID().toString())
    }

    /** 发送文件：先上传到中继，再广播 file 元信息 */
    override fun sendFile(name: String, mime: String, data: ByteArray, target: String?) {
        val fileId = UUID.randomUUID().toString()
        scope.launch {
            try {
                val meta = FileMeta(fileId, name, data.size.toLong(), mime)
                listener?.onFileProgress(meta, 0, data.size.toLong())

                // 1. HTTP 上传
                val url = "$httpBaseUrl/upload?room=$roomId&fileId=$fileId"
                val body = data.toRequestBody("application/octet-stream".toMediaTypeOrNull())
                val req = Request.Builder().url(url).post(body).build()
                okHttp.newCall(req).execute().use { resp ->
                    if (!resp.isSuccessful) throw Exception("上传失败 HTTP ${resp.code}")
                }
                listener?.onFileProgress(meta, data.size.toLong(), data.size.toLong())

                // 2. 广播文件元信息（v1 加密，带 target 定向）
                val payload2 = CryptoEngine.makeV1Payload(meta.toJson().toString(), aesKey, CryptoEngine.roomSalt(roomId), target ?: "", fileId)
                val wrapper = E2EMessage(
                    type = "file", id = fileId, from = deviceName,
                        senderId = deviceId,
                    payload = payload2
                )
                webSocket?.send(wrapper.toJson().toString())
            } catch (e: Exception) {
                listener?.onError("文件发送失败: ${e.message}")
            }
        }
    }

    /** 下载中继上的文件 */
    private suspend fun downloadFile(meta: FileMeta) {
        try {
            val url = "$httpBaseUrl/download?room=$roomId&fileId=${meta.fileId}"
            val req = Request.Builder().url(url).get().build()
            okHttp.newCall(req).execute().use { resp ->
                if (!resp.isSuccessful) throw Exception("下载失败 HTTP ${resp.code}")
                val bytes = resp.body?.bytes() ?: ByteArray(0)
                listener?.onFileReceived(meta, bytes)
            }
        } catch (e: Exception) {
            listener?.onError("文件接收失败: ${e.message}")
        }
    }
}