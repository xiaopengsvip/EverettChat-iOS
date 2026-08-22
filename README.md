# EverettChat iOS

Everett AI 的 iOS 客户端（SwiftUI）—— 与 Android 版完全协议兼容（relay.vios.top Cloudflare 中继）。

## 功能
- 🔐 端到端加密通信（ECDH P-256 + AES-256-GCM，与 Android 互操作）
- 🤖 AI 三模型对话（DeepSeek V4 / 视觉 / Hy3，SSE 流式）
- 📱 好友系统：二维码互加 / 同意制联系人
- 📡 云中继自动连接 + 断线重连 + 心跳保活
- 🎨 2026 AI-Native 深色设计（悬浮 Tab Bar / Liquid Glass）

## 开发环境（Windows 用户）

Windows 无法直接编译 iOS，使用 **GitHub Actions 云构建**：

1. 把本项目推送到你的 GitHub 仓库
2. GitHub Actions 自动用 macOS 虚拟机构建
3. 在 Actions 页面下载 `EverettChat-simulator`（模拟器版）或 `EverettChat-device`（真机版）
4. 真机版需要签名配置（见下）

## 真机安装到 iPhone（17PM）

### 方式一：免费 Apple ID（7 天有效期）
1. 有 Mac 的电脑：Xcode → Signing & Capabilities → 用你的 Apple ID 自动签名
2. 构建后通过爱思助手/Apple Configurator 安装
3. 7 天后需重新签名安装

### 方式二：付费开发者账号（¥688/年，稳定）
在 GitHub Actions Secrets 配置：
- `IOS_DEVELOPMENT_TEAM`：你的 Team ID
- `IOS_SIGNING_IDENTITY`：签名证书标识
然后在 Release 分支推送，自动出签名版 ipa

## 本地开发（有 Mac 时）
```bash
brew install xcodegen
xcodegen generate
open EverettChat.xcodeproj
```

## 协议兼容性
- 中继：`wss://relay.vios.top/ws`（房间 everett-public）
- 加密：口令派生 AES-256-GCM（与 Android `CryptoEngine` 一致）
- 好友：`POST /friend-request`（浏览器 UA 防 Cloudflare 拦截）
- AI：`POST /ai/chat/completions`（SSE 流式）
