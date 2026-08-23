import Foundation
import CryptoKit
import CommonCrypto
import SwiftKyber

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
            // nonce → Data（Nonce 固定 12 字节）
            var nonceData = Data(count: nonceLength)
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

    // ============================================================
    // v2 PQC：ML-KEM-768 + X25519 Hybrid（NIST FIPS 203）
    // 规范：docs/EVO-E2E-Protocol-v2.md
    // 依赖：SwiftKyber (leif-ibsen)
    // ============================================================

    static let v2KemName = "X25519+ML-KEM-768"
    static let v2Info = "EVO-E2E-v2-hybrid"

    // MARK: - ML-KEM-768 (SwiftKyber)

    /// 生成 ML-KEM-768 密钥对 → (encapKey, decapKey)
    static func generateMLKEMKeyPair() -> (encap: Kyber.EncapsulationKey, decap: Kyber.DecapsulationKey) {
        Kyber.GenerateKeyPair(kind: .K768)
    }

    /// 编码 ML-KEM 封装公钥为 Base64
    static func mlkemPubKeyToB64(_ encap: Kyber.EncapsulationKey) -> String {
        Data(encap.encoded).base64EncodedString()
    }

    /// 从 Base64 解码 ML-KEM 封装公钥
    static func mlkemPubKeyFromB64(_ b64: String) -> Kyber.EncapsulationKey? {
        guard let data = Data(base64Encoded: b64) else { return nil }
        return try? Kyber.EncapsulationKey(keyBytes: [UInt8](data))
    }

    /// 封装：用对方公钥 → (共享秘密 K 32B, 封装密文 ct)
    static func mlkemEncapsulate(_ encap: Kyber.EncapsulationKey) -> (secret: Data, kemCt: Data) {
        let (k, ct) = encap.Encapsulate()
        return (Data(k), Data(ct))
    }

    /// 解封装：用自己私钥 + 对方封装密文 → 共享秘密 32B
    static func mlkemDecapsulate(_ decap: Kyber.DecapsulationKey, kemCt: Data) -> Data? {
        return try? Data(decap.Decapsulate(ct: [UInt8](kemCt)))
    }

    // MARK: - X25519 (CryptoKit)

    /// 生成 X25519 临时密钥对
    static func generateX25519KeyPair() -> (priv: Curve25519.KeyAgreement.PrivateKey, pub: Curve25519.KeyAgreement.PublicKey) {
        let priv = Curve25519.KeyAgreement.PrivateKey()
        return (priv, priv.publicKey)
    }

    /// X25519 共享秘密（32B raw）
    static func x25519SharedSecret(myPriv: Curve25519.KeyAgreement.PrivateKey,
                                   peerPub: Curve25519.KeyAgreement.PublicKey) -> Data? {
        return try? myPriv.sharedSecretFromKeyAgreement(with: peerPub)
    }

    /// 编码 X25519 公钥为 Base64（raw 32B）
    static func x25519PubToB64(_ pub: Curve25519.KeyAgreement.PublicKey) -> String {
        pub.rawRepresentation.base64EncodedString()
    }

    /// 从 Base64 解码 X25519 公钥
    static func x25519PubFromB64(_ b64: String) -> Curve25519.KeyAgreement.PublicKey? {
        guard let data = Data(base64Encoded: b64) else { return nil }
        return try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: data)
    }

    // MARK: - HKDF-SHA-384 混合派生

    /// v2 混合 KDF：HKDF-SHA-384(ss1 || ss2, salt, info) → 32B AES key
    static func hybridKDF(ss1: Data, ss2: Data, roomId: String) -> SymmetricKey {
        let saltData = Data(SHA256.hash(data: "everett-e2e-v2|\(roomId)".data(using: .utf8)!).prefix(16))
        let ikm = ss1 + ss2  // 64B
        return HKDF<SHA384>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: ikm),
            salt: saltData,
            info: v2Info.data(using: .utf8)!,
            outputByteCount: keyLength
        )
    }

    // MARK: - v2 Envelope 构造/解析

    /// 构造 v2 加密 payload（Hybrid X25519 + ML-KEM-768）
    static func makeV2Payload(plaintext: String,
                              myX25519Priv: Curve25519.KeyAgreement.PrivateKey,
                              myX25519Pub: Curve25519.KeyAgreement.PublicKey,
                              peerX25519Pub: Curve25519.KeyAgreement.PublicKey,
                              peerKemPub: Kyber.EncapsulationKey,
                              roomId: String, target: String, messageId: String) -> [String: Any]? {
        guard let ss1 = x25519SharedSecret(myPriv: myX25519Priv, peerPub: peerX25519Pub) else { return nil }
        let (ss2, kemCt) = mlkemEncapsulate(peerKemPub)
        let finalKey = hybridKDF(ss1: ss1, ss2: ss2, roomId: roomId)
        guard let enc = encrypt(plaintext, key: finalKey) else { return nil }
        var payload: [String: Any] = [
            "v": 2,
            "kem": v2KemName,
            "nonce": enc.nonce.base64EncodedString(),
            "ct": enc.ciphertext.base64EncodedString(),
            "ephPub": x25519PubToB64(myX25519Pub),
            "kemCt": kemCt.base64EncodedString(),
            "target": target
        ]
        if !messageId.isEmpty { payload["messageId"] = messageId }
        return payload
    }

    /// 解析 v2 payload → 明文
    static func parseV2Payload(_ payload: [String: Any],
                               myX25519Priv: Curve25519.KeyAgreement.PrivateKey,
                               myKemDecap: Kyber.DecapsulationKey,
                               roomId: String) -> String? {
        guard let ephPubB64 = payload["ephPub"] as? String,
              let kemCtB64 = payload["kemCt"] as? String,
              let nonceB64 = payload["nonce"] as? String,
              let ctB64 = payload["ct"] as? String,
              let ephPub = x25519PubFromB64(ephPubB64),
              let ss1 = x25519SharedSecret(myPriv: myX25519Priv, peerPub: ephPub),
              let ss2 = mlkemDecapsulate(myKemDecap, kemCt: Data(base64Encoded: kemCtB64)!),
              let nonce = Data(base64Encoded: nonceB64),
              let ct = Data(base64Encoded: ctB64) else { return nil }
        let finalKey = hybridKDF(ss1: ss1, ss2: ss2, roomId: roomId)
        return decrypt(nonce: nonce, ciphertextWithTag: ct, key: finalKey)
    }
}
