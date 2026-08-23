package top.vios.chat.net

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.content.Context
import kotlinx.coroutines.*
import org.json.JSONObject
import top.vios.chat.crypto.CryptoEngine
import java.io.DataInputStream
import java.io.IOException
import java.io.OutputStream
import java.security.KeyPair
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

/**
 * 蓝牙直连传输层（RFCOMM/SPP）
 * 复用 LanTransport 的 ECDH 握手 + AES-GCM 加密 + 帧协议 + 心跳保活，
 * 仅将 TCP Socket 替换为 BluetoothSocket —— 无 Wi-Fi/无网络场景的近距离通信。
 */
class BtTransport(
    private val context: Context,
    private val deviceName: String,
    override val deviceId: String,
    private val mode: Mode,                 // SERVER / CLIENT
    private val targetDevice: BluetoothDevice? = null   // CLIENT 模式目标设备
) : Transport {

    enum class Mode { SERVER, CLIENT }

    override val modeName = "蓝牙直连"

    companion object {
        /** 标准 SPP 服务 UUID */
        val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
        const val SERVICE_NAME = "EVO"
    }

    private val connected = AtomicBoolean(false)
    private val connectStarted = AtomicBoolean(false)
    private var listener: TransportListener? = null
    private var btSocket: BluetoothSocket? = null
    private var serverSocket: BluetoothServerSocket? = null
    private var keyPair: KeyPair = CryptoEngine.generateKeyPair()
    private var aesKey: javax.crypto.SecretKey? = null
    private var peerName = ""
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var readerJob: Job? = null
    private var serverJob: Job? = null
    private var heartbeatJob: Job? = null
    private val pendingFiles = HashMap<String, PendingFileRecv>()
    @Volatile private var lastPongTime = System.currentTimeMillis()

    data class PendingFileRecv(
        val name: String,
        val mime: String,
        val size: Long,
        val buf: java.io.ByteArrayOutputStream
    )

    override fun isConnected() = connected.get()
    override fun peerName() = peerName

    override fun connect(listener: TransportListener) {
        if (connectStarted.getAndSet(true)) {
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
        try { btSocket?.close() } catch (_: Exception) {}
        try { serverSocket?.close() } catch (_: Exception) {}
        listener = null
    }

    private fun runServer() {
        try {
            val adapter = BluetoothAdapter.getDefaultAdapter() ?: throw IOException("蓝牙不可用")
            serverSocket = adapter.listenUsingRfcommWithServiceRecord(SERVICE_NAME, SPP_UUID)
            // 等待对端连接（阻塞，蓝牙配对后自动建立）
            val s = serverSocket?.accept()
            serverSocket?.close()
            btSocket = s
            if (s == null) throw IOException("蓝牙连接被拒绝")
            handshake(s)
            readerJob = scope.launch { readLoop(s) }
        } catch (e: Exception) {
            if (connected.get()) listener?.onError("蓝牙服务端错误: ${e.message}")
            else listener?.onError("蓝牙服务端错误: ${e.message}")
        }
    }

    private fun runClient() {
        val target = targetDevice ?: run {
            listener?.onError("未选择蓝牙设备")
            return
        }
        try {
            val s = target.createRfcommSocketToServiceRecord(SPP_UUID)
            btSocket = s
            s.connect()   // 阻塞直到建立（蓝牙配对弹窗后自动）
            handshake(s)
            readerJob = scope.launch { readLoop(s) }
        } catch (e: Exception) {
            connectStarted.set(false)
            listener?.onError("蓝牙连接失败: ${e.message}")
        }
    }

    /** ECDH 握手（与 LanTransport 相同协议） */
    private fun handshake(s: BluetoothSocket) {
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

        // 心跳保活（蓝牙 RFCOMM 无 TCP keepalive，应用层心跳更关键）
        heartbeatJob = scope.launch {
            while (connected.get()) {
                delay(10_000)
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

        // 2. 分块发送 (32KB —— 蓝牙带宽有限，用更小块降低延迟)
        val chunkSize = 32 * 1024
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
            Thread.sleep(5)
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
        val out = btSocket?.getOutputStream() ?: return
        writeFrame(out, 1, enc)
    }

    private fun readLoop(s: BluetoothSocket) {
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
                listener?.onDisconnected("蓝牙连接断开: ${e.message}")
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
                val pong = E2EMessage(
                    type = "pong", id = msg.id,
                    from = deviceName,
                    senderId = deviceId,
                    payload = JSONObject()
                )
                sendEncrypted(pong.toJson().toString())
            }
            "pong" -> {
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

    /* ============ 帧协议（与 LanTransport 相同） ============ */

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
