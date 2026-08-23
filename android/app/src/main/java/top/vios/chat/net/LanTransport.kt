package top.vios.chat.net

import android.util.Log
import kotlinx.coroutines.*
import org.json.JSONObject
import top.vios.chat.crypto.CryptoEngine
import java.io.*
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.security.KeyPair
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

/**
 * 局域网直连传输（端到端加密）
 *
 * 协议: TCP + 帧协议
 *   [4B 长度][1B 类型][payload]
 *   type 0 = 握手明文(JSON)   type 1 = 加密数据
 * 握手: ECDH 交换公钥 → AES-256-GCM
 * 文件: 64KB 分块，每块独立加密
 *
 * 角色: 一方 listen(ServerSocket)，另一方 connect(IP:port)
 */
class LanTransport(
    private val deviceName: String,
    override val deviceId: String,
    private val mode: Mode,            // SERVER / CLIENT
    private val listenPort: Int = 44777,
    private val serverHost: String = "",
    private val serverPort: Int = 44777
) : Transport {

    enum class Mode { SERVER, CLIENT }

    override val modeName = "局域网直连"

    private val connected = AtomicBoolean(false)
    private val connectStarted = AtomicBoolean(false)
    private var listener: TransportListener? = null
    private var socket: Socket? = null
    private var keyPair: KeyPair = CryptoEngine.generateKeyPair()
    private var aesKey: javax.crypto.SecretKey? = null
    private var peerName = ""
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var readerJob: Job? = null
    private var serverJob: Job? = null
    private var heartbeatJob: Job? = null
    private var discovery: LanDiscovery? = null
    private val pendingFiles = HashMap<String, PendingFileRecv>()
    @Volatile private var lastPongTime = System.currentTimeMillis()   // 最近一次心跳应答时间

    data class PendingFileRecv(
        val name: String,
        val mime: String,
        val size: Long,
        val buf: java.io.ByteArrayOutputStream
    )

    /** 设置设备发现（服务端模式常驻响应广播探测） */
    fun attachDiscovery(d: LanDiscovery) {
        discovery = d
    }

    override fun isConnected() = connected.get()
    override fun peerName() = peerName

    override fun connect(listener: TransportListener) {
        // B1 修复: 防止重复 connect（ChatScreen DisposableEffect 会再次调用）
        if (connectStarted.getAndSet(true)) {
            // 更新监听器（后续消息交给新 listener），不重复发起连接
            this.listener = listener
            if (connected.get()) {
                listener.onConnected(peerName)
            }
            return
        }
        this.listener = listener
        when (mode) {
            Mode.SERVER -> serverJob = scope.launch { runServer() }
            Mode.CLIENT -> scope.launch { runClient() }
        }
    }

    override fun disconnect() {
        connected.set(false)
        connectStarted.set(true)
        readerJob?.cancel()
        serverJob?.cancel()
        heartbeatJob?.cancel()
        try { socket?.close() } catch (_: Exception) {}
        listener = null
    }

    private fun runServer() {
        try {
            val ss = ServerSocket(listenPort)
            ss.reuseAddress = true
            // B2 修复: 不再提前回调 onConnected（accept 前未真正建立连接）
            // 等待对端连接
            val s = ss.accept()
            socket = s
            handshake(s)
            readerJob = scope.launch { readLoop(s) }
        } catch (e: Exception) {
            if (connected.get()) listener?.onError("服务端错误: ${e.message}")
        }
    }

    private fun runClient() {
        try {
            val s = Socket()
            s.connect(java.net.InetSocketAddress(serverHost, serverPort), 15000)
            socket = s
            handshake(s)
            readerJob = scope.launch { readLoop(s) }
        } catch (e: Exception) {
            // 允许失败后重试
            connectStarted.set(false)
            listener?.onError("连接失败: ${e.message}")
        }
    }

    /** ECDH 握手 */
    private fun handshake(s: Socket) {
        val out = s.getOutputStream()
        // 发送我的公钥
        val hello = JSONObject()
            .put("type", "hello")
            .put("name", deviceName)
            .put("pub", CryptoEngine.pubKeyToBase64(keyPair.public))
        writeFrame(out, 0, hello.toString().toByteArray())

        // 读取对端公钥
        val inStream = DataInputStream(s.getInputStream())
        val resp = readFrame(inStream)
        if (resp == null || resp.first != 0) throw IOException("握手失败")
        val peer = JSONObject(String(resp.second))
        val peerPub = CryptoEngine.pubKeyFromBase64(peer.getString("pub"))
        peerName = peer.optString("name", "对端")

        // 派生共享密钥
        aesKey = CryptoEngine.ecdhSharedSecret(keyPair.private, peerPub)
        connected.set(true)

        // 启动心跳保活（10s 间隔发送，45s 无应答判定断线）
        heartbeatJob = scope.launch {
            while (connected.get()) {
                delay(10_000)
                // 超时检测：超过 45s 没收到任何 pong → 判定断线
                if (System.currentTimeMillis() - lastPongTime > 45_000) {
                    connected.set(false)
                    listener?.onDisconnected("连接超时（对方无响应）")
                    break
                }
                try {
                    val ping = E2EMessage(
                        type = "ping", id = UUID.randomUUID().toString(),
                        from = deviceName,
                        senderId = deviceId,
                        payload = JSONObject().put("t", System.currentTimeMillis())
                    )
                    sendEncrypted(ping.toJson().toString())
                } catch (_: Exception) {
                    connected.set(false)
                    listener?.onDisconnected("连接超时")
                    break
                }
            }
        }

        listener?.onConnected(peerName)
    }

    override fun sendText(text: String, target: String?) {
        val msg = E2EMessage(
            type = "text", id = UUID.randomUUID().toString(),
            from = deviceName,
                        senderId = deviceId,
            payload = JSONObject().put("content", text)
        )
        sendEncrypted(msg.toJson().toString())
    }

    /** 发送语音消息（AAC/M4A，Base64 封装走加密帧） */
    override fun sendAudio(audioData: ByteArray, mime: String, target: String?) {
        val msg = E2EMessage(
            type = "audio", id = UUID.randomUUID().toString(),
            from = deviceName,
                        senderId = deviceId,
            payload = JSONObject()
                .put("data", java.util.Base64.getEncoder().encodeToString(audioData))
                .put("mime", mime)
        )
        sendEncrypted(msg.toJson().toString())
    }

    override fun sendFile(name: String, mime: String, data: ByteArray, target: String?) {
        val fileId = UUID.randomUUID().toString()
        val key = aesKey ?: return

        // 1. 文件元信息
        val meta = E2EMessage(
            type = "file", id = fileId, from = deviceName,
                        senderId = deviceId,
            payload = FileMeta(fileId, name, data.size.toLong(), mime).toJson()
        )
        sendEncrypted(meta.toJson().toString())
        listener?.onFileProgress(FileMeta(fileId, name, data.size.toLong(), mime), 0, data.size.toLong())

        // 2. 分块发送 (64KB)
        val chunkSize = 64 * 1024
        var offset = 0
        val keyFinal = key
        while (offset < data.size) {
            val end = minOf(offset + chunkSize, data.size)
            val chunk = data.copyOfRange(offset, end)
            val enc = CryptoEngine.encryptCombined(keyFinal, chunk)
            val chunkMsg = E2EMessage(
                type = "file-chunk", id = fileId, from = deviceName,
                        senderId = deviceId,
                payload = JSONObject()
                    .put("fileId", fileId)
                    .put("data", java.util.Base64.getEncoder().encodeToString(enc))
            )
            sendEncrypted(chunkMsg.toJson().toString())
            offset = end
            listener?.onFileProgress(FileMeta(fileId, name, data.size.toLong(), mime), offset.toLong(), data.size.toLong())
            Thread.sleep(2)
        }

        // 3. 结束标记
        val endMsg = E2EMessage(
            type = "file-end", id = fileId, from = deviceName,
                        senderId = deviceId,
            payload = JSONObject().put("fileId", fileId)
        )
        sendEncrypted(endMsg.toJson().toString())
    }

    private fun sendEncrypted(json: String) {
        val key = aesKey ?: return
        val enc = CryptoEngine.encryptCombined(key, json.toByteArray())
        val out = socket?.getOutputStream() ?: return
        writeFrame(out, 1, enc)
    }

    private fun readLoop(s: Socket) {
        try {
            val din = DataInputStream(s.getInputStream())
            while (connected.get()) {
                val frame = readFrame(din) ?: break
                if (frame.first == 1) {
                    val key = aesKey ?: continue
                    val dec = CryptoEngine.decrypt(key, frame.second)
                    handleMessage(String(dec))
                }
            }
        } catch (e: Exception) {
            if (connected.get()) {
                connected.set(false)
                listener?.onDisconnected("连接断开: ${e.message}")
            }
        }
    }

    private fun handleMessage(json: String) {
        val msg = E2EMessage.fromJson(json)
        when (msg.type) {
            "text" -> {
                val content = msg.payload.optString("content", "")
                listener?.onTextMessage(msg.from, msg.senderId, content)
            }
            "audio" -> {
                // 语音消息（走 payload.data Base64）
                val b64 = msg.payload.optString("data", "")
                val mime = msg.payload.optString("mime", "audio/mp4")
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
            "ping" -> {
                // B7 修复: 收到心跳立即回 pong
                val pong = E2EMessage(
                    type = "pong", id = msg.id,
                    from = deviceName,
                        senderId = deviceId,
                    payload = JSONObject()
                )
                sendEncrypted(pong.toJson().toString())
            }
            "pong" -> {
                // 心跳回复（连接活性确认）
                lastPongTime = System.currentTimeMillis()
            }
            "file" -> {
                val meta = FileMeta.fromJson(msg.payload)
                pendingFiles[meta.fileId] = PendingFileRecv(meta.name, meta.mime, meta.size, java.io.ByteArrayOutputStream())
            }
            "file-chunk" -> {
                val fileId = msg.payload.optString("fileId", "")
                val pending = pendingFiles[fileId] ?: return
                val enc = java.util.Base64.getDecoder().decode(msg.payload.getString("data"))
                val key = aesKey ?: return
                try {
                    val dec = CryptoEngine.decrypt(key, enc)
                    pending.buf.write(dec)
                } catch (_: Exception) {}
            }
            "file-end" -> {
                val fileId = msg.payload.optString("fileId", "")
                val pending = pendingFiles.remove(fileId) ?: return
                val received = pending.buf.toByteArray()
                // B6 修复: 校验接收完整度
                if (received.size.toLong() != pending.size) {
                    listener?.onError("文件接收不完整: ${pending.name} (${received.size}/${pending.size} bytes)")
                    return
                }
                val meta = FileMeta(fileId, pending.name, pending.size, pending.mime)
                listener?.onFileReceived(meta, received)
            }
            "bye" -> {
                connected.set(false)
                listener?.onDisconnected("对方已断开")
            }
        }
    }

    /* ============ 帧协议 ============ */

    private fun writeFrame(out: OutputStream, type: Int, payload: ByteArray) {
        synchronized(this) {
            val header = ByteArray(5)
            header[0] = (payload.size ushr 24).toByte()
            header[1] = (payload.size ushr 16).toByte()
            header[2] = (payload.size ushr 8).toByte()
            header[3] = payload.size.toByte()
            header[4] = type.toByte()
            out.write(header)
            out.write(payload)
            out.flush()
        }
    }

    private fun readFrame(din: DataInputStream): Pair<Int, ByteArray>? {
        val header = ByteArray(5)
        din.readFully(header)
        val len = ((header[0].toInt() and 0xFF) shl 24) or
                  ((header[1].toInt() and 0xFF) shl 16) or
                  ((header[2].toInt() and 0xFF) shl 8) or
                  (header[3].toInt() and 0xFF)
        val type = header[4].toInt()
        if (len < 0 || len > 512 * 1024 * 1024) throw IOException("非法帧长度: $len")
        val payload = ByteArray(len)
        din.readFully(payload)
        return Pair(type, payload)
    }
}