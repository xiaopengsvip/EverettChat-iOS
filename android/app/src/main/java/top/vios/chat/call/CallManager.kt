package top.vios.chat.call

import android.content.Context
import android.util.Log
import kotlinx.coroutines.*
import org.webrtc.*
import org.json.JSONObject
import top.vios.chat.net.Transport
import java.util.Locale
import java.util.UUID

/**
 * WebRTC 音视频通话管理器
 * 信令通过现有加密传输层（Transport）发送
 * 局域网内使用 host candidate 直连
 */
class CallManager(
    private val context: Context,
    private val transport: Transport,
    private val deviceName: String
) {
    companion object {
        private const val TAG = "CallManager"
        const val CALL_TIMEOUT_MS = 60_000L   // 60 秒未接通自动挂断

        // TURN 服务器配置（REST 凭据，可通过设置页配置；未配置时回退纯 STUN）
        // 部署 coturn 后填写：turn:your-server:3478 + 短期凭据
        private const val TURN_URL = ""          // 例: "turn:turn.vios.top:3478?transport=udp"
        private const val TURN_URL_TCP = ""      // 例: "turn:turn.vios.top:3478?transport=tcp"
        private const val TURN_URL_TLS = ""      // 例: "turns:turn.vios.top:443?transport=tcp"
        private const val TURN_USERNAME = ""
        private const val TURN_PASSWORD = ""

        /** 组装 ICE Servers：STUN + 可选 TURN（UDP/TCP/TLS 全路径） */
        fun buildIceServers(): List<PeerConnection.IceServer> {
            val servers = mutableListOf(
                PeerConnection.IceServer.builder("stun:stun.l.google.com:19302").createIceServer()
            )
            if (TURN_URL.isNotBlank() && TURN_USERNAME.isNotBlank()) {
                servers += PeerConnection.IceServer.builder(TURN_URL)
                    .setUsername(TURN_USERNAME).setPassword(TURN_PASSWORD).createIceServer()
                if (TURN_URL_TCP.isNotBlank()) {
                    servers += PeerConnection.IceServer.builder(TURN_URL_TCP)
                        .setUsername(TURN_USERNAME).setPassword(TURN_PASSWORD).createIceServer()
                }
                if (TURN_URL_TLS.isNotBlank()) {
                    servers += PeerConnection.IceServer.builder(TURN_URL_TLS)
                        .setUsername(TURN_USERNAME).setPassword(TURN_PASSWORD).createIceServer()
                }
            }
            return servers
        }

        // 信令消息类型（走 Transport.sendText 的 JSON 包装）
        const val TYPE_CALL_OFFER = "call-offer"
        const val TYPE_CALL_ANSWER = "call-answer"
        const val TYPE_CALL_ICE = "call-ice"
        const val TYPE_CALL_ENDED = "call-ended"
        const val TYPE_CALL_HANGUP = "call-hangup"
        const val TYPE_CALL_BUSY = "call-busy"
    }

    interface CallListener {
        fun onIncomingCall(callId: String, from: String, video: Boolean)
        fun onCallConnected(callId: String)
        fun onCallEnded(callId: String, reason: String, summary: String)
        fun onCallError(message: String)
        fun onRemoteVideoTrack(track: VideoTrack)
        fun onLocalVideoTrack(track: VideoTrack)
    }

    private var listener: CallListener? = null
    private var peerConnection: PeerConnection? = null
    private var peerConnectionFactory: PeerConnectionFactory? = null
    private var eglBase: EglBase? = null
    private var videoSource: VideoSource? = null
    private var localVideoTrack: VideoTrack? = null
    private var remoteVideoTrack: VideoTrack? = null
    private var audioTrack: AudioTrack? = null
    private var currentCallId: String? = null
    private var isVideoCall = false
    private var isInitiator = false
    private var callActive = false
    private var pendingCandidates = mutableListOf<org.webrtc.IceCandidate>()
    private var pendingOfferSdp: String? = null
    private var initError: String? = null    // WebRTC 初始化错误
    private var timeoutJob: Job? = null      // 60s 未接通自动挂断
    private var callStartMs = 0L              // 发起/接听时间
    private var connectedMs = 0L              // 接通时间（0 = 未接通）
    // 摄像头/纹理助手强引用（关键：局部对象被 GC 会导致接听/发起视频瞬间闪退）
    private var cameraCapturer: org.webrtc.CameraVideoCapturer? = null
    private var surfaceTextureHelper: org.webrtc.SurfaceTextureHelper? = null

    init {
        initWebRTC()
    }

    private fun initWebRTC() {
        try {
            PeerConnectionFactory.initialize(
                PeerConnectionFactory.InitializationOptions.builder(context)
                    .setEnableInternalTracer(false)
                    .createInitializationOptions()
            )
            // 保留 EglBase 引用（防止 GC 回收导致崩溃）
            eglBase = EglBase.create()
            peerConnectionFactory = PeerConnectionFactory.builder()
                .setVideoEncoderFactory(DefaultVideoEncoderFactory(eglBase?.eglBaseContext, true, true))
                .setVideoDecoderFactory(DefaultVideoDecoderFactory(eglBase?.eglBaseContext))
                .createPeerConnectionFactory()
            if (peerConnectionFactory == null) {
                // 降级：纯音频初始化（不带视频编解码器）
                initError = "视频组件初始化失败，降级为纯音频模式"
                Log.e(TAG, "video factory null, fallback to audio-only")
                peerConnectionFactory = PeerConnectionFactory.builder().createPeerConnectionFactory()
            }
            if (peerConnectionFactory != null) {
                Log.i(TAG, "WebRTC initialized")
            }
        } catch (e: Exception) {
            initError = "WebRTC 初始化失败: ${e.message}"
            Log.e(TAG, "WebRTC init failed: ${e.message}")
            // 最后尝试：纯音频
            try {
                peerConnectionFactory = PeerConnectionFactory.builder().createPeerConnectionFactory()
                if (peerConnectionFactory != null) {
                    initError = null
                    Log.i(TAG, "WebRTC fallback audio-only OK")
                }
            } catch (e2: Exception) {
                Log.e(TAG, "WebRTC fallback failed: ${e2.message}")
            }
        }
    }

    /** 检查 WebRTC 就绪，未就绪则报错 */
    private fun checkWebRTC(): Boolean {
        if (peerConnectionFactory != null) return true
        val msg = initError ?: "WebRTC 未就绪"
        listener?.onCallError(msg)
        return false
    }

    fun setListener(l: CallListener?) { listener = l }

    /** 处理接收到的信令消息 */
    fun handleSignaling(json: JSONObject) {
        val type = json.optString("type", "")
        val callId = json.optString("callId", "")
        when (type) {
            TYPE_CALL_OFFER -> {
                val video = json.optBoolean("video", false)
                val from = json.optString("from", "对端")
                isVideoCall = video
                isInitiator = false
                currentCallId = callId
                // 保存 offer sdp，answer 时先 setRemoteDescription
                pendingOfferSdp = json.optString("sdp", "")
                listener?.onIncomingCall(callId, from, video)
            }
            TYPE_CALL_ANSWER -> {
                if (callId == currentCallId) {
                    val sdp = json.optString("sdp", "")
                    peerConnection?.setRemoteDescription(
                        object : SdpObserver {
                            override fun onCreateSuccess(desc: SessionDescription?) {}
                            override fun onCreateFailure(error: String?) {}
                            override fun onSetSuccess() {
                                drainCandidates()
                            }
                            override fun onSetFailure(error: String?) {
                                listener?.onCallError("设置远端描述失败: $error")
                            }
                        },
                        SessionDescription(SessionDescription.Type.ANSWER, sdp)
                    )
                }
            }
            TYPE_CALL_ICE -> {
                if (callId == currentCallId) {
                    val sdp = json.optString("candidate", "")
                    val sdpMid = json.optString("sdpMid", "")
                    val sdpMLineIndex = json.optInt("sdpMLineIndex", 0)
                    val cand = org.webrtc.IceCandidate(sdpMid, sdpMLineIndex, sdp)
                    val pc = peerConnection
                    // 被叫方收到 ICE 时 peerConnection 可能还没创建（用户未接听），先缓存
                    if (pc != null && pc.remoteDescription != null) {
                        pc.addIceCandidate(cand)
                    } else {
                        pendingCandidates.add(cand)
                    }
                }
            }
            TYPE_CALL_HANGUP -> {
                if (callId == currentCallId) {
                    endCall("对方已挂断")
                }
            }
            TYPE_CALL_BUSY -> {
                if (callId == currentCallId) {
                    listener?.onCallEnded(callId, "对方正忙", buildSummary("对方正忙"))
                    cleanupPeerConnection()
                }
            }
        }
    }

    /** 发起通话 */
    fun startCall(video: Boolean) {
        if (callActive) return
        if (!checkWebRTC()) return
        callActive = true
        isInitiator = true
        isVideoCall = video
        currentCallId = UUID.randomUUID().toString()
        callStartMs = System.currentTimeMillis()
        connectedMs = 0L
        createPeerConnection()

        // 60 秒未接通自动挂断（主叫方）
        startTimeout("对方未接听，已自动挂断")

        // 音频轨
        val audioConstraints = MediaConstraints()
        val audioSource = peerConnectionFactory?.createAudioSource(audioConstraints)
        audioTrack = peerConnectionFactory?.createAudioTrack("audio0", audioSource)
        peerConnection?.addTrack(audioTrack, listOf("audio"))

        // 视频轨（可选）
        if (video) {
            val videoConstraints = MediaConstraints().apply {
                mandatory.add(MediaConstraints.KeyValuePair("maxWidth", "1280"))
                mandatory.add(MediaConstraints.KeyValuePair("maxHeight", "720"))
            }
            videoSource = peerConnectionFactory?.createVideoSource(false)
            cameraCapturer = createVideoCapturer()
            if (cameraCapturer != null && eglBase != null) {
                // 复用成员 eglBase + 持有 SurfaceTextureHelper 强引用（防 GC 闪退）
                surfaceTextureHelper = SurfaceTextureHelper.create("captureThread", eglBase!!.eglBaseContext)
                cameraCapturer!!.initialize(surfaceTextureHelper!!, context, videoSource?.capturerObserver)
                cameraCapturer!!.startCapture(1280, 720, 30)
                localVideoTrack = peerConnectionFactory?.createVideoTrack("video0", videoSource)
                peerConnection?.addTrack(localVideoTrack, listOf("video"))
                listener?.onLocalVideoTrack(localVideoTrack!!)
            }
        }

        // 创建 offer
        val constraints = MediaConstraints().apply {
            mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveAudio", "true"))
            mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveVideo", if (video) "true" else "false"))
        }
        peerConnection?.createOffer(object : SdpObserver {
            override fun onCreateSuccess(desc: SessionDescription?) {
                peerConnection?.setLocalDescription(object : SdpObserver {
                    override fun onCreateSuccess(desc: SessionDescription?) {}
                    override fun onCreateFailure(error: String?) {}
                    override fun onSetSuccess() {
                        // 发送 offer 信令
                        sendSignal(TYPE_CALL_OFFER, callId = currentCallId!!, extra = {
                            put("sdp", desc?.description ?: "")
                            put("video", video)
                        })
                    }
                    override fun onSetFailure(error: String?) {
                        listener?.onCallError("设置本地描述失败: $error")
                    }
                }, desc)
            }
            override fun onCreateFailure(error: String?) {
                listener?.onCallError("创建 offer 失败: $error")
            }
            override fun onSetSuccess() {}
            override fun onSetFailure(error: String?) {}
        }, constraints)
    }

    /** 启动 60s 超时自动挂断 */
    private fun startTimeout(reason: String) {
        timeoutJob?.cancel()
        timeoutJob = CoroutineScope(SupervisorJob() + Dispatchers.Main).launch {
            delay(CALL_TIMEOUT_MS)
            if (!isConnectedInternal()) {
                // 超时未接通 → 自动挂断
                listener?.onCallEnded(currentCallId ?: "", reason, buildSummary(reason))
                cleanupPeerConnection()
                callActive = false
            }
        }
    }

    /** 接通后取消超时 */
    private fun cancelTimeout() {
        timeoutJob?.cancel()
        timeoutJob = null
    }

    private fun isConnectedInternal(): Boolean = callActive && peerConnection?.iceConnectionState() == PeerConnection.IceConnectionState.CONNECTED

    /** 接听来电 */
    fun answerCall() {
        if (!checkWebRTC()) return
        val callId = currentCallId ?: return
        val offerSdp = pendingOfferSdp ?: run {
            listener?.onCallError("未收到对方通话数据，请让对方重新拨打")
            return
        }
        createPeerConnection()
        val pc = peerConnection
        if (pc == null) {
            listener?.onCallError("通话通道创建失败")
            return
        }
        callStartMs = System.currentTimeMillis()
        connectedMs = 0L

        // 60 秒未接通自动挂断（被叫方）
        startTimeout("对方未接听，已自动挂断")

        // 先 setRemoteDescription(offer)（WebRTC 必需，之后才能 createAnswer）
        pc.setRemoteDescription(
            object : SdpObserver {
                override fun onCreateSuccess(desc: SessionDescription?) {}
                override fun onCreateFailure(error: String?) {
                    listener?.onCallError("设置远端 offer 失败: $error")
                }
                override fun onSetSuccess() {
                    // 添加缓存的远端 ICE
                    drainCandidates()
                    createAnswerInternal(callId)
                }
                override fun onSetFailure(error: String?) {
                    listener?.onCallError("设置远端 offer 失败: $error")
                }
            },
            SessionDescription(SessionDescription.Type.OFFER, offerSdp)
        )
    }

    private fun createAnswerInternal(callId: String) {
        // 添加音频轨
        val audioConstraints = MediaConstraints()
        val audioSource = peerConnectionFactory?.createAudioSource(audioConstraints)
        audioTrack = peerConnectionFactory?.createAudioTrack("audio0", audioSource)
        peerConnection?.addTrack(audioTrack, listOf("audio"))

        // 视频（可选）
        if (isVideoCall) {
            val videoConstraints = MediaConstraints().apply {
                mandatory.add(MediaConstraints.KeyValuePair("maxWidth", "1280"))
                mandatory.add(MediaConstraints.KeyValuePair("maxHeight", "720"))
            }
            videoSource = peerConnectionFactory?.createVideoSource(false)
            cameraCapturer = createVideoCapturer()
            if (cameraCapturer != null && eglBase != null) {
                // 复用成员 eglBase + 持有 SurfaceTextureHelper 强引用（防 GC 闪退）
                surfaceTextureHelper = SurfaceTextureHelper.create("captureThread", eglBase!!.eglBaseContext)
                cameraCapturer!!.initialize(surfaceTextureHelper!!, context, videoSource?.capturerObserver)
                cameraCapturer!!.startCapture(1280, 720, 30)
                localVideoTrack = peerConnectionFactory?.createVideoTrack("video0", videoSource)
                peerConnection?.addTrack(localVideoTrack, listOf("video"))
                listener?.onLocalVideoTrack(localVideoTrack!!)
            }
        }

        // 创建 answer
        val constraints = MediaConstraints().apply {
            mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveAudio", "true"))
            mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveVideo", if (isVideoCall) "true" else "false"))
        }
        peerConnection?.createAnswer(object : SdpObserver {
            override fun onCreateSuccess(desc: SessionDescription?) {
                peerConnection?.setLocalDescription(object : SdpObserver {
                    override fun onCreateSuccess(desc: SessionDescription?) {}
                    override fun onCreateFailure(error: String?) {}
                    override fun onSetSuccess() {
                        sendSignal(TYPE_CALL_ANSWER, callId = callId, extra = {
                            put("sdp", desc?.description ?: "")
                        })
                        callActive = true
                    }
                    override fun onSetFailure(error: String?) {
                        listener?.onCallError("设置本地描述失败: $error")
                    }
                }, desc)
            }
            override fun onCreateFailure(error: String?) {
                listener?.onCallError("创建 answer 失败: $error")
            }
            override fun onSetSuccess() {}
            override fun onSetFailure(error: String?) {}
        }, constraints)
    }

    private fun createPeerConnection() {
        val config = PeerConnection.RTCConfiguration(
            buildIceServers()   // STUN + 可选 TURN（UDP/TCP/TLS）
        ).apply {
            iceTransportsType = PeerConnection.IceTransportsType.ALL
            bundlePolicy = PeerConnection.BundlePolicy.MAXBUNDLE
            continualGatheringPolicy = PeerConnection.ContinualGatheringPolicy.GATHER_CONTINUALLY
        }
        peerConnection = peerConnectionFactory?.createPeerConnection(config, object : PeerConnection.Observer {
            override fun onSignalingChange(state: PeerConnection.SignalingState?) {}

            override fun onIceConnectionChange(state: PeerConnection.IceConnectionState?) {
                when (state) {
                    PeerConnection.IceConnectionState.CONNECTED -> {
                        callActive = true
                        cancelTimeout()
                        if (connectedMs == 0L) connectedMs = System.currentTimeMillis()
                        listener?.onCallConnected(currentCallId ?: "")
                    }
                    PeerConnection.IceConnectionState.DISCONNECTED -> {
                        listener?.onCallEnded(currentCallId ?: "", "连接中断", buildSummary("连接中断"))
                        cleanupPeerConnection()
                    }
                    PeerConnection.IceConnectionState.FAILED -> {
                        listener?.onCallError("连接失败")
                        cleanupPeerConnection()
                    }
                    else -> {}
                }
            }

            override fun onIceConnectionReceivingChange(receiving: Boolean) {}

            override fun onIceGatheringChange(state: PeerConnection.IceGatheringState?) {}

            override fun onIceCandidate(candidate: org.webrtc.IceCandidate?) {
                candidate ?: return
                // 通过信令发送 ICE
                sendSignal(TYPE_CALL_ICE, callId = currentCallId ?: "", extra = {
                    put("candidate", candidate.sdp)
                    put("sdpMid", candidate.sdpMid ?: "")
                    put("sdpMLineIndex", candidate.sdpMLineIndex)
                })
            }

            override fun onIceCandidatesRemoved(candidates: Array<out org.webrtc.IceCandidate>?) {}

            override fun onAddStream(stream: MediaStream?) {}

            override fun onRemoveStream(stream: MediaStream?) {}

            override fun onAddTrack(receiver: RtpReceiver?, tracks: Array<out MediaStream>?) {
                val track = receiver?.track()
                if (track is VideoTrack) {
                    remoteVideoTrack = track
                    listener?.onRemoteVideoTrack(track)
                }
            }

            override fun onRemoveTrack(receiver: RtpReceiver?) {}

            override fun onDataChannel(dataChannel: DataChannel?) {}

            override fun onRenegotiationNeeded() {}

            override fun onStandardizedIceConnectionChange(newState: PeerConnection.IceConnectionState?) {}
        })
    }

    private fun drainCandidates() {
        pendingCandidates.forEach { peerConnection?.addIceCandidate(it) }
        pendingCandidates.clear()
    }

    private fun createVideoCapturer(): CameraVideoCapturer? {
        return try {
            Camera2Enumerator(context).deviceNames.firstOrNull()?.let { name ->
                Camera2Enumerator(context).createCapturer(name, null)
            }
        } catch (e: Exception) {
            Log.e(TAG, "createVideoCapturer failed: ${e.message}")
            null
        }
    }

    /** 通过传输层发送信令 */
    private fun sendSignal(type: String, callId: String, extra: (JSONObject.() -> Unit)? = null) {
        val payload = JSONObject()
            .put("type", type)
            .put("callId", callId)
            .put("from", deviceName)
        extra?.invoke(payload)
        // 包装为传输层文本消息（加密通道）
        val wrapper = JSONObject()
            .put("__call_signal__", true)
            .put("data", payload.toString())
        transport.sendText(wrapper.toString())
    }

    /** 挂断 */
    fun hangup() {
        val callId = currentCallId ?: return
        sendSignal(TYPE_CALL_HANGUP, callId = callId, extra = null)
        endCall("已挂断")
    }

    /** 网络切换（Wi-Fi↔蜂窝）时 ICE Restart，保持通话不断 */
    fun restartIce() {
        try {
            val pc = peerConnection
            if (pc != null && callActive) {
                pc.restartIce()
                top.vios.chat.DevLog.i("Call", "网络切换，ICE Restart")
            }
        } catch (_: Exception) {}
    }

    /** 拒绝来电 */
    fun rejectCall() {
        val callId = currentCallId ?: return
        sendSignal(TYPE_CALL_BUSY, callId = callId, extra = null)
        endCall("已拒绝")
    }

    private fun endCall(reason: String) {
        val callId = currentCallId
        callActive = false
        cancelTimeout()
        // 计算通话摘要：接通了显示时长，未接通显示状态
        val summary = buildSummary(reason)
        // 通知对方通话已结束（带摘要，对方本地也会显示）
        try {
            sendSignal(TYPE_CALL_ENDED, callId = callId ?: "", extra = {
                put("summary", summary)
                put("reason", reason)
            })
        } catch (_: Exception) {}
        cleanupPeerConnection()
        listener?.onCallEnded(callId ?: "", reason, summary)
    }

    /** 生成通话结束摘要（如 "📞 语音通话 00:32" / "📞 未接听"） */
    fun buildSummary(reason: String): String {
        val kind = if (isVideoCall) "📹 视频通话" else "📞 语音通话"
        if (connectedMs > 0) {
            val secs = ((System.currentTimeMillis() - connectedMs) / 1000).coerceAtLeast(0)
            val mm = secs / 60
            val ss = secs % 60
            return String.format(Locale.CHINA, "%s %02d:%02d", kind, mm, ss)
        }
        return when {
            reason.contains("拒绝") || reason.contains("正忙") -> "📵 对方已拒绝"
            reason.contains("超时") || reason.contains("未接听") || reason.contains("未接") -> "📵 未接听"
            reason.contains("中断") || reason.contains("失败") -> "⚠️ 通话中断"
            else -> "📵 已取消"
        }
    }

    /** EGL 上下文（SurfaceViewRenderer 渲染必需） */
    fun getEglBaseContext(): org.webrtc.EglBase.Context? = eglBase?.eglBaseContext

    private fun cleanupPeerConnection() {
        try {
            cameraCapturer?.stopCapture()
            cameraCapturer?.dispose()
            cameraCapturer = null
            surfaceTextureHelper?.dispose()
            surfaceTextureHelper = null
            videoSource?.dispose()
            videoSource = null
            localVideoTrack = null
            remoteVideoTrack = null
            peerConnection?.close()
            peerConnection = null
            audioTrack = null
        } catch (_: Exception) {}
    }

    fun isInCall() = callActive

    fun destroy() {
        cleanupPeerConnection()
        peerConnectionFactory?.dispose()
        peerConnectionFactory = null
    }
}