import Foundation
import CryptoKit
import CommonCrypto

/// EVO E2E Protocol v1 加密引擎（与 Android 版严格一致）
/// 方案：PBKDF2-HMAC-SHA256(100k) → AES-256-GCM，nonce/tag 显式分离
/// 规范：docs/EVO-E2E-Protocol-v1.md
enum CryptoEngine {
    /// v1 固定参数
    static let protocolVersion = 1
    static let iterations = 100_000
    static let keyLength = 32          // 256-bit
    static let nonceLength = 12        // 96-bit
    static let tagLength = 16          // 128-bit
    static let kdfName = "PBKDF2-HMAC-SHA256"

    // MARK: - 房间盐（与房间绑定，可公开）

    /// salt = SHA256("everett-e2e-v1|" + roomId) 前 16 字节
    static func roomSalt(roomId: String) -> Data {
        let input = "everett-e2e-v1|\(roomId)".data(using: .utf8)!
        let digest = SHA256.hash(data: input)
        return Data(digest.prefix(16))
    }

    // MARK: - PBKDF2 密钥派生（CommonCrypto）

    /// PBKDF2-HMAC-SHA256 派生 AES-256-GCM 密钥
    static func deriveKey(passphrase: String, salt: Data, iterations: Int = iterations) -> SymmetricKey? {
        var key = Data(count: keyLength)
        let result = key.withUnsafeMutableBytes { keyPtr in
            passphrase.withCString { passPtr in
                salt.withUnsafeBytes { saltPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passPtr,
                        passphrase.utf8.count,
                        saltPtr.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        keyPtr.bindMemory(to: UInt8.self).baseAddress,
                        keyLength
                    )
                }
            }
        }
        return result == kCCSuccess ? SymmetricKey(data: key) : nil
    }

    // MARK: - AES-256-GCM 加密（nonce 显式，ct 含 tag）

    /// 加密明文 → (nonce, ciphertext+tag)
    static func encrypt(_ plaintext: String, key: SymmetricKey) -> (nonce: Data, ciphertext: Data)? {
        do {
            let nonce = AES.GCM.Nonce()   // 12B 随机
            let sealed = try AES.GCM.seal(Data(plaintext.utf8), using: key, nonce: nonce)
            // nonce → Data
            var nonceData = Data(count: nonce.byteCount)
            nonceData.withUnsafeMutableBytes { noncePtr in
                nonce.withUnsafeBytes { src in
                    noncePtr.copyMemory(from: src)
                }
            }
            return (nonceData, sealed.ciphertext + sealed.tag)
        } catch {
            return nil
        }
    }

    /// 解密 (nonce, ciphertext+tag) → 明文
    static func decrypt(nonce: Data, ciphertextWithTag: Data, key: SymmetricKey) -> String? {
        guard ciphertextWithTag.count > tagLength else { return nil }
        let ct = ciphertextWithTag.prefix(ciphertextWithTag.count - tagLength)
        let tag = ciphertextWithTag.suffix(tagLength)
        do {
            let sealed = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: nonce),
                ciphertext: Data(ct),
                tag: Data(tag)
            )
            let plain = try AES.GCM.open(sealed, using: key)
            return String(data: plain, encoding: .utf8)
        } catch {
            return nil
        }
    }

    // MARK: - v1 Envelope 构造/解析

    /// 构造 v1 加密 payload（含协议元数据，接收端按 v 兼容）
    static func makeV1Payload(plaintext: String, key: SymmetricKey, salt: Data,
                              target: String, messageId: String) -> [String: Any]? {
        guard let enc = encrypt(plaintext, key: key) else { return nil }
        var payload: [String: Any] = [
            "v": protocolVersion,
            "kdf": kdfName,
            "iter": iterations,
            "salt": salt.base64EncodedString(),
            "nonce": enc.nonce.base64EncodedString(),
            "ct": enc.ciphertext.base64EncodedString(),
            "target": target
        ]
        if !messageId.isEmpty { payload["messageId"] = messageId }
        return payload
    }

    /// 解析 v1 payload → 明文
    static func parseV1Payload(_ payload: [String: Any], key: SymmetricKey) -> String? {
        guard let nonceB64 = payload["nonce"] as? String,
              let ctB64 = payload["ct"] as? String,
              let nonce = Data(base64Encoded: nonceB64),
              let ct = Data(base64Encoded: ctB64) else { return nil }
        return decrypt(nonce: nonce, ciphertextWithTag: ct, key: key)
    }

    // MARK: - 外层消息帧解析（仅拆包，不解密）

    /// 解析外层 JSON → (type, from, senderId, payload)。payload 可能是明文 dict 或 v1 加密 dict
    static func parseMessage(_ json: String) -> (type: String, from: String, senderId: String, payload: [String: Any])? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let type = obj["type"] as? String ?? ""
        let from = obj["from"] as? String ?? ""
        let senderId = obj["senderId"] as? String ?? ""
        let payload = obj["payload"] as? [String: Any] ?? [:]
        return (type, from, senderId, payload)
    }
}
