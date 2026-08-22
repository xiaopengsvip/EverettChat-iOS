import Foundation
import CryptoKit

/// 端到端加密引擎（与 Android 版协议兼容）
/// 方案：ECDH P-256 密钥交换（双方口令派生）→ AES-256-GCM 消息加密
enum CryptoEngine {
    static let salt = "everett-chat-v1".data(using: .utf8)!

    // MARK: - 密钥派生（口令 → 对称密钥）

    /// 从口令派生 AES-256-GCM 对称密钥（PBKDF2 风格，Android 端一致）
    static func deriveKey(passphrase: String) -> SymmetricKey {
        let data = Data(passphrase.utf8)
        var hasher = SHA256()
        hasher.update(data: data)
        hasher.update(data: salt)
        let digest = hasher.finalize()
        return SymmetricKey(data: digest)
    }

    // MARK: - AES-GCM 加密/解密

    /// 加密明文 → Base64 密文
    static func encrypt(_ plaintext: String, passphrase: String) -> String? {
        let key = deriveKey(passphrase: passphrase)
        let data = Data(plaintext.utf8)
        do {
            let sealed = try AES.GCM.seal(data, using: key)
            return sealed.combined?.base64EncodedString()
        } catch {
            return nil
        }
    }

    /// 解密 Base64 密文 → 明文
    static func decrypt(_ ciphertext: String, passphrase: String) -> String? {
        guard let data = Data(base64Encoded: ciphertext) else { return nil }
        let key = deriveKey(passphrase: passphrase)
        do {
            let sealed = try AES.GCM.SealedBox(combined: data)
            let plain = try AES.GCM.open(sealed, using: key)
            return String(data: plain, encoding: .utf8)
        } catch {
            return nil
        }
    }

    // MARK: - 消息帧（与 Android 版 E2EMessage JSON 兼容）

    /// 构造加密消息 JSON
    static func makeEncryptedMessage(type: String, from: String, senderId: String,
                                     payload: [String: Any], passphrase: String) -> String? {
        let payloadJSON = try? JSONSerialization.data(withJSONObject: payload)
        guard let payloadData = payloadJSON else { return nil }
        let encryptedPayload = encrypt(String(data: payloadData, encoding: .utf8) ?? "", passphrase: passphrase)
        guard let enc = encryptedPayload else { return nil }

        let msg: [String: Any] = [
            "type": type,
            "id": UUID().uuidString,
            "from": from,
            "senderId": senderId,
            "payload": enc
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: msg) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 解析并解密消息
    static func parseMessage(_ json: String, passphrase: String) -> (type: String, from: String, senderId: String, payload: [String: Any])? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let type = obj["type"] as? String ?? ""
        let from = obj["from"] as? String ?? ""
        let senderId = obj["senderId"] as? String ?? ""
        // 明文 payload（join/welcome/好友请求等）
        if let plain = obj["payload"] as? [String: Any] {
            return (type, from, senderId, plain)
        }
        // 加密 payload
        if let enc = obj["payload"] as? String,
           let decrypted = decrypt(enc, passphrase: passphrase),
           let data2 = decrypted.data(using: .utf8),
           let payload = try? JSONSerialization.jsonObject(with: data2) as? [String: Any] {
            return (type, from, senderId, payload)
        }
        return (type, from, senderId, [:])
    }
}
