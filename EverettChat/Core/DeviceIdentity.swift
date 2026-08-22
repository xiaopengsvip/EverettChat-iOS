import Foundation
import CryptoKit
import Security

/// 设备身份：唯一 ID（首次生成，永不可改）+ 设备名
final class DeviceIdentity {
    static let shared = DeviceIdentity()

    private let defaults = UserDefaults.standard
    private let idKey = "everett_device_id"
    private let nameKey = "everett_device_name"
    private let customNameKey = "everett_custom_name"

    /// 完整唯一 ID（UUID）
    var deviceId: String {
        if let id = defaults.string(forKey: idKey), !id.isEmpty {
            return id
        }
        let newId = UUID().uuidString.lowercased()
        defaults.set(newId, forKey: idKey)
        return newId
    }

    /// 短 ID（前 8 位，展示用）
    var shortId: String {
        String(deviceId.prefix(8))
    }

    /// 设备名（首次随机，可自定义）
    var deviceName: String {
        if let n = defaults.string(forKey: customNameKey), !n.isEmpty {
            return n
        }
        if let n = defaults.string(forKey: nameKey), !n.isEmpty {
            return n
        }
        let names = ["幻影蜂鸟", "霓虹白虎", "曙光行者", "深空猎鹰", "寒冰玄龟", "绯红彗星", "极光鲸", "星尘鹿"]
        let n = names.randomElement() ?? "Everett 设备"
        defaults.set(n, forKey: nameKey)
        return n
    }

    func setCustomName(_ name: String) {
        defaults.set(name, forKey: customNameKey)
    }

    func rerollName() -> String {
        let names = ["幻影蜂鸟", "霓虹白虎", "曙光行者", "深空猎鹰", "寒冰玄龟", "绯红彗星", "极光鲸", "星尘鹿"]
        let n = names.randomElement() ?? "Everett 设备"
        defaults.set(n, forKey: nameKey)
        defaults.removeObject(forKey: customNameKey)
        return n
    }
}
