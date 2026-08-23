import Foundation
import WebRTC
import Combine

/// WebRTC 媒体引擎：真实音视频通道
/// 信令经 ConnectionManager 交换（call-offer / call-answer / call-ice）
@MainActor
final class WebRTCEngine: NSObject, ObservableObject {
    static let shared = WebRTCEngine()

    // 渲染视图（SwiftUI 通过 UIViewRepresentable 桥接）
    @Published var localVideoView: RTCMTLVideoView?
    @Published var remoteVideoView: RTCMTLVideoView?

    private var factory: RTCPeerConnectionFactory!
    private var peerConnection: RTCPeerConnection?
    private var localVideoTrack: RTCVideoTrack?
    private var localAudioTrack: RTCAudioTrack?
    private var remoteVideoTrack: RTCVideoTrack?
    private var callId = ""
    private var conn: ConnectionManager { ConnectionManager.shared }
    private var videoEnabled = false

    // STUN（公共）+ TURN（P2P 失败兜底）
    private var iceServers: [RTCIceServer] {
        var servers = [
            RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"]),
            RTCIceServer(urlStrings: ["stun:stun1.l.google.com:19302"])
        ]
        // 1) 用户自配 TURN（Cloudflare Calls / coturn）优先
        if let turnURL = UserDefaults.standard.string(forKey: "turn_url"),
           !turnURL.isEmpty {
            let user = UserDefaults.standard.string(forKey: "turn_user") ?? ""
            let pass = UserDefaults.standard.string(forKey: "turn_pass") ?? ""
            servers.append(RTCIceServer(urlStrings: [turnURL], username: user, credential: pass))
        } else {
            // 2) 免费公共 TURN 兜底（openrelay.metered.ca，公开凭据，有流量限制）
            servers.append(RTCIceServer(
                urlStrings: [
                    "turn:openrelay.metered.ca:80",
                    "turn:openrelay.metered.ca:443",
                    "turns:openrelay.metered.ca:443?transport=tcp"
                ],
                username: "openrelayproject",
                credential: "openrelayproject"
            ))
        }
        return servers
    }

    private override init() {
        super.init()
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        factory = RTCPeerConnectionFactory(encoderFactory: encoderFactory, decoderFactory: decoderFactory)
        // 订阅信令
        conn.addMessageHandler { [weak self] type, _, _, payload in
            self?.handleSignal(type: type, payload: payload)
        }
    }

    // MARK: - 信令

    private func handleSignal(type: String, payload: [String: Any]) {
        switch type {
        case "call-offer":
            guard let sdp = payload["sdp"] as? String, let cid = payload["callId"] as? String else { return }
            callId = cid
            receiveOffer(sdp)
        case "call-answer":
            guard let sdp = payload["sdp"] as? String else { return }
            receiveAnswer(sdp)
        case "call-ice":
            guard let candidate = payload["candidate"] as? String,
                  let mid = payload["sdpMid"] as? String,
                  let index = payload["sdpMLineIndex"] as? Int else { return }
            let ice = RTCIceCandidate(sdp: candidate, sdpMLineIndex: Int32(index), sdpMid: mid)
            peerConnection?.add(ice)
        default:
            break
        }
    }

    private func sendSignal(type: String, payload: [String: Any]) {
        var p = payload
        p["callId"] = callId
        conn.send(type: type, target: CallManager.shared.peerId, payload: p)
    }

    // MARK: - 发起/接听

    /// 发起通话：创建 PeerConnection + 本地轨道 + Offer
    func startCall(type: CallType) {
        videoEnabled = (type == .video)
        callId = UUID().uuidString
        setupPeerConnection(video: videoEnabled)
        guard let pc = peerConnection else { return }
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: ["DtlsSrtpKeyAgreement": "true"])
        pc.offer(for: constraints) { [weak self] sdp, _ in
            guard let sdp else { return }
            self?.setLocalAndSend(sdp, type: "call-offer")
        }
    }

    /// 接听：应答 Offer
    func acceptCall(type: CallType) {
        videoEnabled = (type == .video)
        setupPeerConnection(video: videoEnabled)
    }

    /// 挂断
    func endCall() {
        peerConnection?.close()
        peerConnection = nil
        remoteVideoTrack = nil
    }

    private func setupPeerConnection(video: Bool) {
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
        }
    }

    private func setLocalAndSend(_ sdp: RTCSessionDescription, type: String) {
        peerConnection?.setLocalDescription(sdp) { [weak self] _ in
            self?.sendSignal(type: type, payload: ["sdp": sdp.sdp])
        }
    }

    private func receiveOffer(_ sdpString: String) {
        let sdp = RTCSessionDescription(type: .offer, sdp: sdpString)
        peerConnection?.setRemoteDescription(sdp) { [weak self] _ in
            guard let self, let pc = self.peerConnection else { return }
            let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: ["DtlsSrtpKeyAgreement": "true"])
            pc.answer(for: constraints) { sdp, _ in
                guard let sdp else { return }
                self.setLocalAndSend(sdp, type: "call-answer")
            }
        }
    }

    private func receiveAnswer(_ sdpString: String) {
        let sdp = RTCSessionDescription(type: .answer, sdp: sdpString)
        peerConnection?.setRemoteDescription(sdp) { _ in }
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
