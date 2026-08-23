import Foundation
import SwiftUI
import Combine

/// 通话类型
enum CallType {
    case audio   // 语音通话
    case video   // 视频通话
}

/// 通话状态机（Evo Protocol CALL_* 信令）
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

/// 统一通话管理器（P2：WebRTC 音视频）
/// 信令走 ConnectionManager（Cloud WS），媒体通道后续接 WebRTC
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
    private var callbacks: [String: (String, String, String, [String: Any]) -> Void] = [:]

    private init() {
        // 订阅统一连接层的消息（多播，不覆盖 AppState）
        conn.addMessageHandler { [weak self] type, from, senderId, payload in
            self?.handleSignal(type: type, from: from, senderId: senderId, payload: payload)
        }
    }

    // MARK: - 信令处理

    private func handleSignal(type: String, from: String, senderId: String, payload: [String: Any]) {
        switch type {
        case "call-start":
            guard let callTypeRaw = payload["callType"] as? String else { return }
            state = .ringing
            callType = callTypeRaw == "video" ? .video : .audio
            peerName = from
            peerId = senderId
            callbacks[peerId] = { [weak self] t, f, sid, p in self?.handleSignal(type: t, from: f, senderId: sid, payload: p) }
        case "call-accept":
            if state == .outgoing {
                state = .connecting
                startTimer()
            }
        case "call-reject":
            if state == .outgoing || state == .ringing {
                endCall()
            }
        case "call-end":
            endCall()
        default:
            break
        }
    }

    // MARK: - 对外接口

    /// 发起通话
    func startCall(peerId: String, peerName: String, type: CallType) {
        self.peerId = peerId
        self.peerName = peerName
        self.callType = type
        self.state = .outgoing
        conn.send(type: "call-start", target: peerId, payload: [
            "callType": type == .video ? "video" : "audio",
            "target": peerId
        ])
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
        conn.send(type: "call-accept", target: peerId, payload: ["target": peerId])
        startTimer()
    }

    /// 拒绝来电
    func rejectCall() {
        guard state == .ringing else { return }
        conn.send(type: "call-reject", target: peerId, payload: ["target": peerId])
        endCall()
    }

    /// 挂断
    func endCall() {
        if state != .idle && state != .ended {
            conn.send(type: "call-end", target: peerId, payload: ["target": peerId])
        }
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
    }

    func toggleVideo() {
        isVideoEnabled.toggle()
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
