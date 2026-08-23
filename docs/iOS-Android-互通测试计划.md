# EVO iOS ↔ Android 互通测试计划

> 目标：验证双端文本/音视频通信完全互通，协议对齐后再开发 Android 新功能。

## 通信链路
- 中继: `wss://relay.vios.top/ws`（Cloudflare Workers）
- 房间: `everett-public` / 密码: `everett-public`
- 加密: CryptoEngine（passphrase 同上）

## 协议对照（关键差异！）

### 外层信封（relay 转发格式）
```json
{
  "type": "text|image|voice|video|ack|call-start|call-accept|call-reject|call-end|offer|answer|candidate|file",
  "id": "UUID",
  "from": "设备名",
  "senderId": "deviceId",
  "target": "目标 deviceId",
  "payload": { ... }
}
```

### iOS 行为（Android 需对齐）
| 项 | iOS | Android 现状 |
|---|---|---|
| 文本发送 | `text` + E2E data | ✅ `text` |
| 图片发送 | `image` + data + name/mime/text | ❌ 无 |
| 语音发送 | `voice` + data + durationMs | ⚠️ 类型名是 `audio`，需改 `voice` |
| 视频发送 | `video` + data + durationMs | ❌ 无 |
| 送达确认 | 收到 text/image/voice 自动回 `ack`（payload.ackId=原messageId） | ❌ 无 |
| 在线用户 | `get-users` 请求 / `online-users` 广播 | ⚠️ 需核对 |
| 心跳 | `ping` 10s | ✅ `ping` |
| 加入房间 | `join`（payload.room） | ✅ `join` |
| 通话信令 | `call-start/accept/reject/end` + `offer/answer/candidate` | ⚠️ 需核对字段 |
| TURN | 动态凭据 `/turn/credentials` | ❌ 无 |

### 消息 payload 结构
- **text**: `{"data":"<E2E密文>","target":"id","messageId":"UUID"}`
- **image**: `{"data":"<E2E密文>","name":"image.jpg","mime":"image/jpeg","text":"","target":"id","messageId":"UUID"}`
- **voice**: `{"data":"<E2E密文>","mime":"audio/m4a","durationMs":1234,"target":"id","messageId":"UUID"}`
- **video**: `{"data":"<E2E密文>","mime":"video/mp4","durationMs":5000,"target":"id","messageId":"UUID"}`
- **ack**: `{"ackId":"原messageId","target":"deviceId"}`
- 收到方解析：`CryptoEngine.parseMessage` → 解密 payload.data

## 测试场景矩阵

### T1 文本互通
- [ ] iOS ↔ Android 互相可见（online-users）
- [ ] iOS → Android 文本
- [ ] Android → iOS 文本
- [ ] ACK：iOS 发 → Android 回 → iOS 显示 ✓✓ 已送达
- [ ] 长文本 / emoji / 中英文

### T2 图片互通
- [ ] iOS 发压缩图 → Android 显示
- [ ] Android 发图 → iOS 显示
- [ ] 原图 5MB+ 传输
- [ ] 图片+文字

### T3 语音互通
- [ ] iOS 录语音 → Android 播放（时长正确）
- [ ] Android 录语音 → iOS 播放
- [ ] 60s+ 长语音

### T4 视频互通
- [ ] iOS → Android 视频
- [ ] Android → iOS 视频
- [ ] 时长显示

### T5 WebRTC 通话
- [ ] iOS 呼叫 Android（语音）→ 接听 → 双向
- [ ] Android 呼叫 iOS → 接听 → 双向
- [ ] 视频通话双向
- [ ] 拒绝/挂断/超时
- [ ] TURN 兜底（无局域网）

### T6 离线消息
- [ ] Android 离线 → iOS 发 → Android 上线补收
- [ ] 反之
- [ ] 多条离线消息

### T7 文件互传（局域网）
- [ ] NFC 配对（双端 NFC 手机）
- [ ] MultipeerConnectivity ↔ Android Nearby/NSD
- [ ] 大文件分片

## 测试环境
- iOS 真机: 最新 IPA（EVO-设备管理版.ipa 起）
- Android 真机: 最新 APK
- 网络: 同一 Wi-Fi / 4G+5G
- 准备: 两台手机 + 电脑（可测 Hermes 设备互联）

## Android 协议对齐改造清单（互通前置）
1. `RelayTransport.kt`：audio → voice 类型名；加 image/video 发送；收到 text/image/voice 自动回 ack
2. payload 统一 senderId（不用 from）
3. `CallManager.kt`：信令字段对齐 iOS（call-start/offer/answer/candidate 负载）
4. 加 TURN 动态凭据（GET relay.vios.top/turn/credentials）
5. 离线补发：relay 服务端已存队列，客户端 join 后自动收

## 验证命令
```bash
curl https://relay.vios.top/health          # relay 健康
# iOS 构建: cd /d/EverettChat-iOS && git push
# Android 构建: cd /c/Users/XIAO2027/EverettChat && export JAVA_HOME=/d/Android/jbr && ./gradle-dist/bin/gradle assembleDebug --no-daemon
```
