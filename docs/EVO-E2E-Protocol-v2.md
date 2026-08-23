# EVO E2E Protocol v2 — Hybrid X25519 + ML-KEM-768

> 状态：DRAFT（v1 兼容，v2 可选升级）
> 适用范围：EverettChat (EVO) iOS + Android 端到端加密消息
> 原则：两端严格按本规范实现，禁止各自"差不多的实现"

## 1. 设计目标

| 威胁 | v1 防护 | v2 新增防护 |
|------|---------|-----------|
| 暴力破解口令 | PBKDF2 100k 迭代 | ✅ 不变 |
| 经典破解 ECDH | 不使用 ECDH（口令模式） | ✅ X25519 |
| 量子破解（Harvest Now Decrypt Later） | ❌ 无防护 | ✅ ML-KEM-768 |
| 消息篡改 | AES-GCM Tag | ✅ 不变 |

**核心思路**：v2 在 v1 的 PBKDF2 房间密钥基础上，叠加 **X25519 + ML-KEM-768 混合共享密钥**，两端通过非对称协商得到联合密钥，即使量子计算机破解了 ECDH，ML-KEM 部分仍然安全。

## 2. 密钥层级

```
设备 A                              设备 B
───                                   ───
X25519 静态密钥对 (a_priv, a_pub)      X25519 静态密钥对 (b_priv, b_pub)
ML-KEM-768 静态密钥对 (A_priv, A_pub)  ML-KEM-768 静态密钥对 (B_priv, B_pub)
      │                                        │
      └────────── 公钥通过 relay 交换 ──────────┘
                        │
                        ▼
                混合密钥派生 (per-message)
        ┌─────────────────────────────────┐
        │ ❶ X25519 Ephemeral              │
        │   eph_priv → eph_pub            │
        │   ss1 = X25519(eph_priv, b_pub) │
        │                                 │
        │ ❷ ML-KEM-768 Encapsulate        │
        │   (kemCt, ss2) = Encaps(B_pub)   │
        │                                 │
        │ ❸ HKDF-SHA-384                  │
        │   finalKey = HKDF(ss1 || ss2,   │
        │     salt, info)                 │
        └─────────────────────────────────┘
                        │
                        ▼
                AES-256-GCM 消息密钥
```

**接收端**：
```
❶ X25519(b_priv, eph_pub) → ss1
❷ ML-KEM-Decaps(kemCt, B_priv) → ss2
❸ HKDF-SHA-384(ss1 || ss2, 相同 salt, info) → finalKey
❹ AES-GCM Decrypt(ciphertext, nonce, finalKey) → 明文
```

## 3. 密钥生成

### 每设备静态密钥对（长期有效，安装时生成）

```swift
// iOS
let x25519Priv = Curve25519.KeyAgreement.PrivateKey()
let x25519Pub = x25519Priv.publicKey  // 32B raw
let kemKeys = try Kyber768.generateKeyPair()
let kemPub = kemKeys.publicKey         // 1184B
let kemPriv = kemKeys.privateKey        // 2400B
```

```kotlin
// Android
val x25519Kp = KeyPairGenerator.getInstance("X25519").generateKeyPair()
val kemKp = KeyPairGenerator.getInstance("ML-KEM-768", "BC").generateKeyPair()
```

### 公钥存储

- 公钥（X25519 + ML-KEM）注册到 `POST /identity`
- 本地加密存储（iOS Keychain / Android EncryptedSharedPreferences）
- 设备恢复（Recovery Key）时随身份一起恢复

## 4. 消息加密流程

### 发送方（Alice → Bob）

```
1. 获取 Bob 的 X25519 公钥 + ML-KEM-768 公钥（从 relay /identity 查）
2. 生成临时 X25519 密钥对（ephemeral, 每条消息一次）
3. ss1 = X25519(eph_priv, bob_x25519_pub)     // 32B
4. (kemCt, ss2) = Kyber768.encapsulate(bob_kem_pub)  // kemCt 1088B, ss2 32B
5. finalKey = HKDF-SHA-384(
      ikm = ss1 || ss2,          // 64B 混合素材
      salt = SHA256("everett-e2e-v2|" + roomId)[0..16],
      info = "EVO-E2E-v2-hybrid",
      length = 32                 // 256-bit AES key
   )
6. nonce = random 12B
7. ct = AES-256-GCM.encrypt(plaintext, finalKey, nonce)
8. 构造 v2 envelope
```

### 接收方（Bob 收到）

```
1. 从 v2 envelope 提取 eph_pub, kemCt, nonce, ct
2. ss1 = X25519(bob_x25519_priv, eph_pub)
3. ss2 = Kyber768.decapsulate(kemCt, bob_kem_priv)
4. finalKey = HKDF-SHA-384(ss1 || ss2, 相同 salt, info)
5. plaintext = AES-256-GCM.decrypt(ct, finalKey, nonce)
```

## 5. 传输格式 (JSON Envelope v2)

### 外层（明文，与 v1 相同）

```json
{
  "type": "text|image|voice|video|file|ack|...",
  "id": "UUID",
  "from": "设备名",
  "senderId": "deviceId",
  "target": "目标 deviceId",
  "payload": { ... 见下 }
}
```

### 内层 payload（v2 格式）

```json
{
  "v": 2,
  "kem": "X25519+ML-KEM-768",
  "nonce": "<base64 12B AES-GCM nonce>",
  "ct": "<base64 ciphertext+tag>",
  "ephPub": "<base64 32B ephemeral X25519 pubkey>",
  "kemCt": "<base64 1088B ML-KEM encapsulate ciphertext>",
  "target": "目标 deviceId",
  "messageId": "UUID"
}
```

- `v` = 2：接收端按版本分派
- `ephPub`：发送方临时 X25519 公钥（接收方用此做 ECDH）
- `kemCt`：ML-KEM-768 封装密文（接收方用自己的静态 ML-KEM 私钥解封装）
- 不含 `kdf`/`iter`/`salt`（v2 固定参数，无用户口令）

### 兼容性

- 接收端先读 `v`：
  - `v == 1` → 走 v1 解密（PBKDF2 口令派生）
  - `v == 2` → 走 v2 解密（Hybrid KEM）
  - 无 `v` 字段 → 视为 v0 旧格式（可选降级）
- 发送端优先用 v2，如果对方公钥不可用 → 降级到 v1

## 6. HKDF 实现

### 规范

```
算法: HKDF-SHA-384
salt: SHA256("everett-e2e-v2|" + roomId) 前 16 字节
info: "EVO-E2E-v2-hybrid"
ikm:  ss1 (32B) || ss2 (32B)  — 共 64B
output: 32B (AES-256 key)
```

### Swift (iOS)

```swift
import CryptoKit

func hybridKDF(ss1: Data, ss2: Data, roomId: String) -> SymmetricKey {
    let salt = SHA256.hash(data: "everett-e2e-v2|\(roomId)".data(using: .utf8)!)
    let info = "EVO-E2E-v2-hybrid".data(using: .utf8)!
    let ikm = ss1 + ss2  // 64B
    let derived = HKDF<SHA384>.deriveKey(
        inputKeyMaterial: SymmetricKey(data: ikm),
        salt: Data(salt.prefix(16)),
        info: info,
        outputByteCount: 32
    )
    return derived
}
```

### Kotlin (Android)

```kotlin
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

fun hybridKDF(ss1: ByteArray, ss2: ByteArray, roomId: String): SecretKey {
    val salt = MessageDigest.getInstance("SHA-256")
        .digest("everett-e2e-v2|$roomId".toByteArray()).copyOf(16)
    val info = "EVO-E2E-v2-hybrid".toByteArray()
    val ikm = ss1 + ss2  // 64B
    // HKDF extract-then-expand
    val mac = Mac.getInstance("HmacSHA384")
    mac.init(SecretKeySpec(salt, "HmacSHA384"))
    val prk = mac.doFinal(ikm)  // 48B pseudorandom key
    mac.init(SecretKeySpec(prk, "HmacSHA384"))
    // expand
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
    return SecretKeySpec(result, "AES")
}
```

## 7. 密钥存储与恢复

| 密钥 | 存储位置 | 说明 |
|------|---------|------|
| X25519 私钥 | iOS Keychain / Android EncryptedSharedPreferences | 随设备身份生成 |
| ML-KEM-768 私钥 | iOS Keychain / Android EncryptedSharedPreferences | 2400B，随设备身份生成 |
| X25519 公钥 | relay.identity.publicKey | 已有字段，扩展 |
| ML-KEM-768 公钥 | relay.identity.kemPublicKey（新增字段） | 新字段，Base64 编码 |

- 恢复密钥（Recovery Key）包含：X25519 私钥 + ML-KEM 私钥的加密备份
- 换机恢复时，解密恢复密钥得到私钥，注册公钥到 relay

## 8. 测试向量

待两端实现后补充。

## 9. 依赖

### Android

```kotlin
// build.gradle.kts
dependencies {
    implementation("org.bouncycastle:bcprov-jdk18on:1.85.2")
}
```

- `Security.removeProvider("BC")` + `Security.addProvider(BouncyCastleProvider())`
- `KeyPairGenerator.getInstance("ML-KEM-768", "BC")`
- `KeyEncapsulation` API: `kem.encapsulate(pubKey)` / `kem.decapsulate(privKey, ct, 0, 32)`

### iOS

```swift
// Package.swift 或 project.yml
// dependencies: [.package(url: "https://github.com/leif-ibsen/SwiftKyber", from: "3.1.0")]
```

- `import SwiftKyber`
- `Kyber768.generateKeyPair()` → `(privateKey, publicKey)`
- `Kyber768.encapsulate(publicKey)` → `(ciphertext, sharedSecret)`
- `Kyber768.decapsulate(ciphertext, privateKey)` → `sharedSecret`

## 10. 实现检查清单

- [ ] 写 v2 协议规范（本文档）
- [ ] Android: 加 bcprov-jdk18on 依赖
- [ ] Android: CryptoEngine 加 ML-KEM keygen/encaps/decaps
- [ ] Android: CryptoEngine 加 HKDF-SHA-384
- [ ] Android: CryptoEngine 加 makeV2Payload/parseV2Payload
- [ ] iOS: 加 SwiftKyber SPM 依赖
- [ ] iOS: CryptoEngine 加 ML-KEM keygen/encaps/decaps
- [ ] iOS: CryptoEngine 加 HKDF-SHA-384（CryptoKit 已有）
- [ ] iOS: CryptoEngine 加 makeV2Payload/parseV2Payload
- [ ] 双端互通测试
- [ ] 设备公钥注册/查询（relay /identity 扩展）
- [ ] v1 → v2 降级兼容（对方无公钥时用 v1）