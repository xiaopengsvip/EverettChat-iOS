package top.vios.chat.crypto

import java.security.*
import java.security.spec.*
import javax.crypto.Cipher
import javax.crypto.KeyAgreement
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.SecretKeyFactory
import java.util.Base64

/**
 * EVO E2E Protocol v1 加密引擎（与 iOS CryptoKit 严格一致）
 * 方案：PBKDF2-HMAC-SHA256(100k) → AES-256-GCM，nonce/tag 显式分离
 * 规范：docs/EVO-E2E-Protocol-v1.md
 */
object CryptoEngine {
    private const val AES_KEY_SIZE = 32          // 256-bit
    private const val GCM_NONCE_LEN = 12         // 96-bit IV
    private const val GCM_TAG_LEN = 128          // 128-bit tag
    private const val PBKDF2_ITERATIONS = 100000

    /** 生成 P-256 密钥对（预留，当前中继模式用口令派生） */
    fun generateKeyPair(): KeyPair {
        val kpg = KeyPairGenerator.getInstance("EC")
        kpg.initialize(ECGenParameterSpec("secp256r1"))
        return kpg.generateKeyPair()
    }

    /** 编码公钥为 Base64 */
    fun pubKeyToBase64(pub: PublicKey): String =
        Base64.getEncoder().encodeToString(pub.encoded)

    /** 解码公钥 */
    fun pubKeyFromBase64(b64: String): PublicKey {
        val bytes = Base64.getDecoder().decode(b64)
        val kf = KeyFactory.getInstance("EC")
        return kf.generatePublic(X509EncodedKeySpec(bytes))
    }

    /** ECDH 派生共享密钥 */
    fun ecdhSharedSecret(myPriv: PrivateKey, peerPub: PublicKey): SecretKey {
        val ka = KeyAgreement.getInstance("ECDH")
        ka.init(myPriv)
        ka.doPhase(peerPub, true)
        val raw = ka.generateSecret()
        val md = MessageDigest.getInstance("SHA-256")
        return SecretKeySpec(md.digest(raw), "AES")
    }

    // MARK: - v1 房间盐（与房间绑定，可公开）

    /** salt = SHA256("everett-e2e-v1|" + roomId) 前 16 字节 */
    fun roomSalt(roomId: String): ByteArray {
        val input = "everett-e2e-v1|$roomId".toByteArray(Charsets.UTF_8)
        val md = MessageDigest.getInstance("SHA-256")
        return md.digest(input).copyOfRange(0, 16)
    }

    // MARK: - PBKDF2 密钥派生（v1 统一）

    /** PBKDF2-HMAC-SHA256 派生 AES-256-GCM 密钥（与 iOS 参数严格一致） */
    fun deriveKeyFromPassphrase(passphrase: String, salt: ByteArray, iterations: Int = PBKDF2_ITERATIONS): SecretKey {
        val spec = PBEKeySpec(passphrase.toCharArray(), salt, iterations, AES_KEY_SIZE * 8)
        val factory = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
        return SecretKeySpec(factory.generateSecret(spec).encoded, "AES")
    }

    // MARK: - AES-256-GCM 加密（nonce 显式，返回 nonce + ct含tag）

    /** 加密明文 → (nonce, ciphertext+tag) */
    fun encrypt(key: SecretKey, plaintext: ByteArray): Pair<ByteArray, ByteArray> {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val nonce = ByteArray(GCM_NONCE_LEN).also { SecureRandom().nextBytes(it) }
        cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(GCM_TAG_LEN, nonce))
        val ct = cipher.doFinal(plaintext)   // ct || tag
        return nonce to ct
    }

    /** 解密 (nonce, ciphertext+tag) → 明文 */
    fun decrypt(key: SecretKey, nonce: ByteArray, ciphertext: ByteArray): ByteArray {
        require(ciphertext.size >= GCM_NONCE_LEN + 16) { "密文太短" }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(GCM_TAG_LEN, nonce))
        return cipher.doFinal(ciphertext)
    }

    /** 兼容旧签名（非 v1 调用处使用）：密文内嵌 nonce 头 */
    fun decrypt(key: SecretKey, combined: ByteArray): ByteArray {
        require(combined.size >= GCM_NONCE_LEN + 16) { "密文太短" }
        val nonce = combined.copyOfRange(0, GCM_NONCE_LEN)
        val ct = combined.copyOfRange(GCM_NONCE_LEN, combined.size)
        return decrypt(key, nonce, ct)
    }

    /** 兼容旧签名：返回 nonce || ciphertext+tag 的 combined 格式（局域网直连用） */
    fun encryptCombined(key: SecretKey, plaintext: ByteArray): ByteArray {
        val (nonce, ct) = encrypt(key, plaintext)
        return nonce + ct
    }

    // MARK: - v1 Envelope 构造/解析

    /** 构造 v1 加密 payload JSON（与 iOS makeV1Payload 对应） */
    fun makeV1Payload(plaintext: String, key: SecretKey, salt: ByteArray, target: String, messageId: String): org.json.JSONObject {
        val (nonce, ct) = encrypt(key, plaintext.toByteArray())
        val payload = org.json.JSONObject()
            .put("v", 1)
            .put("kdf", "PBKDF2-HMAC-SHA256")
            .put("iter", PBKDF2_ITERATIONS)
            .put("salt", Base64.getEncoder().encodeToString(salt))
            .put("nonce", Base64.getEncoder().encodeToString(nonce))
            .put("ct", Base64.getEncoder().encodeToString(ct))
            .put("target", target)
        if (messageId.isNotEmpty()) payload.put("messageId", messageId)
        return payload
    }

    /** 解析 v1 payload → 明文 */
    fun parseV1Payload(payload: org.json.JSONObject, key: SecretKey): String? {
        return try {
            val nonce = Base64.getDecoder().decode(payload.optString("nonce", ""))
            val ct = Base64.getDecoder().decode(payload.optString("ct", ""))
            String(decrypt(key, nonce, ct), Charsets.UTF_8)
        } catch (e: Exception) {
            null
        }
    }

    // ============================================================
    // v2 PQC：ML-KEM-768 + X25519 Hybrid（NIST FIPS 203）
    // 规范：docs/EVO-E2E-Protocol-v2.md
    // 依赖：org.bouncycastle:bcprov-jdk18on:1.85.2
    // ============================================================

    /** 生成 ML-KEM-768 密钥对（BouncyCastle，Android 全版本可用） */
    fun generateMLKEMKeyPair(): org.bouncycastle.crypto.AsymmetricCipherKeyPair {
        val params = org.bouncycastle.pqc.crypto.mlkem.MLKEMKeyGenerationParameters(
            java.security.SecureRandom(),
            org.bouncycastle.pqc.crypto.mlkem.MLKEMParameters.ml_kem_768
        )
        val kpg = org.bouncycastle.pqc.crypto.mlkem.MLKEMKeyPairGenerator()
        kpg.init(params)
        return kpg.generateKeyPair()
    }

    /** 编码 ML-KEM 公钥为 Base64 */
    fun mlkemPubKeyToB64(pub: org.bouncycastle.pqc.crypto.mlkem.MLKEMPublicKeyParameters): String =
        Base64.getEncoder().encodeToString(pub.encoded)

    /** 从 Base64 解码 ML-KEM 公钥 */
    fun mlkemPubKeyFromB64(b64: String): org.bouncycastle.pqc.crypto.mlkem.MLKEMPublicKeyParameters =
        org.bouncycastle.pqc.crypto.mlkem.MLKEMPublicKeyParameters(
            org.bouncycastle.pqc.crypto.mlkem.MLKEMParameters.ml_kem_768,
            Base64.getDecoder().decode(b64)
        )

    /** 封装：用对方公钥 → (共享秘密 32B, 封装密文 1088B) */
    fun mlkemEncapsulate(pub: org.bouncycastle.pqc.crypto.mlkem.MLKEMPublicKeyParameters):
            Pair<ByteArray, ByteArray> {
        val gen = org.bouncycastle.pqc.crypto.mlkem.MLKEMGenerator(java.security.SecureRandom())
        val enc = gen.generateEncapsulated(pub)
        return enc.secret to enc.encapsulation
    }

    /** 解封装：用自己私钥 + 对方封装密文 → 共享秘密 32B */
    fun mlkemDecapsulate(priv: org.bouncycastle.pqc.crypto.mlkem.MLKEMPrivateKeyParameters,
                         kemCt: ByteArray): ByteArray {
        val extractor = org.bouncycastle.pqc.crypto.mlkem.MLKEMExtractor(priv)
        return extractor.extractSecret(kemCt)
    }

    // ---- X25519（经典 ECDH，与 ML-KEM 组成 Hybrid） ----

    /** 生成 X25519 密钥对 */
    fun generateX25519KeyPair(): java.security.KeyPair {
        val kpg = java.security.KeyPairGenerator.getInstance("X25519")
        return kpg.generateKeyPair()
    }

    /** X25519 共享秘密（32B） */
    fun x25519SharedSecret(myPriv: java.security.PrivateKey,
                           peerPub: java.security.PublicKey): ByteArray {
        val ka = javax.crypto.KeyAgreement.getInstance("X25519")
        ka.init(myPriv)
        ka.doPhase(peerPub, true)
        return ka.generateSecret()
    }

    /** 编码 X25519 公钥为 Base64 */
    fun x25519PubToB64(pub: java.security.PublicKey): String =
        Base64.getEncoder().encodeToString(pub.encoded)

    /** 从 Base64 解码 X25519 公钥 */
    fun x25519PubFromB64(b64: String): java.security.PublicKey {
        val spec = java.security.spec.X509EncodedKeySpec(Base64.getDecoder().decode(b64))
        return java.security.KeyFactory.getInstance("X25519").generatePublic(spec)
    }

    // ---- HKDF-SHA-384 混合派生 ----

    /**
     * v2 混合 KDF：HKDF-SHA-384(ss1 || ss2, salt, info) → 32B AES key
     * salt = SHA256("everett-e2e-v2|" + roomId) 前 16 字节
     * info = "EVO-E2E-v2-hybrid"
     */
    fun hybridKDF(ss1: ByteArray, ss2: ByteArray, roomId: String): SecretKey {
        val salt = java.security.MessageDigest.getInstance("SHA-256")
            .digest("everett-e2e-v2|$roomId".toByteArray(Charsets.UTF_8)).copyOf(16)
        val info = "EVO-E2E-v2-hybrid".toByteArray(Charsets.UTF_8)
        val ikm = ss1 + ss2

        // HKDF-Extract: PRK = HMAC-SHA384(salt, ikm)
        val mac = javax.crypto.Mac.getInstance("HmacSHA384")
        mac.init(javax.crypto.spec.SecretKeySpec(salt, "HmacSHA384"))
        val prk = mac.doFinal(ikm)

        // HKDF-Expand: OKM = T(1) || T(2) || ...
        mac.init(javax.crypto.spec.SecretKeySpec(prk, "HmacSHA384"))
        var t = ByteArray(0)
        val result = ByteArray(32)
        var remaining = 32
        var blockIndex = 1
        while (remaining > 0) {
            mac.update(t)
            mac.update(info)
            mac.update(blockIndex.toByte())
            t = mac.doFinal()
            val copyLen = minOf(t.size, remaining)
            System.arraycopy(t, 0, result, 32 - remaining, copyLen)
            remaining -= copyLen
            blockIndex++
        }
        return javax.crypto.spec.SecretKeySpec(result, "AES")
    }

    // ---- v2 Envelope 构造/解析 ----

    /**
     * 构造 v2 加密 payload（Hybrid X25519 + ML-KEM-768）
     * @param myX25519Priv 发送方 X25519 私钥（临时密钥，每次消息生成）
     * @param peerX25519Pub 接收方 X25519 公钥
     * @param peerKemPub 接收方 ML-KEM-768 公钥
     */
    fun makeV2Payload(plaintext: String,
                      myX25519Priv: java.security.PrivateKey,
                      myX25519Pub: java.security.PublicKey,
                      peerX25519Pub: java.security.PublicKey,
                      peerKemPub: org.bouncycastle.pqc.crypto.mlkem.MLKEMPublicKeyParameters,
                      roomId: String, target: String, messageId: String): org.json.JSONObject? {
        return try {
            // 1. X25519 经典共享秘密
            val ss1 = x25519SharedSecret(myX25519Priv, peerX25519Pub)
            // 2. ML-KEM-768 后量子封装
            val (ss2, kemCt) = mlkemEncapsulate(peerKemPub)
            // 3. HKDF 混合 → AES key
            val finalKey = hybridKDF(ss1, ss2, roomId)
            // 4. AES-GCM 加密
            val (nonce, ct) = encrypt(finalKey, plaintext.toByteArray(Charsets.UTF_8))
            org.json.JSONObject()
                .put("v", 2)
                .put("kem", "X25519+ML-KEM-768")
                .put("nonce", Base64.getEncoder().encodeToString(nonce))
                .put("ct", Base64.getEncoder().encodeToString(ct))
                .put("ephPub", Base64.getEncoder().encodeToString(myX25519Pub.encoded))
                .put("kemCt", Base64.getEncoder().encodeToString(kemCt))
                .put("target", target)
                .apply { if (messageId.isNotEmpty()) put("messageId", messageId) }
        } catch (e: Exception) {
            null
        }
    }

    /**
     * 解析 v2 payload → 明文
     * @param myX25519Priv 接收方 X25519 私钥（静态）
     * @param myKemPriv 接收方 ML-KEM-768 私钥（静态）
     */
    fun parseV2Payload(payload: org.json.JSONObject,
                       myX25519Priv: java.security.PrivateKey,
                       myKemPriv: org.bouncycastle.pqc.crypto.mlkem.MLKEMPrivateKeyParameters,
                       roomId: String): String? {
        return try {
            val ephPubB64 = payload.optString("ephPub", "")
            val kemCtB64 = payload.optString("kemCt", "")
            val nonceB64 = payload.optString("nonce", "")
            val ctB64 = payload.optString("ct", "")
            if (ephPubB64.isEmpty() || kemCtB64.isEmpty()) return null
            // 1. X25519：用接收方静态私钥 + 发送方临时公钥
            val ephPub = x25519PubFromB64(ephPubB64)
            val ss1 = x25519SharedSecret(myX25519Priv, ephPub)
            // 2. ML-KEM-768：用接收方静态私钥解封装
            val ss2 = mlkemDecapsulate(myKemPriv, Base64.getDecoder().decode(kemCtB64))
            // 3. HKDF 混合 → AES key
            val finalKey = hybridKDF(ss1, ss2, roomId)
            // 4. AES-GCM 解密
            val nonce = Base64.getDecoder().decode(nonceB64)
            val ct = Base64.getDecoder().decode(ctB64)
            String(decrypt(finalKey, nonce, ct), Charsets.UTF_8)
        } catch (e: Exception) {
            null
        }
    }
}
