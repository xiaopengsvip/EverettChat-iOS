# EVO E2E Protocol v1

> 状态：ACTIVE（v1 生效中，v2 规划中）
> 适用范围：EverettChat (EVO) iOS + Android 跨平台端到端加密消息
> 原则：两端严格按本规范实现，禁止各自"差不多的实现"

## 1. 目标

- iOS / Android 完全互通（能加密也能互相解密）
- 密码派生抗暴力破解（PBKDF2 迭代）
- 消息防篡改（AES-GCM 认证 Tag）
- 房间隔离（每房间独立 Salt）
- 协议版本化（未来升级不破坏兼容）

## 2. 架构总览

```
用户口令 (passphrase)
     │
     ▼
PBKDF2-HMAC-SHA256
     │  ├── salt (房间独立)
     │  ├── iterations: 100,000
     │  └── dkLen: 32 bytes (256-bit)
     ▼
AES-256-GCM Key
     │
     ├── random 12-byte nonce (每消息)
     │
     ▼
plaintext ──► ciphertext + 16-byte auth tag
```

**注意**：口令只派生"房间密钥"（Room Key），不直接作为用户身份主密钥。
身份/恢复密钥体系见 `DeviceIdentity`（Root Key + Recovery Key），与消息加密分层。

## 3. 密钥派生 (KDF)

| 参数 | 值 |
|---|---|
| 算法 | PBKDF2-HMAC-SHA256 |
| iterations | 100,000 |
| dkLen | 32 bytes (256-bit) |
| salt | `SHA256("everett-e2e-v1|" + roomId)` 的前 16 字节 |

- **salt 与房间绑定**：同房间所有客户端派生相同密钥；不同房间即使口令相同密钥也不同（房间隔离）
- **salt 可公开**：不依赖 salt 保密（PBKDF2 标准假设 salt 公开）
- **口令保密**：`passphrase` 是唯一保密因子

### Swift (iOS)
```swift
import CommonCrypto

func pbkdf2SHA256(passphrase: String, salt: Data, iterations: Int, keyLen: Int) -> Data? {
    var key = Data(count: keyLen)
    let result = key.withUnsafeMutableBytes { keyPtr in
        passphrase.withCString { passPtr in
            salt.withUnsafeBytes { saltPtr in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passPtr, passphrase.utf8.count,
                    saltPtr.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(iterations),
                    keyPtr.bindMemory(to: UInt8.self).baseAddress, keyLen
                )
            }
        }
    }
    return result == kCCSuccess ? key : nil
}
```

### Kotlin (Android)
```kotlin
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec

fun deriveKey(passphrase: String, salt: ByteArray, iterations: Int = 100_000): SecretKey {
    val spec = PBEKeySpec(passphrase.toCharArray(), salt, iterations, 256)
    return SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
        .generateSecret(spec) as SecretKey
}
```

## 4. 消息加密 (AES-256-GCM)

| 参数 | 值 |
|---|---|
| 算法 | AES-256-GCM |
| Key | 32 bytes（PBKDF2 输出） |
| Nonce | 12 bytes，每消息随机（`SecureRandom`/`SecRandomCopyBytes`） |
| Tag | 16 bytes（128-bit，GCM 自动附加） |
| 明文 | 纯文本内容 / 明确规定的 JSON payload（不整体加密外层 envelope） |

### 密文编码（两端一致）
- 传输时 `nonce`、`ciphertext`（含 tag）**分开传输**（不合并成 combined）
- 均使用标准 Base64 编码

### Swift (iOS)
```swift
import CryptoKit

func encrypt(_ plain: String, key: SymmetricKey) throws -> (nonce: Data, ciphertext: Data) {
    let nonce = AES.GCM.Nonce()  // 12B random
    let sealed = try AES.GCM.seal(Data(plain.utf8), using: key, nonce: nonce)
    return (nonce.data, sealed.ciphertext + sealed.tag)  // ct || tag
}

func decrypt(nonce: Data, ciphertext: Data, key: SymmetricKey) throws -> String {
    let tag = ciphertext.suffix(16)
    let ct = ciphertext.prefix(ciphertext.count - 16)
    let sealed = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce),
                                       ciphertext: Data(ct), tag: Data(tag))
    let plain = try AES.GCM.open(sealed, using: key)
    return String(data: plain, encoding: .utf8) ?? ""
}
```

### Kotlin (Android)
```kotlin
fun encrypt(key: SecretKey, plaintext: ByteArray): Pair<ByteArray, ByteArray> {
    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
    val nonce = ByteArray(12).also { SecureRandom().nextBytes(it) }
    cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(128, nonce))
    val ct = cipher.doFinal(plaintext)  // ct || tag
    return nonce to ct
}

fun decrypt(key: SecretKey, nonce: ByteArray, ciphertext: ByteArray): ByteArray {
    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
    cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, nonce))
    return cipher.doFinal(ciphertext)
}
```

## 5. 传输格式 (JSON Envelope)

### 外层（relay 路由，明文，仅元数据）
```json
{
  "type": "text|image|voice|video|file|ack|...",
  "id": "UUID",
  "from": "设备名",
  "senderId": "deviceId",
  "target": "目标 deviceId（可选）",
  "payload": { ... 见下 }
}
```

### 内层 payload（加密内容，v1 格式）
```json
{
  "v": 1,
  "kdf": "PBKDF2-HMAC-SHA256",
  "iter": 100000,
  "salt": "<base64 16B 房间盐>",
  "nonce": "<base64 12B>",
  "ct": "<base64 ciphertext+tag>",
  "target": "目标 deviceId（冗余路由）",
  "messageId": "UUID"
}
```

- **version 字段（v）**：接收端先读 v，按对应版本解密；未来 v2（PQC）可并存
- **salt/iter 字段**：接收端可用发送方参数解密（兼容未来迭代次数调整）
- **只加密明文内容**：`ct` 解密后即明文文本（text 类型）或 JSON 字符串（image/voice/video 的元数据+数据）

### 类型明细

| type | 明文内容 (解密后) |
|---|---|
| text | 纯文本字符串 |
| image | `{"data":"<b64>","name":"...","mime":"...","text":"..."}` |
| voice | `{"data":"<b64>","mime":"audio/m4a","durationMs":1234}` |
| video | `{"data":"<b64>","mime":"video/mp4","durationMs":5000}` |
| file | `{"fileId":"...","name":"...","size":N,"mime":"..."}` |
| ack | 明文（`{"ackId":"原messageId","target":"..."}`）不加密 |

## 6. ACK 送达确认

- 收到 `text/image/voice/video` 且含 `messageId` → 自动回 `ack`
- ack 格式：`{"type":"ack","payload":{"ackId":"原messageId","target":"原senderId"}}`
- ack 不加密（仅元数据）

## 7. 心跳与握手

- `join`：明文 `{"type":"join","payload":{"room":"..."}}`
- `welcome`：服务器回复（明文）
- `ping/pong`：明文（仅时间戳，无内容）
- 心跳间隔：10s

## 8. 密钥轮换与升级（v1.1+）

- **房间盐轮换**：换盐即换密钥（通知机制 v1.1 实现）
- **口令修改**：仅影响房间密钥派生，不影响历史消息（历史密文用旧密钥仍可解）
- **多设备**：每设备独立 deviceId；Room Key 由口令派生，天然多设备共享

## 9. PQC 抗量子规划（v2，未实现）

```
设备 A                        设备 B
  │  X25519 (经典) ──────────  │
  │  ML-KEM-768 (后量子) ────  │
  └──────── Hybrid Secret ─────┘
                 │
              HKDF-SHA-384
                 │
          AES-256-GCM Message Key
                 │
              消息
```

- 密钥协商：X25519 + ML-KEM-768 **Hybrid**（经典+后量子双保险）
- 消息加密：AES-256-GCM 不变（AES-256 对量子有足够余量）
- 身份认证：ML-DSA-65（FIPS 204）
- 口令保护：PBKDF2-HMAC-SHA256 不变（保护本地私钥）
- 依赖：iOS 26+ CryptoKit ML-KEM 支持 / Android BouncyCastle PQC；两端平台支持后实现

## 10. 测试向量（用于两端互通验证）

```
passphrase = "everett-public"
roomId     = "everett-public"
salt       = SHA256("everett-e2e-v1|everett-public")[0..16]
key        = PBKDF2-HMAC-SHA256(passphrase, salt, 100000, 32)

测试消息: "你好 EVO"
nonce      = 固定 12B（测试用）：00 01 02 03 04 05 06 07 08 09 0A 0B
```
（固定 nonce 仅测试；生产必须随机）

## 11. 实现检查清单

- [ ] iOS CryptoEngine：PBKDF2 + 显式 nonce/tag + v1 envelope
- [ ] Android CryptoEngine：PBKDF2 参数统一 + v1 envelope
- [ ] iOS RelayTransport：payload 改 v1 格式
- [ ] Android RelayTransport：payload 改 v1 格式
- [ ] 双端互通测试：文本/图片/语音/视频
- [ ] 旧版本密文兼容策略：v0 检测（无 v 字段 → 尝试旧解密）可选
