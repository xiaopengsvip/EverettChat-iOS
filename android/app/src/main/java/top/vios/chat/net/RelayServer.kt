package top.vios.chat.net

import android.content.Context
import android.util.Log
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import top.vios.chat.getLocalIpAddress
import fi.iki.elonen.NanoHTTPD
import fi.iki.elonen.NanoWSD
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer

/**
 * 内置中继服务器（端到端加密中继）
 *
 * 让本机成为中继节点：任何设备装 App 开启此服务后，
 * 其他设备可通过 ws://本机IP:8088/ws 加入同一房间中转消息。
 *
 * 协议与电脑版 relay-server.js 完全一致：
 *   WS  /ws                  — join/转发密文
 *   POST /upload?room=&fileId= — 上传文件
 *   GET  /download?room=&fileId= — 下载文件
 *   GET  /health             — 健康检查
 *
 * 仅转发密文（E2E 加密在客户端完成），中继看不到内容。
 */
class RelayServer(
    private val context: Context,
    private val port: Int = 8088
) : NanoWSD("0.0.0.0", port) {

    companion object {
        private const val TAG = "RelayServer"
        const val DEFAULT_PORT = 8088
        const val ROOM_KEY = "room"
        const val FILE_KEY = "fileId"
        const val MESH_ROOM = "__mesh__"      // 中继节点互联专用房间
        const val MAX_HOP = 3                 // 跨节点转发最大跳数（防环）

        fun relayWsAddress(ip: String, port: Int = DEFAULT_PORT) = "ws://$ip:$port/ws"
        fun relayHttpAddress(ip: String, port: Int = DEFAULT_PORT) = "http://$ip:$port"

        /** 中继网可视化 Web 页面（精简版） */
        const val RELAY_WEB_PAGE = """<html><head><meta charset="utf-8"><title>Everett 中继网</title>
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="theme-color" content="#0B0B14">
<style>*{margin:0;padding:0;box-sizing:border-box;--sat:env(safe-area-inset-top);--sab:env(safe-area-inset-bottom)}
body{background:#0B0B14;color:#F2F2F7;font-family:-apple-system,sans-serif;padding:calc(12px + var(--sat)) 14px calc(12px + var(--sab));-webkit-tap-highlight-color:transparent}
h1{font-size:17px;margin-bottom:12px;display:flex;align-items:center;gap:8px}h1 span{color:#8B5CF6}
.card{background:#14141F;border:1px solid #24243A;border-radius:14px;padding:14px;margin-bottom:10px}
.row{display:flex;justify-content:space-between;padding:6px 0;font-size:13px;border-bottom:1px solid #1A1A2C}.row:last-child{border:none}
.k{color:#9E9EB0}.v{color:#34D399;font-weight:600}
.user{padding:8px 0;font-size:13px;border-bottom:1px solid #1A1A2C;display:flex;align-items:center;gap:8px}.user:last-child{border:none}
.user .dot{width:8px;height:8px;border-radius:50%;background:#34D399;flex:none;box-shadow:0 0 4px #34D399}.dlbtn{display:block;text-align:center;text-decoration:none;margin-top:12px;padding:14px;border-radius:14px;background:linear-gradient(135deg,#8B5CF6,#6366F1);color:#fff;font-size:15px;font-weight:700;min-height:48px;display:flex;align-items:center;justify-content:center;gap:8px}</style></head><body>
<h1>🕸 Everett <span>中继网</span></h1>
<div class="card"><div class="row"><span class="k">节点</span><span class="v" id="nname">-</span></div>
<div class="row"><span class="k">节点ID</span><span class="v" id="nid">-</span></div>
<div class="row"><span class="k">地址</span><span class="v" id="nip">-</span></div>
<div class="row"><span class="k">互联节点</span><span class="v" id="npeers">-</span></div></div>
<div class="card"><b>📶 在线用户</b><div id="users">加载中...</div></div>
<div class="card"><b>📦 APK</b><div id="apk">-</div>
<a id="apkBtn" href="/apk/everett-chat.apk" download style="display:block;text-align:center;text-decoration:none;margin-top:10px;padding:12px;border-radius:12px;background:linear-gradient(135deg,#8B5CF6,#6366F1);color:#fff;font-size:14px;font-weight:600">📥 点击下载并安装</a></div>
<script>
setInterval(async()=>{try{
const d=await(await fetch('/topology')).json();
document.getElementById('nname').textContent=d.name;
document.getElementById('nid').textContent=(d.nodeId||'').slice(0,8);
document.getElementById('nip').textContent=d.ip+':'+d.port;
document.getElementById('npeers').textContent=(d.peers||[]).length+' 台';
document.getElementById('users').innerHTML=(d.users||[]).map(u=>'<div class="user">🟢 '+u.name+' <span style="color:#6E6E82">('+u.room+')</span></div>').join('')||'<div class="user">暂无在线</div>';
document.getElementById('apk').textContent=d.apk&&d.apk.versionName?('v'+d.apk.versionName+' · 安装量 '+(d.apk.downloads||0)):'暂无';
}catch(e){document.getElementById('users').textContent='连接失败'}},3000)();
</script></body></html>"""
    }

    // 房间管理：roomId -> 连接的 WebSocket
    private val rooms = HashMap<String, MutableSet<NanoWSD.WebSocket>>()
    private val dataDir = File(context.filesDir, "relay-data")
    private val apkDir = File(context.filesDir, "relay-apk")
    private val serverScope = kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.SupervisorJob() + kotlinx.coroutines.Dispatchers.IO)
    private var heartbeatJob: kotlinx.coroutines.Job? = null   // 服务器级心跳（清理死连接）

    // ===== 中继网互联（业务网：节点间传输） =====
    /** 本节点唯一 ID（持久化，重启不变） */
    val nodeId: String = context.getSharedPreferences("everett_chat", Context.MODE_PRIVATE)
        .getString("relay_node_id", null) ?: java.util.UUID.randomUUID().toString().also {
            context.getSharedPreferences("everett_chat", Context.MODE_PRIVATE)
                .edit().putString("relay_node_id", it).apply()
        }
    @Volatile var nodeName = "中继节点"
    /** 互联节点表：nodeId -> peer 连接 */
    private val meshPeers = HashMap<String, MeshPeer>()
    /** 已处理的消息 ID（防环去重） */
    private val seenMsgIds = java.util.Collections.synchronizedSet(HashSet<String>())
    /** 在线用户表（中继网用户发现）：senderId -> {name, room} */
    private val users = HashMap<String, Pair<String, String>>()
    /** APK 下载计数 + Web 访问统计（安装量 + Web 页面统计） */
    private val apkCountFile = File(apkDir, "download-count.json")
    private fun getApkCountJson(): org.json.JSONObject =
        try { org.json.JSONObject(apkCountFile.readText()) } catch (_: Exception) { org.json.JSONObject().put("count", 0).put("webViews", 0).put("webDownloads", 0) }
    private fun getApkCount(): Int = getApkCountJson().optInt("count", 0)
    private fun incrApkCount(fromWeb: Boolean) {
        try {
            val c = getApkCountJson()
            c.put("count", c.optInt("count", 0) + 1)
            if (fromWeb) c.put("webDownloads", c.optInt("webDownloads", 0) + 1)
            apkCountFile.writeText(c.toString())
        } catch (_: Exception) {}
    }
    private fun incrWebView() {
        try {
            val c = getApkCountJson()
            c.put("webViews", c.optInt("webViews", 0) + 1)
            apkCountFile.writeText(c.toString())
        } catch (_: Exception) {}
    }
    private val meshOkHttp = OkHttpClient.Builder().pingInterval(20, java.util.concurrent.TimeUnit.SECONDS).build()

    /** 互联节点 */
    class MeshPeer(val nodeId: String, val name: String, val ws: okhttp3.WebSocket)

    /** 当前互联节点数 */
    fun meshPeerCount(): Int = synchronized(meshPeers) { meshPeers.size }

    /** 互联节点列表（管理网 /nodes 用） */
    fun meshPeerList(): List<Pair<String, String>> = synchronized(meshPeers) { meshPeers.values.map { it.nodeId to it.name } }

    /** 作为客户端连接另一中继节点（业务网互联） */
    fun connectToNode(ip: String, port: Int = DEFAULT_PORT) {
        val wsUrl = "ws://$ip:$port/ws"
        // 防重复连接
        synchronized(meshPeers) {
            if (meshPeers.values.any { it.ws.toString().contains(ip) }) return
        }
        try {
            val request = Request.Builder().url(wsUrl).build()
            meshOkHttp.newWebSocket(request, object : okhttp3.WebSocketListener() {
                override fun onOpen(ws: okhttp3.WebSocket, response: okhttp3.Response) {
                    // 加入 mesh 房间，声明节点身份
                    val join = JSONObject()
                        .put("type", "join")
                        .put("id", java.util.UUID.randomUUID().toString())
                        .put("from", nodeName)
                        .put("senderId", "node-" + nodeId)
                        .put("payload", JSONObject()
                            .put("room", MESH_ROOM)
                            .put("mesh", true)
                            .put("nodeId", nodeId)
                            .put("name", nodeName))
                    runCatching { ws.send(join.toString()) }
                    Log.i(TAG, "已互联中继节点: $ip:$port")
                }
                override fun onMessage(ws: okhttp3.WebSocket, text: String) {
                    // 处理对方节点的 mesh-welcome 或 relay-forward
                    handleMeshMessage(text)
                }
                override fun onClosed(ws: okhttp3.WebSocket, code: Int, reason: String) {
                    synchronized(meshPeers) {
                        val it = meshPeers.entries.firstOrNull { it.value.ws === ws }
                        if (it != null) {
                            meshPeers.remove(it.key)
                            Log.i(TAG, "中继节点断开: ${it.value.name}")
                        }
                    }
                }
                override fun onFailure(ws: okhttp3.WebSocket, t: Throwable, response: okhttp3.Response?) {
                    synchronized(meshPeers) {
                        val it = meshPeers.entries.firstOrNull { it.value.ws === ws }
                        if (it != null) {
                            meshPeers.remove(it.key)
                        }
                    }
                }
            })
        } catch (e: Exception) {
            Log.e(TAG, "互联失败 $ip:$port: ${e.message}")
        }
    }

    /** 处理来自互联节点的消息 */
    private fun handleMeshMessage(text: String) {
        try {
            val msg = JSONObject(text)
            when (msg.optString("type", "")) {
                "mesh-welcome" -> {
                    val peerId = msg.optJSONObject("payload")?.optString("nodeId") ?: return
                    val peerName = msg.optJSONObject("payload")?.optString("name") ?: "中继节点"
                    Log.i(TAG, "mesh 握手完成: $peerName ($peerId)")
                }
                "relay-forward" -> {
                    val room = msg.optString("room", "")
                    val origin = msg.optString("origin", "")
                    val hop = msg.optInt("hop", 0)
                    val msgId = msg.optString("msgId", "")
                    val data = msg.optString("data", "")
                    // 防环：同一条消息只处理一次
                    if (msgId.isNotEmpty() && !seenMsgIds.add(msgId)) return
                    if (room.isEmpty() || data.isEmpty() || hop >= MAX_HOP) return
                    // 转发给本节点该房间的客户端
                    synchronized(rooms) {
                        rooms[room]?.toList()?.forEach { ws ->
                            if (ws.isOpen && ws !is RelaySocket) runCatching { ws.send(data) }
                            else if (ws.isOpen) runCatching { ws.send(data) }
                        }
                    }
                    // 转发给其他互联节点（除来源方向，靠 msgId 去重）
                    forwardToPeers(JSONObject()
                        .put("type", "relay-forward")
                        .put("room", room)
                        .put("origin", origin)
                        .put("hop", hop + 1)
                        .put("msgId", msgId)
                        .put("data", data))
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "mesh 消息处理失败: ${e.message}")
        }
    }

    /** 广播消息给所有互联节点 */
    private fun forwardToPeers(payload: JSONObject) {
        synchronized(meshPeers) {
            meshPeers.values.forEach { peer ->
                runCatching { peer.ws.send(payload.toString()) }
            }
        }
    }

    /** 中继设备放置 APK 安装包（OTA 更新分发） */
    fun publishApk(apkBytes: ByteArray, versionCode: Int, versionName: String) {
        try {
            if (!apkDir.exists()) apkDir.mkdirs()
            File(apkDir, "everett-chat.apk").writeBytes(apkBytes)
            val info = JSONObject()
                .put("versionName", versionName)
                .put("versionCode", versionCode)
                .put("size", apkBytes.size.toLong())
                .put("fileName", "everett-chat.apk")
            File(apkDir, "version.json").writeText(info.toString())
            Log.i(TAG, "APK 已发布: $versionName ($versionCode)")
        } catch (e: Exception) {
            Log.e(TAG, "发布 APK 失败: ${e.message}")
        }
    }

    /** 启动服务器（非阻塞） */
    fun startServer(): Boolean {
        return try {
            if (!dataDir.exists()) dataDir.mkdirs()
            if (!apkDir.exists()) apkDir.mkdirs()
            start(NanoHTTPD.SOCKET_READ_TIMEOUT, false)
            // 服务器级心跳：每 30s ping，60s 无响应才清理（两次机会，避免误杀）
            heartbeatJob?.cancel()
            heartbeatJob = serverScope.launch {
                while (true) {
                    kotlinx.coroutines.delay(30_000)
                    synchronized(rooms) {
                        rooms.values.flatten().forEach { ws ->
                            val rs = ws as? RelaySocket ?: return@forEach
                            if (!rs.isAlive) {
                                // 连续 miss 2 次（60s 无响应）才清理 —— 避免网络抖动误杀
                                rs.missCount++
                                if (rs.missCount >= 2) {
                                    runCatching { ws.close(NanoWSD.WebSocketFrame.CloseCode.GoingAway, "heartbeat timeout", false) }
                                } else {
                                    runCatching { ws.ping(ByteArray(0)) }
                                }
                            } else {
                                rs.isAlive = false
                                runCatching { ws.ping(ByteArray(0)) }
                            }
                        }
                    }
                }
            }
            Log.i(TAG, "中继服务器已启动: $port")
            true
        } catch (e: Exception) {
            Log.e(TAG, "中继服务器启动失败: ${e.message}")
            false
        }
    }

    fun stopServer() {
        try {
            heartbeatJob?.cancel()
            heartbeatJob = null
            synchronized(rooms) { rooms.values.forEach { it.forEach { ws -> runCatching { ws.close(NanoWSD.WebSocketFrame.CloseCode.NormalClosure, "server stop", false) } }; rooms.clear() } }
            stop()
            Log.i(TAG, "中继服务器已停止")
        } catch (_: Exception) {}
    }

    fun isRunning(): Boolean = isAlive

    private fun getRoom(roomId: String): MutableSet<NanoWSD.WebSocket> {
        synchronized(rooms) {
            return rooms.getOrPut(roomId) { HashSet() }
        }
    }

    private fun broadcast(roomId: String, message: String, sender: NanoWSD.WebSocket?) {
        synchronized(rooms) {
            val room = rooms[roomId] ?: return
            for (ws in room) {
                if (ws !== sender && ws.isOpen) {
                    runCatching { ws.send(message) }
                }
            }
        }
    }

    override fun openWebSocket(handshake: NanoHTTPD.IHTTPSession): NanoWSD.WebSocket {
        return RelaySocket(handshake)
    }

    /** HTTP 文件服务 + 健康检查（WebSocket 由 NanoWSD.serve 自动分流，这里只处理 HTTP） */
    override fun serveHttp(session: NanoHTTPD.IHTTPSession): NanoHTTPD.Response {
        val uri = session.uri
        val params = session.parms

        // CORS（跨域兼容）
        val corsHeaders = mapOf(
            "Access-Control-Allow-Origin" to "*",
            "Access-Control-Allow-Methods" to "GET, POST, OPTIONS"
        )

        // 健康检查
        if (uri == "/health") {
            val clients = synchronized(rooms) { rooms.values.sumOf { it.size } }
            val nodesArray = org.json.JSONArray()
            synchronized(meshPeers) { meshPeers.entries.forEach { nodesArray.put(JSONObject().put("id", it.key).put("name", it.value.name)) } }
            val resp = NanoHTTPD.newFixedLengthResponse(
                NanoHTTPD.Response.Status.OK, "application/json",
                JSONObject()
                    .put("ok", true)
                    .put("nodeId", nodeId)
                    .put("nodeName", nodeName)
                    .put("nodes", nodesArray)
                    .put("rooms", rooms.size)
                    .put("clients", clients)
                    .toString()
            )
            corsHeaders.forEach { (k, v) -> resp.addHeader(k, v) }
            return resp
        }

        // ===== 安装量统计（含 Web 统计） =====
        if (session.method == NanoHTTPD.Method.GET && uri == "/apk/stats") {
            val info = try { org.json.JSONObject(File(apkDir, "version.json").readText()) } catch (_: Exception) { JSONObject() }
            val c = getApkCountJson()
            return NanoHTTPD.newFixedLengthResponse(
                NanoHTTPD.Response.Status.OK, "application/json",
                JSONObject()
                    .put("downloads", c.optInt("count", 0))
                    .put("webViews", c.optInt("webViews", 0))
                    .put("webDownloads", c.optInt("webDownloads", 0))
                    .put("version", info.optString("versionName", "unknown"))
                    .toString()
            )
        }

        // ===== 用户反馈收集 =====
        if (session.method == NanoHTTPD.Method.POST && uri == "/feedback") {
            try {
                val buf = ByteArrayOutputStream()
                session.inputStream.use { input ->
                    val tmp = ByteArray(4096)
                    while (true) { val n = input.read(tmp); if (n < 0) break; buf.write(tmp, 0, n) }
                }
                val data = org.json.JSONObject(String(buf.toByteArray()))
                val feedbackDir = File(dataDir, "feedback")
                if (!feedbackDir.exists()) feedbackDir.mkdirs()
                File(feedbackDir, System.currentTimeMillis().toString() + ".json").writeText(
                    JSONObject()
                        .put("time", System.currentTimeMillis())
                        .put("device", data.optString("device", "unknown"))
                        .put("type", data.optString("type", "feedback"))
                        .put("msg", data.optString("msg", ""))
                        .toString()
                )
                Log.i(TAG, "收到反馈: " + data.optString("msg", "").take(50))
                return NanoHTTPD.newFixedLengthResponse(NanoHTTPD.Response.Status.OK, "application/json", JSONObject().put("ok", true).toString())
            } catch (e: Exception) {
                return NanoHTTPD.newFixedLengthResponse(NanoHTTPD.Response.Status.BAD_REQUEST, "text/plain", "Bad request")
            }
        }

        // ===== 拓扑可视化 + 在线用户 + Web 页面 =====
        if (session.method == NanoHTTPD.Method.GET && uri == "/topology") {
            val peerArr = org.json.JSONArray()
            // 主动连出的互联节点
            synchronized(meshPeers) { meshPeers.entries.forEach { peerArr.put(JSONObject().put("key", it.key).put("name", it.value.name)) } }
            // 接入的互联节点（服务端接受的 mesh 连接）
            synchronized(rooms) {
                rooms[MESH_ROOM]?.forEach { ws ->
                    val rs = ws as? RelaySocket
                    if (rs?.isMeshPeer == true) {
                        peerArr.put(JSONObject().put("key", rs.peerNodeId).put("name", rs.peerNodeName.ifEmpty { "中继节点" }))
                    }
                }
            }
            val roomArr = org.json.JSONArray()
            synchronized(rooms) { rooms.entries.forEach { (r, set) -> if (r != MESH_ROOM) roomArr.put(JSONObject().put("room", r).put("clients", set.size)) } }
            val userArr = org.json.JSONArray()
            synchronized(users) { users.entries.forEach { (did, p) -> userArr.put(JSONObject().put("deviceId", did).put("name", p.first).put("room", p.second)) } }
            val apkInfo = try { org.json.JSONObject(File(apkDir, "version.json").readText()) } catch (_: Exception) { JSONObject() }
            val c = getApkCountJson()
            apkInfo.put("downloads", c.optInt("count", 0))
            apkInfo.put("webViews", c.optInt("webViews", 0))
            apkInfo.put("webDownloads", c.optInt("webDownloads", 0))
            return NanoHTTPD.newFixedLengthResponse(
                NanoHTTPD.Response.Status.OK, "application/json",
                JSONObject()
                    .put("nodeId", nodeId)
                    .put("name", nodeName)
                    .put("ip", getLocalIpAddress())
                    .put("port", port)
                    .put("peers", peerArr)
                    .put("rooms", roomArr)
                    .put("users", userArr)
                    .put("apk", apkInfo)
                    .toString()
            )
        }
        if (session.method == NanoHTTPD.Method.GET && uri == "/users") {
            val userArr = org.json.JSONArray()
            synchronized(users) { users.entries.forEach { (did, p) -> userArr.put(JSONObject().put("deviceId", did).put("name", p.first).put("room", p.second)) } }
            return NanoHTTPD.newFixedLengthResponse(
                NanoHTTPD.Response.Status.OK, "application/json",
                JSONObject().put("users", userArr).put("nodeName", nodeName).toString()
            )
        }
        if (session.method == NanoHTTPD.Method.GET && uri == "/") {
            incrWebView()   // Web 页面访问量 +1
            return NanoHTTPD.newFixedLengthResponse(
                NanoHTTPD.Response.Status.OK, "text/html; charset=utf-8", RELAY_WEB_PAGE
            )
        }

        // 文件上传：POST /upload?room=X&fileId=Y
        if (session.method == NanoHTTPD.Method.POST && uri == "/upload") {
            val room = params?.get(ROOM_KEY) ?: "default"
            val fileId = params?.get(FILE_KEY)
            if (fileId.isNullOrEmpty()) {
                return NanoHTTPD.newFixedLengthResponse(NanoHTTPD.Response.Status.BAD_REQUEST, "text/plain", "Missing fileId")
            }
            try {
                val roomDir = File(dataDir, room)
                if (!roomDir.exists()) roomDir.mkdirs()
                // 读取请求体（raw 文件数据）
                val buf = ByteArrayOutputStream()
                session.inputStream.use { input ->
                    val tmp = ByteArray(8192)
                    while (true) {
                        val n = input.read(tmp)
                        if (n < 0) break
                        buf.write(tmp, 0, n)
                    }
                }
                val savedFile = File(roomDir, fileId)
                savedFile.writeBytes(buf.toByteArray())
                // 短存储：10 分钟后自动删除（中继不应长期保存用户文件）
                kotlinx.coroutines.MainScope().launch {
                    kotlinx.coroutines.delay(10 * 60 * 1000)
                    try { savedFile.delete() } catch (_: Exception) {}
                }
                return NanoHTTPD.newFixedLengthResponse(NanoHTTPD.Response.Status.OK, "text/plain", "OK")
            } catch (e: Exception) {
                Log.e(TAG, "upload 失败: ${e.message}")
                return NanoHTTPD.newFixedLengthResponse(NanoHTTPD.Response.Status.INTERNAL_ERROR, "text/plain", "Write error")
            }
        }

        // ===== APK 更新分发：GET /apk/version.json + GET /apk/everett-chat.apk =====
        if (session.method == NanoHTTPD.Method.GET && uri == "/apk/version.json") {
            val infoFile = File(apkDir, "version.json")
            if (infoFile.exists()) {
                return NanoHTTPD.newFixedLengthResponse(
                    NanoHTTPD.Response.Status.OK, "application/json",
                    infoFile.readText()
                )
            }
            return NanoHTTPD.newFixedLengthResponse(
                NanoHTTPD.Response.Status.OK, "application/json",
                JSONObject().put("error", "no apk").toString()
            )
        }
        if (session.method == NanoHTTPD.Method.GET && uri == "/apk/everett-chat.apk") {
            val fromWeb = params?.get("from") == "web"   // 区分 Web/App 来源
            incrApkCount(fromWeb)
            val apk = File(apkDir, "everett-chat.apk")
            if (!apk.exists()) {
                return NanoHTTPD.newFixedLengthResponse(NanoHTTPD.Response.Status.NOT_FOUND, "text/plain", "APK not found")
            }
            return NanoHTTPD.newFixedLengthResponse(
                NanoHTTPD.Response.Status.OK, "application/vnd.android.package-archive",
                apk.inputStream(), apk.length()
            )
        }

        // 文件下载：GET /download?room=X&fileId=Y
        if (session.method == NanoHTTPD.Method.GET && uri == "/download") {
            val room = params?.get(ROOM_KEY) ?: "default"
            val fileId = params?.get(FILE_KEY)
            if (fileId.isNullOrEmpty()) {
                return NanoHTTPD.newFixedLengthResponse(NanoHTTPD.Response.Status.BAD_REQUEST, "text/plain", "Missing fileId")
            }
            val file = File(File(dataDir, room), fileId)
            if (!file.exists()) {
                return NanoHTTPD.newFixedLengthResponse(NanoHTTPD.Response.Status.NOT_FOUND, "text/plain", "Not found")
            }
            return NanoHTTPD.newFixedLengthResponse(
                NanoHTTPD.Response.Status.OK,
                "application/octet-stream",
                file.inputStream(),
                file.length()
            )
        }

        return NanoHTTPD.newFixedLengthResponse(NanoHTTPD.Response.Status.NOT_FOUND, "text/plain", "Not found")
    }

    /** 中继 WebSocket：join 房间 + 转发 */
    inner class RelaySocket(handshake: NanoHTTPD.IHTTPSession) : NanoWSD.WebSocket(handshake) {

        private var currentRoom: String? = null
        private var clientName = "unknown"
        @Volatile var isAlive = true     // 服务器心跳存活标记
        @Volatile var isMeshPeer = false // 是否中继节点互联连接
        var peerNodeId = ""
        var peerNodeName = ""
        var senderDeviceId = ""
        @Volatile var missCount = 0      // 连续心跳超时次数（>=2 才清理，60s）""

        override fun onOpen() {}

        override fun onClose(code: NanoWSD.WebSocketFrame.CloseCode?, reason: String?, initiatedByRemote: Boolean) {
            // 离开房间
            currentRoom?.let { roomId ->
                synchronized(rooms) {
                    rooms[roomId]?.remove(this)
                    if (rooms[roomId]?.isEmpty() == true) rooms.remove(roomId)
                }
            }
            // 移除在线用户
            if (senderDeviceId.isNotEmpty()) {
                synchronized(users) { users.remove(senderDeviceId) }
            }
        }

        override fun onMessage(message: NanoWSD.WebSocketFrame) {
            try {
                val text = message.textPayload
                val msg = JSONObject(text)
                val type = msg.optString("type", "")

                if (type == "join") {
                    val roomId = msg.optJSONObject("payload")?.optString("room") ?: "default"
                    currentRoom = roomId
                    clientName = msg.optString("from", "unknown")
                    senderDeviceId = msg.optString("senderId", "")
                    // 注册在线用户（中继网用户发现）
                    if (senderDeviceId.isNotEmpty() && !senderDeviceId.startsWith("node-")) {
                        synchronized(users) { users[senderDeviceId] = clientName to roomId }
                    }
                    // 中继节点互联连接（业务网 mesh）
                    val isMesh = msg.optJSONObject("payload")?.optBoolean("mesh", false) == true
                    if (isMesh) {
                        isMeshPeer = true
                        peerNodeId = msg.optJSONObject("payload")?.optString("nodeId", "") ?: ""
                        peerNodeName = msg.optJSONObject("payload")?.optString("name", "中继节点") ?: "中继节点"
                        synchronized(rooms) {
                            rooms.getOrPut(MESH_ROOM) { HashSet() }.add(this)
                        }
                        // mesh 握手：告知对方本节点身份
                        send(JSONObject()
                            .put("type", "mesh-welcome")
                            .put("id", msg.optString("id", ""))
                            .put("from", "server")
                            .put("senderId", "node-" + nodeId)
                            .put("payload", JSONObject()
                                .put("nodeId", nodeId)
                                .put("name", nodeName))
                            .toString())
                        Log.i(TAG, "中继节点已互联(接入): $peerNodeName")
                        return
                    }
                    val room = getRoom(roomId)
                    synchronized(rooms) {
                        room.add(this)
                    }

                    if (room.size >= 2) {
                        // 通知已有成员：新成员加入
                        for (client in room) {
                            if (client !== this && client.isOpen) {
                                runCatching {
                                    client.send(JSONObject()
                                        .put("type", "peer-joined")
                                        .put("id", msg.optString("id", ""))
                                        .put("from", msg.optString("from", ""))
                                        .put("senderId", msg.optString("senderId", ""))
                                        .put("payload", JSONObject().put("name", clientName))
                                        .toString())
                                }
                            }
                        }
                        // 通知新成员：房间就绪
                        val otherName = synchronized(rooms) { room.firstOrNull { it !== this }?.let { "对端" } ?: "对端" }
                        send(JSONObject()
                            .put("type", "welcome")
                            .put("id", msg.optString("id", ""))
                            .put("from", "server")
                            .put("senderId", "server")
                            .put("payload", JSONObject().put("peer", otherName))
                            .toString())
                    } else {
                        send(JSONObject()
                            .put("type", "welcome")
                            .put("id", msg.optString("id", ""))
                            .put("from", "server")
                            .put("senderId", "server")
                            .put("payload", JSONObject().put("peer", "等待对方加入..."))
                            .toString())
                    }
                    return
                }

                // 转发到同房间其他客户端（target 定向，否则广播）
                currentRoom?.let { roomId ->
                    val target = msg.optJSONObject("payload")?.optString("target", "") ?: ""
                    if (target.isNotEmpty()) {
                        // 定向：只发给目标设备
                        synchronized(rooms) {
                            rooms[roomId]?.toList()?.forEach { c ->
                                val rs = c as? RelaySocket
                                if (c !== this && c.isOpen && rs?.senderDeviceId == target) {
                                    runCatching { c.send(text) }
                                }
                            }
                        }
                    } else {
                        // 本地房间广播
                        broadcast(roomId, text, this)
                    }
                    // 跨节点转发（业务网传输）：包装为 relay-forward 发给互联节点
                    val msgId = msg.optString("id", "")
                    if (msgId.isNotEmpty()) seenMsgIds.add(msgId)
                    val fwd = JSONObject()
                        .put("type", "relay-forward")
                        .put("room", roomId)
                        .put("origin", nodeId)
                        .put("hop", 0)
                        .put("msgId", msgId)
                        .put("data", text)
                    // 主动互联的节点（okhttp）
                    forwardToPeers(fwd)
                    // 接入的 mesh 节点（服务端连接）
                    synchronized(rooms) {
                        rooms[MESH_ROOM]?.toList()?.forEach { ws ->
                            val rs = ws as? RelaySocket
                            if (rs?.isMeshPeer == true && ws !== this) {
                                runCatching { ws.send(fwd.toString()) }
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "消息处理失败: ${e.message}")
            }
        }

        override fun onPong(pong: NanoWSD.WebSocketFrame) {
            isAlive = true
            missCount = 0
        }

        override fun onException(exception: java.io.IOException?) {}
    }
}
