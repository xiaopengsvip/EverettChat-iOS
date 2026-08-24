import Foundation
import WebRTC
import Combine

/// WebRTC 媒体引擎：真实音视频通道
/// 信令走 ConnectionManager 的 __call_signal__ 包装（与 Android 一致，实现 iOS↔Android 互拨）
/// - call-offer（含 sdp/video/from/callId）→ call-answer（sdp）→ call-ice（candidate）
/// - call-hangup / call-busy / call-ended 由 CallManager 处理
@MainActor
final class WebRTCEngine: NSObject, ObservableObject {
    static let shared = WebRTCEngine()

    // 渲染视图（SwiftUI 通过 UIViewRepresentable 桥接）
    @Published var localVideoView: RTCMTLVideoView?
    @Published var remoteVideoView: RTCMTLVideoView?

    // 收到来电 offer 的回调（CallManager 弹来电 UI，不自动接听）
    var onIncomingOffer: ((String, String, Bool) -> Void)?   // (callId, from, video)

    private var factory: RTCPeerConnectionFactory!
    private var peerConnection: RTCPeerConnection?
    private var localVideoTrack: RTCVideoTrack?
    private var localAudioTrack: RTCAudioTrack?
    private var remoteVideoTrack: RTCVideoTrack?
    private var callId = ""
    private var videoEnabled = false
    private var pendingOfferSdp: String? = nil
    private var conn: ConnectionManager { ConnectionManager.shared }
    private var pendingCandidates: [RTCIceCandidate] = []

    // STUN（公共）+ TURN（relay 动态获取 Cloudflare Calls 凭据）
    private var staticIceServers: [RTCIceServer] {
        [
            RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"]),
            RTCIceServer(urlStrings: ["stun:stun1.l.google.com:19302"])
        ]
    }

    // 从 relay 获取 Cloudflare TURN 凭据（动态，1h 有效）
    private var turnServers: [RTCIceServer] = []

    /// 刷新 TURN 凭据（通话前调用）
    func refreshTurnCredentials() {
        guard let url = URL(string: "\(PublicRelay.httpURL)/turn/credentials?ttl=3600") else { return }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ice = json["iceServers"] as? [String: Any],
                  let urls = ice["urls"] as? [String],
                  let username = ice["username"] as? String,
                  let credential = ice["credential"] as? String else { return }
            let servers = urls.map { RTCIceServer(urlStrings: [$0], username: username, credential: credential) }
            DispatchQueue.main.async {
                self?.turnServers = servers
            }
        }.resume()
    }

    private var iceServers: [RTCIceServer] {
        staticIceServers + turnServers
    }

    private override init() {
        super.init()
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        factory = RTCPeerConnectionFactory(encoderFactory: encoderFactory, decoderFactory: decoderFactory)
        // 订阅信令（__call_signal__ 包装，外层 type=text）
        conn.addMessageHandler { [weak self] type, from, senderId, payload in
            self?.handleSignal(type: type, payload: payload)
        }
    }

    // MARK: - 信令（__call_signal__ 协议，与 Android 一致）

    private func handleSignal(type: String, payload: [String: Any]) {
        // 解析 __call_signal__ 包装（Android 发的：外层 text + content 为 {"__call_signal__":true,"data":"{...}"}）
        guard type == "text",
              let content = payload["content"] as? String,
              let outer = try? JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any],
              outer["__call_signal__"] as? Bool == true,
              let dataStr = outer["data"] as? String,
              let data = try? JSONSerialization.jsonObject(with: Data(dataStr.utf8)) as? [String: Any],
              let signalType = data["type"] as? String else { return }

        switch signalType {
        case "call-offer":
            guard let sdp = data["sdp"] as? String else { return }
            let cid = data["callId"] as? String ?? ""
            let video = data["video"] as? Bool ?? false
            let fromName = data["from"] as? String ?? "对端"
            callId = cid
            videoEnabled = video
            pendingOfferSdp = sdp
            // 通知 CallManager 弹来电 UI（不自动接听）
            onIncomingOffer?(cid, fromName, video)
        case "call-answer":
            guard let sdp = data["sdp"] as? String else { return }
            receiveAnswer(sdp)
        case "call-ice":
            guard let candidate = data["candidate"] as? String,
                  let mid = data["sdpMid"] as? String,
                  let index = data["sdpMLineIndex"] as? Int else { return }
            let ice = RTCIceCandidate(sdp: candidate, sdpMLineIndex: Int32(index), sdpMid: mid)
            let pc = peerConnection
            // 被叫方在 setRemoteDescription 前收到的 ICE 先缓存
            if pc != nil, pc?.remoteDescription != nil {
                pc?.add(ice)
            } else {
                pendingCandidates.append(ice)
            }
        default:
            break
        }
    }

    /// 发送 __call_signal__ 包装信令（与 Android RelayTransport.sendText 格式一致）
    private func sendSignal(type: String, payload: [String: Any]) {
        var inner = payload
        inner["type"] = type
        inner["callId"] = callId
        inner["from"] = DeviceIdentity.shared.deviceName
        guard let innerData = try? JSONSerialization.data(withJSONObject: inner),
              let innerStr = String(data: innerData, encoding: .utf8) else { return }
        let outer: [String: Any] = ["__call_signal__": true, "data": innerStr]
        guard let outerData = try? JSONSerialization.data(withJSONObject: outer),
              let outerStr = String(data: outerData, encoding: .utf8) else { return }
        conn.sendText(outerStr, target: CallManager.shared.peerId)
    }

    // MARK: - 发起/接听/挂断

    /// 发起通话：创建 PeerConnection + 本地轨道 + Offer
    func startCall(type: CallType, peerId: String) {
        videoEnabled = (type == .video)
        callId = UUID().uuidString
        setupPeerConnection(video: videoEnabled)
        guard let pc = peerConnection else { return }
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: ["DtlsSrtpKeyAgreement": "true"])
        pc.offer(for: constraints) { [weak self] sdp, _ in
            guard let sdp else { return }
            self?.setLocalAndSend(sdp, type: "call-offer", extra: ["video": self?.videoEnabled ?? false])
        }
    }

    /// 接听：先 setRemoteDescription(offer)，再创建 Answer 发送
    func acceptCall(type: CallType) {
        videoEnabled = (type == .video)
        setupPeerConnection(video: videoEnabled)
        guard let pc = peerConnection, let offerSdp = pendingOfferSdp else { return }
        let sdp = RTCSessionDescription(type: .offer, sdp: offerSdp)
        pc.setRemoteDescription(sdp) { [weak self] _ in
            guard let self, let pc = self.peerConnection else { return }
            // 添加缓存的远端 ICE
            self.drainCandidates()
            let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: ["DtlsSrtpKeyAgreement": "true"])
            pc.answer(for: constraints) { sdp, _ in
                guard let sdp else { return }
                self.setLocalAndSend(sdp, type: "call-answer", extra: [:])
            }
        }
    }

    /// 挂断
    func endCall() {
        peerConnection?.close()
        peerConnection = nil
        remoteVideoTrack = nil
        pendingCandidates.removeAll()
        pendingOfferSdp = nil
        // 释放 WebRTC 音频会话
        let rtcAudio = RTCAudioSession.sharedInstance()
        rtcAudio.lockForConfiguration()
        try? rtcAudio.setActive(false)
        rtcAudio.unlockForConfiguration()
    }

    private func setupPeerConnection(video: Bool) {
        // 配置 WebRTC 音频会话（RTCAudioSession，独立于 AVAudioSession 由 WebRTC 管理）
        let rtcAudio = RTCAudioSession.sharedInstance()
        rtcAudio.lockForConfiguration()
        do {
            try rtcAudio.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .defaultToSpeaker])
            try rtcAudio.setActive(true)
        } catch {
            DiagAgent.shared.log("warn", "RTCAudioSession config failed: \(error)")
        }
        rtcAudio.unlockForConfiguration()

        let config = RTCConfiguration()
        config.iceServers = iceServers
        config.sdpSemantics = .unifiedPlan

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: ["DtlsSrtpKeyAgreement": "true"])
        peerConnection = factory.peerConnection(with: config, constraints: constraints, delegate: self)

        // 音频轨道（始终开启）
        let audioConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = factory.audioSource(with: audioConstraints)
        localAudioTrack = factory.audioTrack(with: audioSource, trackId: "audio0")
        peerConnection?.add(localAudioTrack!, streamIds: ["stream0"])

        // 视频轨道（视频通话才开）
        if video {
            let videoSource = factory.videoSource()
            #if targetEnvironment(simulator)
            // 模拟器无摄像头
            #else
            let capturer = RTCCameraVideoCapturer(delegate: videoSource)
            if let cam = RTCCameraVideoCapturer.captureDevices().first,
               let fmt = RTCCameraVideoCapturer.supportedFormats(for: cam).first {
                capturer.startCapture(with: cam, format: fmt, fps: 30)
            }
            #endif
            localVideoTrack = factory.videoTrack(with: videoSource, trackId: "video0")
            peerConnection?.add(localVideoTrack!, streamIds: ["stream0"])
            // 创建本地视频渲染视图（用于 CallView 画中画）
            let renderer = RTCMTLVideoView(frame: .zero)
            renderer.videoContentMode = .scaleAspectFill
            localVideoTrack?.add(renderer)
            localVideoView = renderer
        }
    }

    private func setLocalAndSend(_ sdp: RTCSessionDescription, type: String, extra: [String: Any]) {
        peerConnection?.setLocalDescription(sdp) { [weak self] _ in
            var payload: [String: Any] = ["sdp": sdp.sdp]
            for (k, v) in extra { payload[k] = v }
            self?.sendSignal(type: type, payload: payload)
        }
    }

    private func receiveAnswer(_ sdpString: String) {
        let sdp = RTCSessionDescription(type: .answer, sdp: sdpString)
        peerConnection?.setRemoteDescription(sdp) { [weak self] _ in
            self?.drainCandidates()
        }
    }

    private func drainCandidates() {
        pendingCandidates.forEach { peerConnection?.add($0) }
        pendingCandidates.removeAll()
    }
}

extension WebRTCEngine: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        if let track = stream.videoTracks.first {
            remoteVideoTrack = track
            let renderer = RTCMTLVideoView(frame: .zero)
            renderer.videoContentMode = .scaleAspectFill
            track.add(renderer)
            remoteVideoView = renderer
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        sendSignal(type: "call-ice", payload: [
            "candidate": candidate.sdp,
            "sdpMid": candidate.sdpMid ?? "",
            "sdpMLineIndex": Int(candidate.sdpMLineIndex)
        ])
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        if newState == .connected {
            CallManager.shared.state = .inCall
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didUpdateLocalCandidate local: RTCIceCandidate, remote: RTCIceCandidate) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didFailToGatherCandidatesForDescription description: RTCSessionDescription, error: Error) {}
}