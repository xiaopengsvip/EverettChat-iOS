# EVO 设备间通信测试体系

> 从 Hermes 侧远程驱动设备互发消息，自动化验证双向通道，全程记录。

## 架构

```
Hermes (本机)
   │  curl / Python 脚本
   ▼
relay.vios.top (Cloudflare Workers)
   │  POST /cmd 推送命令 → 目标设备 WebSocket
   ▼
设备 A (iOS/Android)                    设备 B (iOS/Android)
   │  DiagAgent 执行命令                    │  收到 EVO-PING-xxx 消息
   │  send_ping_test → sendText            │  自动回显同文本
   │                                       ▼
   └── POST /cmd/result 上报结果     ──►  设备 A 收到回显 → 日志确认
```

## 设备端能力（DiagAgent）

| 命令 | 功能 | iOS | Android |
|---|---|---|---|
| `version`/`v` | 版本/设备/协议信息 | ✅ | ✅ |
| `status`/`st` | 连接状态/在线用户 | ✅ | ✅ |
| `log` | 最近 30 条日志 | ✅ | ✅ |
| `ping` | 健康检查 | ✅ | ✅ |
| `reconnect` | 强制重连中继 | ✅ | ✅ |
| `clear_logs` | 清日志 | ✅ | ✅ |
| `send_test`/`send_text` | 发文本给指定设备 | ✅ | ✅ |
| `send_ping_test` | 发 EVO-PING-xxx 互测消息 | ✅ | ✅ |
| `echo_reply` | 回显指定文本 | ✅ | — |
| `flush` | 主动上报日志到 relay | ✅ | — |

## 自动回显机制

- 设备收到 `EVO-PING-<tag>` 文本 → **自动回复同文本**给发送方
- 发送方收到回显 → 日志记录"收到互测"→ 双向通道验证成立

## 测试脚本

```bash
# 列出在线设备 + 自动跑所有设备对
python scripts/evo_interop_test.py

# 指定设备对测试
python scripts/evo_interop_test.py --from=<设备A的deviceId> --to=<设备B的deviceId>

# 多轮测试
python scripts/evo_interop_test.py --rounds=3

# 手动单步
curl -X POST https://relay.vios.top/cmd -H "Content-Type: application/json" \
  -d '{"target":"<A>","cmd":"send_ping_test","target":"<B>"}'     # A 发 ping
curl "https://relay.vios.top/cmd/result?requestId=<req>"           # 查结果
curl -X POST https://relay.vios.top/cmd -H "Content-Type: application/json" \
  -d '{"target":"<A>","cmd":"log"}'                                # A 查日志确认回显
```

## 测试记录（持续追加）

### 2026-08-24 凌晨（初测）

**在线设备**: 流星麒麟、曙光行者（vivo V2301A / SDK36）、幻影蜂鸟

| # | 场景 | 结果 |
|---|---|---|
| 1 | 远程 `version` → 曙光行者 | ✅ 回复 `{version:26.0824.0004, model:V2301A, sdk:36}` |
| 2 | 远程 `status` → 曙光行者 | ⏳ pending（设备装的是旧版，无 status 命令） |
| 3 | 远程 `version` → 幻影蜂鸟 | ⚠️ unknown（离线或旧版） |

**结论**: 远程命令通道 ✅ 打通；设备需升级到测试驱动版才有完整命令。

### 待测（装最新版后）

| # | 场景 | 预期 |
|---|---|---|
| T1 | iPhone ↔ 安卓A 双向 ping | 双向回显 |
| T2 | 安卓A ↔ 安卓B 双向 ping | 双向回显 |
| T3 | iPhone ↔ 安卓 文本 | 明文互通 |
| T4 | 安卓 ↔ 安卓 文本 | 明文互通 |
| T5 | 图片/语音/视频 | 互通 |
| T6 | 离线补发 | 上线收到 |
| T7 | 断网重连稳定性 | 重连后正常 |

## 稳定性问题排查流程（"不稳定"复现时）

1. `curl https://relay.vios.top/users` — 看谁在线
2. 对疑似设备发 `status` — 看连接状态
3. 发 `log` — 看最近日志（连接断开/解密失败都会记录）
4. 发 `reconnect` — 强制重连
5. 根据日志定位根因 → 修复 → 发新版
