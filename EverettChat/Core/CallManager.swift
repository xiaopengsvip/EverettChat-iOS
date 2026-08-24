import Foundation
import SwiftUI
import Combine

/// 通话类型
enum CallType {
    case audio   // 语音通话
    case video   // 视频通话
}

/// 通话状态机（Evo Protocol CALL_* 信令，与 Android 一致）
enum CallState: Equatable {
    case idle          // 空闲
    case outgoing      // 去电（等待对方接听）
    case ringing       // 来电（对方呼叫，等待接听）
    case connecting    // 已接听，建立媒体通道
    case inCall        // 通话中
    case ended         // 已结束

    var label: String {
        switch self {
        case .idle: return ""
        case .outgoing: return "正在呼叫..."
        case .ringing: return "邀请你通话..."
        case .connecting: return "正在连接..."
        case .inCall: return "通话中"
        case .ended: return "通话结束"
        }
    }
}

/// 统一通话管理器（WebRTC 音视频，信令走 __call_signal__ 协议，与 Android 互通）
@MainActor
final class CallManager: ObservableObject {
    static let shared = CallManager()

    @Published var state: CallState = .idle
    @Published var callType: CallType = .audio
    @Published var peerName = ""
    @Published var peerId = ""
    @Published var duration: TimeInterval = 0
    @Published var isMuted = false
    @Published var isSpeakerOn = false
    @Published var isVideoEnabled = false

    private var conn: ConnectionManager { ConnectionManager.shared }
    private var timer: Timer?
    private var activeCallUUID: UUID?

    private init() {
        // WebRTC 引擎收到 offer → 弹来电 UI
        WebRTCEngine.shared.onIncomingOffer = { [weak self] callId, from, video in
            self?.handleIncomingOffer(callId: callId, from: from, video: video)
        }
        // 订阅统一连接层的消息（__call_signal__ 信令 + 状态类）
        conn.addMessageHandler { [weak self] type, from, senderId, payload in
            self?.handleSignal(type: type, from: from, senderId: senderId, payload: payload)
        }
    }

    // MARK: - 信令处理（__call_signal__ 协议）

    private func handleSignal(type: String, from: String, senderId: String, payload: [String: Any]) {
        // 解析 __call_signal__ 包装
        guard type == "text",
              let content = payload["content"] as? String,
              let outer = try? JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any],
              outer["__call_signal__"] as? Bool == true,
              let dataStr = outer["data"] as? String,
              let data = try? JSONSerialization.jsonObject(with: Data(dataStr.utf8)) as? [String: Any],
              let signalType = data["type"] as? String else { return }

        let cid = data["callId"] as? String ?? ""
        switch signalType {
        case "call-offer":
            // WebRTCEngine 已通过 onIncomingOffer 通知，这里只做状态兜底
            break
        case "call-answer":
            if state == .outgoing {
                state = .connecting
                startTimer()
            }
        case "call-hangup":
            // 对方挂断
            endCall()
        case "call-busy":
            // 对方正忙/拒绝
            endCall()
        case "call-ended":
            endCall()
        default:
            break
        }
    }

    /// 收到来电 offer（WebRTCEngine 回调）
    private func handleIncomingOffer(callId: String, from: String, video: Bool) {
        guard state == .idle else {
            // 忙：回 call-busy
            sendSignal(type: "call-busy", callId: callId)
            return
        }
        state = .ringing
        callType = video ? .video : .audio
        peerName = from
        // CallKit 系统来电界面（锁屏/后台显示）
        let uuid = UUID()
        activeCallUUID = uuid
        CallKitAdapter.shared.reportIncomingCall(uuid: uuid, peerName: from, hasVideo: video)
        // 本地通知补充
        PushRegistration.shared.showLocalNotification(title: "\(from) 来电", body: video ? "视频通话" : "语音通话")
    }

    // MARK: - 对外接口

    /// 发起通话
    func startCall(peerId: String, peerName: String, type: CallType) {
        self.peerId = peerId
        self.peerName = peerName
        self.callType = type
        self.state = .outgoing
        // 刷新 TURN 凭据（Cloudflare Calls 动态凭据）
        WebRTCEngine.shared.refreshTurnCredentials()
        // 启动 WebRTC 引擎（创建 PeerConnection + 生成 Offer 并发送 call-offer）
        WebRTCEngine.shared.startCall(type: type, peerId: peerId)
        // 启动音频会话（听筒/扬声器路由）
        CallKitAdapter.shared.startAudioSession()
        startTimer()
        // 超时挂断（60s 未接听）
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            if self?.state == .outgoing {
                self?.endCall()
            }
        }
    }

    /// 接听来电
    func acceptCall() {
        guard state == .ringing else { return }
        state = .connecting
        // 刷新 TURN 凭据
        WebRTCEngine.shared.refreshTurnCredentials()
        // WebRTC 引擎：setRemoteDescription(offer) + 生成 Answer 并发送
        WebRTCEngine.shared.acceptCall(type: callType)
        startTimer()
    }

    /// 拒绝来电
    func rejectCall() {
        guard state == .ringing else { return }
        sendSignal(type: "call-busy")
        endCall()
    }

    /// 挂断
    func endCall() {
        if state != .idle && state != .ended {
            sendSignal(type: "call-hangup")
        }
        // 关闭 WebRTC 引擎
        WebRTCEngine.shared.endCall()
        // 结束 CallKit 通话（系统 UI 关闭 + 音频会话释放）
        if let uuid = activeCallUUID {
            CallKitAdapter.shared.endCall(uuid: uuid)
        }
        activeCallUUID = nil
        state = .ended
        stopTimer()
        // 延迟复位到空闲（UI 显示"通话结束"后回到空闲）
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.state = .idle
            self?.duration = 0
        }
    }

    func toggleMute() {
        isMuted.toggle()
    }

    func toggleSpeaker() {
        isSpeakerOn.toggle()
        CallKitAdapter.shared.setSpeaker(isSpeakerOn)
    }

    func toggleVideo() {
        isVideoEnabled.toggle()
    }

    // MARK: - 信令发送

    /// 发送 __call_signal__ 包装信令（与 Android RelayTransport.sendText 格式一致）
    private func sendSignal(type: String, callId: String = "") {
        let cid = callId.isEmpty ? UUID().uuidString : callId
        let inner: [String: Any] = ["type": type, "callId": cid, "from": DeviceIdentity.shared.deviceName]
        guard let innerData = try? JSONSerialization.data(withJSONObject: inner),
              let innerStr = String(data: innerData, encoding: .utf8) else { return }
        let outer: [String: Any] = ["__call_signal__": true, "data": innerStr]
        guard let outerData = try? JSONSerialization.data(withJSONObject: outer),
              let outerStr = String(data: outerData, encoding: .utf8) else { return }
        conn.sendText(outerStr, target: peerId)
    }

    // MARK: - 计时

    private func startTimer() {
        duration = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.duration += 1
            if self?.state == .connecting {
                self?.state = .inCall
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// 通话时长格式化
    func durationString() -> String {
        let m = Int(duration) / 60
        let s = Int(duration) % 60
        return String(format: "%02d:%02d", m, s)
    }
}