import Foundation
import CallKit
import UIKit
import Combine

/// CallKit 平台适配（P3）
/// - 来电：系统级来电界面（锁屏/后台也能显示）
/// - 去电：系统通话界面
/// - 音频会话管理（扬声器/听筒/蓝牙耳机）
@MainActor
final class CallKitAdapter: NSObject, ObservableObject {
    static let shared = CallKitAdapter()

    private var provider: CXProvider?
    private let callController = CXCallController()
    private var activeCallUUID: UUID?

    private override init() {
        super.init()
        setupProvider()
    }

    // MARK: - Provider 配置

    private func setupProvider() {
        let config = CXProviderConfiguration()
        config.supportsVideo = true
        config.maximumCallsPerCallGroup = 1
        config.supportedHandleTypes = [.generic]
        config.includesCallsInRecents = true
        config.iconTemplateImageData = nil
        provider = CXProvider(configuration: config)
        provider?.setDelegate(self, queue: nil)
    }

    // MARK: - 来电上报（CallManager 收到 call-start 时调用）

    func reportIncomingCall(uuid: UUID, peerName: String, hasVideo: Bool) {
        activeCallUUID = uuid
        let handle = CXHandle(type: .generic, value: peerName)
        let update = CXCallUpdate()
        update.remoteHandle = handle
        update.localizedCallerName = peerName
        update.hasVideo = hasVideo

        provider?.reportNewIncomingCall(with: uuid, update: update) { _ in }
        // 系统来电铃声/震动由 CallKit 处理
        startAudioSession()
    }

    /// 通话建立后：启动音频会话（扬声器/听筒路由）
    func startAudioSession() {
        let config = AVAudioSession.sharedInstance()
        do {
            try config.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .defaultToSpeaker])
            try config.setActive(true)
        } catch {}
    }

    /// 切换扬声器
    func setSpeaker(_ on: Bool) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.overrideOutputAudioPort(on ? .speaker : .none)
        } catch {}
    }

    /// 通话结束上报（系统 UI 关闭）
    func endCall(uuid: UUID) {
        provider?.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
        activeCallUUID = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - 去电（可选：系统通话界面）

    func startOutgoingCall(uuid: UUID, peerName: String) {
        activeCallUUID = uuid
        let handle = CXHandle(type: .generic, value: peerName)
        let action = CXStartCallAction(call: uuid, handle: handle)
        let transaction = CXTransaction(action: action)
        callController.request(transaction) { _ in }
    }
}

// MARK: - CXProviderDelegate

extension CallKitAdapter: CXProviderDelegate {
    func providerDidReset(_ provider: CXProvider) {}

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        // 用户点击接听 → 通知 CallManager
        Task { @MainActor in
            CallManager.shared.acceptCall()
        }
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        // 用户点击挂断 → 通知 CallManager
        Task { @MainActor in
            CallManager.shared.endCall()
        }
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        Task { @MainActor in
            CallManager.shared.isMuted = action.isMuted
        }
        action.fulfill()
    }

    func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        // 音频会话激活（WebRTC 音频输出）
        try? audioSession.setActive(true)
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }
}
