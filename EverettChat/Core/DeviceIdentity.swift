import Foundation
import CryptoKit
import Security

/// EVO 身份体系：Root Identity Key + 设备身份 + 恢复密钥
/// - deviceId：首次生成持久化（兼容旧版本），恢复身份时由 Root Key 重新派生
/// - recoveryKey：Root Key 的 Base32 编码（用户保存，换机/恢复时输入）
final class DeviceIdentity {
    static let shared = DeviceIdentity()

    private let defaults = UserDefaults.standard
    private let idKey = "everett_device_id"
    private let nameKey = "everett_device_name"
    private let customNameKey = "everett_custom_name"
    private let rootKeyKey = "everett_root_key"

    /// Root Identity Key（32 字节，首次生成，Keychain 存储）
    var rootKey: Data {
        if let k = KeychainHelper.load(key: rootKeyKey), k.count == 32 {
            return k
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let k = Data(bytes)
        KeychainHelper.save(key: rootKeyKey, data: k)
        return k
    }

    /// 完整唯一 ID（UUID；新设备由 Root Key 派生，可恢复）
    var deviceId: String {
        if let id = defaults.string(forKey: idKey), !id.isEmpty {
            return id
        }
        let hash = SHA256.hash(data: rootKey)
        let bytes = Array(hash.prefix(16))
        let id = uuidString(from: bytes)
        defaults.set(id, forKey: idKey)
        return id
    }

    /// 恢复身份：输入 Recovery Key → 恢复 Root Key → 重新派生 deviceId（换机场景）
    func restore(fromRecoveryKey code: String) -> Bool {
        let cleaned = code.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "")
            .uppercased()
        guard let k = base32Decode(cleaned), k.count == 32 else { return false }
        KeychainHelper.save(key: rootKeyKey, data: k)
        // 清除旧 deviceId，下次访问时由 Root Key 重新派生
        defaults.removeObject(forKey: idKey)
        return true
    }

    /// 恢复密钥（Base32 分组，用户可保存）
    var recoveryKey: String {
        let raw = base32Encode(rootKey)
        // 每 8 字符一组用 - 分隔，方便输入
        return stride(from: 0, to: raw.count, by: 8).map {
            let start = raw.index(raw.startIndex, offsetBy: $0)
            let end = raw.index(start, offsetBy: min(8, raw.distance(from: start, to: raw.endIndex)))
            return String(raw[start..<end])
        }.joined(separator: "-")
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
        let n = names.randomElement() ?? "EVO 设备"
        defaults.set(n, forKey: nameKey)
        return n
    }

    func setCustomName(_ name: String) {
        defaults.set(name, forKey: customNameKey)
    }

    func rerollName() -> String {
        let names = ["幻影蜂鸟", "霓虹白虎", "曙光行者", "深空猎鹰", "寒冰玄龟", "绯红彗星", "极光鲸", "星尘鹿"]
        let n = names.randomElement() ?? "EVO 设备"
        defaults.set(n, forKey: nameKey)
        defaults.removeObject(forKey: customNameKey)
        return n
    }

    // MARK: - 工具

    private func uuidString(from bytes: [UInt8]) -> String {
        var b = bytes
        b[6] = (b[6] & 0x0F) | 0x40   // version 4
        b[8] = (b[8] & 0x3F) | 0x80   // variant
        let hex = b.map { String(format: "%02x", $0) }.joined()
        return "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20).prefix(12))"
    }

    private let base32Alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    private func base32Encode(_ data: Data) -> String {
        var result = ""
        var buffer = 0
        var bits = 0
        for byte in data {
            buffer = (buffer << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                let index = (buffer >> (bits - 5)) & 31
                result.append(base32Alphabet[index])
                bits -= 5
            }
        }
        if bits > 0 {
            result.append(base32Alphabet[(buffer << (5 - bits)) & 31])
        }
        return result
    }

    private func base32Decode(_ s: String) -> Data? {
        var result = Data()
        var buffer = 0
        var bits = 0
        for ch in s.uppercased() {
            guard let idx = base32Alphabet.firstIndex(of: ch) else { return nil }
            buffer = (buffer << 5) | idx
            bits += 5
            if bits >= 8 {
                result.append(UInt8((buffer >> (bits - 8)) & 0xFF))
                bits -= 8
            }
        }
        return result
    }
}

/// Keychain 轻量封装（Root Key 安全存储）
enum KeychainHelper {
    static func save(key: String, data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return data
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
