package top.vios.chat.net

import android.util.Log
import kotlinx.coroutines.*
import org.json.JSONObject
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.NetworkInterface
import java.nio.charset.StandardCharsets
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

/**
 * 局域网设备发现（UDP 广播）
 *
 * 协议:
 *  探测方: 广播发送 {"type":"probe","name":"设备名","id":"实例ID"} 到 255.255.255.255:44779
 *  在线方: 收到 probe 后单播回复 {"type":"hello","name":"设备名","port":44777,"id":"实例ID"}
 *  探测方: 收集回复 → 设备列表（跳过自己的 instanceId 和本机所有 IP）
 *
 * 配对模式:
 *  发起方: 生成配对码 → 广播 {"type":"pair-announce","code":"123456","name":...}
 *  输入方: 广播 {"type":"pair-probe","code":"123456"} → 发起方校验 code 一致后回复
 *          {"type":"pair-hello","name":...,"ip":...,"port":...} → 输入方自动连接
 */
class LanDiscovery(
    private val deviceName: String,
    private val servicePort: Int = 44777
) {
    companion object {
        private const val TAG = "LanDiscovery"
        const val DISCOVERY_PORT = 44779
        const val BROADCAST_ADDR = "255.255.255.255"
    }

    data class DiscoveredDevice(
        val name: String,
        val ip: String,
        val port: Int,
        val instanceId: String = ""
    )

    // 唯一实例 ID（用于跳过自己）
    private val instanceId: String = UUID.randomUUID().toString().take(8)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val running = AtomicBoolean(false)
    private var respondSocket: DatagramSocket? = null

    // 配对码监听回调（携带来源 IP 和端口，回复必须回到来源端口）
    var onPairRequest: ((code: String, fromIp: String, fromPort: Int) -> Unit)? = null

    fun getInstanceId() = instanceId

    /** 获取本机所有 IPv4 地址（用于跳过自己） */
    private fun getLocalIps(): Set<String> {
        val ips = HashSet<String>()
        try {
            NetworkInterface.getNetworkInterfaces().toList()
                .filter { it.isUp && !it.isLoopback }
                .flatMap { it.inetAddresses.toList() }
                .filterIsInstance<java.net.Inet4Address>()
                .forEach { ips.add(it.hostAddress ?: "") }
        } catch (_: Exception) {}
        ips.add("127.0.0.1")
        ips.add("")
        return ips
    }

    /**
     * 主动扫描局域网，返回发现的设备列表
     * 跳过自己：instanceId 相同 或 IP 属于本机
     */
    suspend fun scan(timeoutMs: Long = 2500): List<DiscoveredDevice> = withContext(Dispatchers.IO) {
        val found = LinkedHashMap<String, DiscoveredDevice>()
        val socket = DatagramSocket()
        socket.broadcast = true
        socket.soTimeout = timeoutMs.toInt()
        val localIps = getLocalIps()

        try {
            val probe = JSONObject()
                .put("type", "probe")
                .put("name", deviceName)
                .put("id", instanceId)
                .toString()
            val data = probe.toByteArray(StandardCharsets.UTF_8)
            val packet = DatagramPacket(data, data.size, InetAddress.getByName(BROADCAST_ADDR), DISCOVERY_PORT)
            socket.send(packet)

            // 等待回复
            val buf = ByteArray(2048)
            val endTime = System.currentTimeMillis() + timeoutMs
            while (System.currentTimeMillis() < endTime) {
                try {
                    val resp = DatagramPacket(buf, buf.size)
                    socket.receive(resp)
                    val json = String(resp.data, 0, resp.length, StandardCharsets.UTF_8)
                    val o = JSONObject(json)
                    if (o.optString("type") == "hello") {
                        val name = o.optString("name", "未知设备")
                        val ip = resp.address.hostAddress ?: continue
                        val port = o.optInt("port", servicePort)
                        val peerId = o.optString("id", "")

                        // 跳过自己：实例ID相同 或 本机IP
                        if (peerId == instanceId) continue
                        if (ip in localIps) continue
                        if (name == deviceName && ip == getLocalIp()) continue

                        found[ip] = DiscoveredDevice(name, ip, port, peerId)
                    }
                } catch (_: java.net.SocketTimeoutException) {
                    break
                } catch (_: Exception) {
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "scan error: ${e.message}")
        } finally {
            socket.close()
        }
        found.values.toList()
    }

    /**
     * 自动配对：广播配对探测（携带配对码），等待配对发起方回复
     * @return 匹配到的设备（null=超时未找到）
     */
    suspend fun pairMatch(code: String, timeoutMs: Long = 4000): DiscoveredDevice? = withContext(Dispatchers.IO) {
        val socket = DatagramSocket()
        socket.broadcast = true
        socket.soTimeout = timeoutMs.toInt()
        val localIps = getLocalIps()

        try {
            // 广播配对探测
            val probe = JSONObject()
                .put("type", "pair-probe")
                .put("code", code)
                .put("name", deviceName)
                .put("id", instanceId)
                .toString()
            val data = probe.toByteArray(StandardCharsets.UTF_8)
            val packet = DatagramPacket(data, data.size, InetAddress.getByName(BROADCAST_ADDR), DISCOVERY_PORT)
            socket.send(packet)

            // 等待配对发起方回复（可能回多次，取第一个匹配的）
            val buf = ByteArray(2048)
            val endTime = System.currentTimeMillis() + timeoutMs
            while (System.currentTimeMillis() < endTime) {
                try {
                    val resp = DatagramPacket(buf, buf.size)
                    socket.receive(resp)
                    val json = String(resp.data, 0, resp.length, StandardCharsets.UTF_8)
                    val o = JSONObject(json)
                    if (o.optString("type") == "pair-hello" && o.optString("code") == code) {
                        val ip = resp.address.hostAddress ?: continue
                        if (ip in localIps) continue
                        return@withContext DiscoveredDevice(
                            name = o.optString("name", "配对设备"),
                            ip = ip,
                            port = o.optInt("port", servicePort),
                            instanceId = o.optString("id", "")
                        )
                    }
                } catch (_: java.net.SocketTimeoutException) {
                    break
                } catch (_: Exception) {
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "pairMatch error: ${e.message}")
        } finally {
            socket.close()
        }
        null
    }

    /**
     * 启动监听：响应 probe 扫描 + 响应 pair-probe 配对探测
     * 配对发起方需在收到 pair-probe 后调用 respondPair()
     */
    fun startResponder() {
        if (!running.compareAndSet(false, true)) return
        scope.launch {
            try {
                respondSocket = DatagramSocket(DISCOVERY_PORT).apply {
                    reuseAddress = true
                    broadcast = true
                    soTimeout = 5000
                }
                val buf = ByteArray(2048)
                while (running.get()) {
                    try {
                        val packet = DatagramPacket(buf, buf.size)
                        respondSocket?.receive(packet) ?: break
                        val json = String(packet.data, 0, packet.length, StandardCharsets.UTF_8)
                        val o = JSONObject(json)
                        when (o.optString("type")) {
                            "probe" -> {
                                val reply = JSONObject()
                                    .put("type", "hello")
                                    .put("name", deviceName)
                                    .put("port", servicePort)
                                    .put("id", instanceId)
                                    .toString()
                                val respData = reply.toByteArray(StandardCharsets.UTF_8)
                                val resp = DatagramPacket(respData, respData.size, packet.address, packet.port)
                                respondSocket?.send(resp)
                            }
                            "pair-probe" -> {
                                val code = o.optString("code", "")
                                val fromIp = packet.address.hostAddress ?: ""
                                // 关键修复: 回复必须发到探测者的来源端口（packet.port），
                                // 探测者用临时 socket 监听，不是 DISCOVERY_PORT
                                val fromPort = packet.port
                                onPairRequest?.invoke(code, fromIp, fromPort)
                            }
                        }
                    } catch (_: java.net.SocketTimeoutException) {
                    } catch (_: Exception) {
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "responder error: ${e.message}")
            }
        }
    }

    /** 配对发起方：向探测者回复配对成功（仅当 code 匹配时调用） */
    fun respondPair(code: String, toIp: String, toPort: Int) {
        scope.launch {
            try {
                val reply = JSONObject()
                    .put("type", "pair-hello")
                    .put("code", code)
                    .put("name", deviceName)
                    .put("port", servicePort)
                    .put("id", instanceId)
                    .toString()
                val data = reply.toByteArray(StandardCharsets.UTF_8)
                val packet = DatagramPacket(data, data.size, InetAddress.getByName(toIp), toPort)
                respondSocket?.send(packet)
                Log.i(TAG, "respondPair: code=$code -> $toIp:$toPort")
            } catch (e: Exception) {
                Log.w(TAG, "respondPair error: ${e.message}")
            }
        }
    }

    fun stopResponder() {
        running.set(false)
        try { respondSocket?.close() } catch (_: Exception) {}
        respondSocket = null
    }

    fun getLocalIp(): String {
        return try {
            NetworkInterface.getNetworkInterfaces().toList()
                .filter { it.isUp && !it.isLoopback }
                .flatMap { it.inetAddresses.toList() }
                .filterIsInstance<java.net.Inet4Address>()
                .firstOrNull { !it.isLoopbackAddress && it.hostAddress?.startsWith("192.168") == true }
                ?.hostAddress ?: ""
        } catch (_: Exception) { "" }
    }
}