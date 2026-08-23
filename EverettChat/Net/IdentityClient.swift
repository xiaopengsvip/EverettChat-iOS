import Foundation

/// 云端身份注册（Evo Protocol：POST /identity）
/// 首次启动注册 Root Identity 到云端，之后定期更新 lastSeen
enum IdentityClient {
    private static let registeredKey = "evt_identity_registered"

    /// 是否已注册
    static var isRegistered: Bool {
        UserDefaults.standard.bool(forKey: registeredKey)
    }

    /// 注册/更新身份到云端（幂等，可重复调用）
    static func register(force: Bool = false, completion: ((Bool) -> Void)? = nil) {
        // 已注册且非强制 → 跳过
        if isRegistered && !force {
            completion?(true)
            return
        }

        guard let url = URL(string: "\(PublicRelay.httpURL)/identity") else {
            completion?(false)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let identity = DeviceIdentity.shared
        let body: [String: Any] = [
            "userId": identity.deviceId,          // 当前单设备模型：deviceId 即 userId
            "deviceId": identity.deviceId,
            "deviceName": identity.deviceName,
            "platform": "ios",
            "version": "1.0.0"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, error in
            let ok = error == nil && (try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any])??["ok"] as? Bool == true
            if ok {
                UserDefaults.standard.set(true, forKey: registeredKey)
            }
            DispatchQueue.main.async {
                completion?(ok)
            }
        }.resume()
    }
}
