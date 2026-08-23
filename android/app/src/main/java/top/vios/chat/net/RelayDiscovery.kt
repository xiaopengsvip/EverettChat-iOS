package top.vios.chat.net

import android.content.Context
import android.net.wifi.WifiManager
import android.util.Log
import kotlinx.coroutines.*
import org.json.JSONObject
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress

/**
 * 局域网中继自动发现
 *
 * 机制（与 LanDiscovery 同思路，UDP 广播）:
 *   - 中继设备：每 5 秒向 255.255.255.255:44780 广播 announce（含设备名/IP/端口）
 *   - 客户端设备：监听 44780，收到 announce → 回调 onRelayFound，自动配置中继地址
 *
 * 同一局域网内任意设备开启中继，其他装 App 的设备自动发现并可一键连接。
 */
class RelayDiscovery(private val context: Context) {

    companion object {
        private const val TAG = "RelayDiscovery"
        const val PORT = 44780
        const val ANNOUNCE_INTERVAL_MS = 10_000L
        private const val BROADCAST_ADDR = "255.255.255.255"
        private const val TYPE = "relay-announce"
    }

    data class RelayNode(
        val name: String,
        val ip: String,
        val port: Int,
        val nodeId: String = ""
    ) {
        val wsUrl: String get() = RelayServer.relayWsAddress(ip, port)
        val httpUrl: String get() = RelayServer.relayHttpAddress(ip, port)
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var announceJob: Job? = null
    private var listenJob: Job? = null
    private var multicastLock: WifiManager.MulticastLock? = null

    // 最近发现的节点（ip:port 去重）
    private val foundNodes = LinkedHashMap<String, RelayNode>()
    private var onRelayFound: ((RelayNode) -> Unit)? = null

    /** 中继设备：开始周期广播（每 10s） */
    fun startAnnounce(name: String, ip: String, port: Int, nodeId: String = "") {
        stopAnnounce()
        announceJob = scope.launch {
            while (isActive) {
                try {
                    val payload = JSONObject()
                        .put("type", TYPE)
                        .put("name", name)
                        .put("ip", ip)
                        .put("port", port)
                        .put("nodeId", nodeId)
                        .toString()
                    val bytes = payload.toByteArray()
                    val socket = DatagramSocket()
                    socket.broadcast = true
                    val packet = DatagramPacket(bytes, bytes.size, InetAddress.getByName(BROADCAST_ADDR), PORT)
                    socket.send(packet)
                    socket.close()
                    Log.i(TAG, "广播中继: $ip:$port")
                } catch (e: Exception) {
                    Log.e(TAG, "广播失败: ${e.message}")
                }
                delay(ANNOUNCE_INTERVAL_MS)
            }
        }
    }

    fun stopAnnounce() {
        announceJob?.cancel()
        announceJob = null
    }

    /** 客户端：开始监听局域网内的中继广播 */
    fun startListen(onFound: (RelayNode) -> Unit) {
        stopListen()
        onRelayFound = onFound
        foundNodes.clear()
        // MulticastLock 防止接收广播时 CPU 休眠丢包
        try {
            val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            multicastLock = wifi.createMulticastLock("EverettRelayDiscovery").apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (_: Exception) {}

        listenJob = scope.launch {
            val socket = try {
                DatagramSocket(PORT).apply { soTimeout = 1000 }
            } catch (e: Exception) {
                Log.e(TAG, "监听端口占用: ${e.message}")
                return@launch
            }
            val buf = ByteArray(2048)
            while (isActive) {
                try {
                    val packet = DatagramPacket(buf, buf.size)
                    socket.receive(packet)
                    val json = String(packet.data, 0, packet.length).trim()
                    val msg = JSONObject(json)
                    if (msg.optString("type", "") == TYPE) {
                        val node = RelayNode(
                            name = msg.optString("name", "中继设备"),
                            ip = msg.optString("ip", packet.address.hostAddress ?: ""),
                            port = msg.optInt("port", RelayServer.DEFAULT_PORT),
                            nodeId = msg.optString("nodeId", "")
                        )
                        val key = "${node.ip}:${node.port}"
                        // 去重：已存在则更新，否则新增并回调
                        val isNew = !foundNodes.containsKey(key)
                        foundNodes[key] = node
                        if (isNew) {
                            Log.i(TAG, "发现中继: ${node.name} @ ${node.ip}:${node.port}")
                            onRelayFound?.invoke(node)
                        }
                    }
                } catch (_: java.net.SocketTimeoutException) {
                    // 超时继续监听
                } catch (_: Exception) {
                    // 忽略坏包
                }
            }
            try { socket.close() } catch (_: Exception) {}
        }
    }

    fun stopListen() {
        listenJob?.cancel()
        listenJob = null
        try { multicastLock?.release() } catch (_: Exception) {}
        multicastLock = null
    }

    /** 当前已发现的节点列表 */
    fun currentNodes(): List<RelayNode> = foundNodes.values.toList()

    fun dispose() {
        stopAnnounce()
        stopListen()
        scope.cancel()
    }
}
