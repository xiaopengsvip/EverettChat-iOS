import Foundation
import UIKit
import UserNotifications
import PushKit

/// 推送注册（APNs + PushKit VoIP）+ 本地通知（来电后台提醒）
/// 注意：免费 Apple ID 签名无法使用 APNs（需付费开发者账号），但注册代码保留
@MainActor
final class PushRegistration: NSObject, ObservableObject {
    static let shared = PushRegistration()

    @Published var pushToken: String = ""
    @Published var voipToken: String = ""

    private override init() {
        super.init()
        // 请求通知权限（本地通知必用，APNs 选配）
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        UNUserNotificationCenter.current().delegate = self
    }

    /// 注册远程通知（APNs）
    func registerAPNs() {
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// 注册 VoIP Push（PushKit）
    func registerVoIP() {
        let registry = PKPushRegistry(queue: .main)
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
    }

    /// 发本地通知（来电后台提醒，CallKit 的补充）
    func showLocalNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushRegistration: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }
}

// MARK: - PKPushRegistryDelegate

extension PushRegistration: PKPushRegistryDelegate {
    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        if type == .voIP {
            voipToken = token
        }
        // 上报 token 到云端（Push 服务器端）
        uploadToken(token: token, type: type == .voIP ? "voip" : "apns")
    }

    /// 上报 push token 到 relay /push/register
    private func uploadToken(token: String, type: String) {
        guard let url = URL(string: "\(PublicRelay.httpURL)/push/register") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "deviceId": DeviceIdentity.shared.deviceId,
            "token": token,
            "platform": "ios",
            "type": type
        ])
        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }

    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        // VoIP 推送 → 上报 CallKit 来电
        if let caller = payload.dictionaryPayload["caller"] as? String {
            Task { @MainActor in
                CallKitAdapter.shared.reportIncomingCall(uuid: UUID(), peerName: caller, hasVideo: false)
            }
        }
        completion()
    }
}