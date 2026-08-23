package top.vios.chat.net

import org.json.JSONArray
import org.json.JSONObject

/**
 * 端到端消息模型
 * senderId = 发送者设备唯一 ID（身份判断依据）
 * from = 发送者显示名（仅展示用）
 */
data class E2EMessage(
    val type: String,          // text | file | file-chunk | file-end | ack | hello | bye | ping | pong
    val id: String,
    val from: String,          // 设备显示名（展示用）
    val senderId: String,      // 设备唯一 ID（身份区分）
    val payload: JSONObject    // 具体内容
) {
    fun toJson(): JSONObject = JSONObject()
        .put("type", type)
        .put("id", id)
        .put("from", from)
        .put("senderId", senderId)
        .put("payload", payload)

    companion object {
        fun fromJson(s: String): E2EMessage {
            val o = JSONObject(s)
            return E2EMessage(
                type = o.getString("type"),
                id = o.optString("id", ""),
                from = o.optString("from", ""),
                senderId = o.optString("senderId", ""),
                payload = o.optJSONObject("payload") ?: JSONObject()
            )
        }
    }
}

/** 文件消息载荷 */
data class FileMeta(
    val fileId: String,
    val name: String,
    val size: Long,
    val mime: String
) {
    fun toJson(): JSONObject = JSONObject()
        .put("fileId", fileId)
        .put("name", name)
        .put("size", size)
        .put("mime", mime)

    companion object {
        fun fromJson(o: JSONObject) = FileMeta(
            fileId = o.getString("fileId"),
            name = o.optString("name", "file"),
            size = o.optLong("size", 0),
            mime = o.optString("mime", "application/octet-stream")
        )
    }
}

/** 传输层回调 */
interface TransportListener {
    fun onConnected(peerName: String)
    fun onDisconnected(reason: String)
    fun onTextMessage(from: String, senderId: String, text: String)
    fun onFileReceived(meta: FileMeta, data: ByteArray)
    fun onFileProgress(meta: FileMeta, sent: Long, total: Long)
    fun onError(message: String)
}

/** 传输层抽象：局域网直连 / 云中继 */
interface Transport {
    val modeName: String
    val deviceId: String          // 本机设备唯一 ID
    fun connect(listener: TransportListener)
    fun disconnect()
    /** 发送文本（target = 目标设备唯一 ID，null=房间广播） */
    fun sendText(text: String, target: String? = null)
    fun sendAudio(audioData: ByteArray, mime: String = "audio/mp4", target: String? = null)
    fun sendFile(name: String, mime: String, data: ByteArray, target: String? = null)
    fun isConnected(): Boolean
    fun peerName(): String
}