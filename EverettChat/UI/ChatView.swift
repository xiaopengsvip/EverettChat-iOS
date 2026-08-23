import SwiftUI
import UIKit
import PhotosUI
import AVFoundation

/// 聊天页（AI / 对端，Document Style + 思考折叠 + 模型选择）
struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @State private var input = ""
    // 语音录制
    @State private var recorder: AVAudioRecorder?
    @State private var isRecording = false
    @State private var recordingSeconds: Double = 0
    @State private var recordTimer: Timer?
    @State private var voicePlayer: AVAudioPlayer?
    @State private var playingVoiceId: String?
    @State private var showVoiceHint = false
    @State private var isStreaming = false
    @State private var showModelSheet = false
    @State private var selectedModel = ApiConfig.model
    @State private var showReasoning = false
    @State private var messages: [ChatMessage] = []
    @State private var scrollProxy: ScrollViewProxy?
    @State private var showInfoSheet = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var webURL: URL?
    // +号功能面板
    @State private var showPlusPanel = false
    // 相册
    @State private var showPhotoPicker = false
    // 文件发送
    @State private var showFilePicker = false
    // 拍摄
    @State private var showCamera = false
    @State private var cameraImage: UIImage?
    // 语音按住录音：上滑取消
    @State private var isVoiceSlidingUp = false
    @State private var voiceDragOffset: CGFloat = 0
    @State private var voiceHintText = ""
    // 语音/键盘切换模式
    @State private var voiceMode = false
    // 表情面板
    @State private var showEmojiPanel = false

    private var isAI: Bool { appState.chatMode == "ai" }
    private let apiClient = ChatApiClient()

    var body: some View {
        VStack(spacing: 0) {
            // 顶栏：返回 + 居中标题 + 副标题（模型名/ID）+ ℹ️
            ZStack {
                // 居中标题
                VStack(alignment: .center, spacing: 1) {
                    Text(isAI ? "AI 助手" : appState.chatPeerName)
                        .font(.headline)
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)
                    Text(isAI ? currentModelName : "ID: \(String(appState.chatPeerId.prefix(8)))")
                        .font(.caption2)
                        .foregroundColor(Theme.textTertiary)
                }
                // 左侧返回
                HStack {
                    Button {
                        appState.showChat = false
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                    }
                    Spacer()
                    // 右侧信息
                    Button {
                        showInfoSheet = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 18))
                            .foregroundColor(Theme.textSecondary)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
            // 顶栏与内容区分：原生材质背景 + 底部细分隔线
            .background(.thinMaterial)
            .overlay(alignment: .bottom) {
                Divider().overlay(Theme.surfaceHigh)
            }

            // 消息列表
            MessageListView(
                messages: messages,
                isAI: isAI,
                isStreaming: isStreaming,
                streamContent: streamContent,
                streamReasoning: streamReasoning,
                deviceName: appState.deviceName,
                playingVoiceId: playingVoiceId,
                onPlayVoice: playVoice,
                onStopVoice: stopVoice,
                onCopy: { msg in UIPasteboard.general.string = msg.text },
                onRegenerate: regenerateAIResponse,
                onDelete: deleteMessage,
                onCountChange: { proxy in
                    withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
                },
                onStreamChange: { proxy in
                    withAnimation { proxy.scrollTo("streaming", anchor: .bottom) }
                }
            )

            // 输入区
            VStack(spacing: 0) {
                if isAI {
                    ModelSwitcherRow(
                        icon: currentModelIcon,
                        name: currentModelName,
                        onTap: { showModelSheet = true }
                    )
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, 4)
                }

                // +号附件面板（微信风格网格，输入框上方展开）
                if showPlusPanel {
                    AttachmentPanel(
                        onAlbum: { showPhotoPicker = true },
                        onCamera: { showCamera = true },
                        onFile: { showFilePicker = true },
                        onVoiceCall: { voiceHintText = "语音电话即将上线"; showVoiceHint = true },
                        onLocation: {
                            voiceHintText = "位置功能即将上线"; showVoiceHint = true
                        },
                        onRedPacket: {
                            voiceHintText = "红包功能即将上线"; showVoiceHint = true
                        },
                        onGift: {
                            voiceHintText = "礼物功能即将上线"; showVoiceHint = true
                        },
                        onTransfer: {
                            voiceHintText = "转账功能即将上线"; showVoiceHint = true
                        },
                        onVoiceInput: {
                            voiceHintText = "语音输入即将上线"; showVoiceHint = true
                        },
                        onNamecard: {
                            let card = "我的 ID: \(DeviceIdentity.shared.shortId) · 昵称: \(DeviceIdentity.shared.deviceName)"
                            if isAI {
                                let msg = ChatMessage(role: "user", text: card)
                                messages.append(msg)
                                sendAI(text: card, imageBase64: "")
                            } else {
                                let msg = ChatMessage(role: "user", text: card, senderId: appState.chatPeerId)
                                messages.append(msg)
                                appState.transport.sendText(card, target: appState.chatPeerId, messageId: msg.id)
                            }
                            showPlusPanel = false
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // 表情面板
                if showEmojiPanel {
                    EmojiPanel { emoji in
                        input += emoji
                        showEmojiPanel = false
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // 输入区（微信布局：语音切换 + 输入框/按住说话 + 表情 + 加号）
                ChatInputBar(
                    input: $input,
                    isAI: isAI,
                    peerName: appState.chatPeerName,
                    voiceMode: voiceMode,
                    isRecording: isRecording,
                    isVoiceSlidingUp: isVoiceSlidingUp,
                    recordingSeconds: recordingSeconds,
                    onToggleVoiceMode: {
                        voiceMode.toggle()
                        showEmojiPanel = false
                        showPlusPanel = false
                    },
                    onEmoji: {
                        showEmojiPanel.toggle()
                        showPlusPanel = false
                        voiceMode = false
                    },
                    onPlus: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showPlusPanel.toggle()
                            showEmojiPanel = false
                        }
                    },
                    onSend: { send() },
                    onStartRecord: { startRecording() },
                    onEndRecord: { stopRecordingAndSend() },
                    onCancelRecord: { cancelRecording() },
                    onSlideUpChange: { up in isVoiceSlidingUp = up },
                    onDragChange: { h in voiceDragOffset = h }
                )
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
            }
            // 原生 Liquid Glass 输入区
            .background(.thinMaterial)
        }
        .background(Theme.bg)
        // 微信式录音浮层（按住录音时显示）
        .overlay {
            if isRecording {
                RecordingOverlay(
                    seconds: recordingSeconds,
                    dragOffset: voiceDragOffset,
                    onCancel: { cancelRecording() },
                    onToText: { voiceHintText = "语音转文字即将上线"; showVoiceHint = true; cancelRecording() },
                    onSend: { stopRecordingAndSend() }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isRecording)
        // 语音提示浮层（录音提示/功能提示）
        .overlay(alignment: .top) {
            if showVoiceHint {
                VoiceHintBubble(text: voiceHintText, isRecording: isRecording)
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showVoiceHint)
        .sheet(isPresented: $showModelSheet) { ModelPickerSheet(selected: $selectedModel) }
        .sheet(isPresented: $showInfoSheet) { ChatInfoSheet(isAI: isAI) }
        // 文件选择器
        .sheet(isPresented: $showFilePicker) {
            DocumentPicker { _, fileName, data in
                sendFile(name: fileName, data: data)
            }
        }
        // 相机拍摄
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                sendCameraImage(image)
            }
        }
        // 相册（PhotosPicker 展示）
        .photosPicker(isPresented: $showPhotoPicker, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    let resized = img.resized(maxSide: 1280)
                    let jpeg = resized.jpegData(compressionQuality: 0.8) ?? data
                    let b64 = jpeg.base64EncodedString()
                    if isAI {
                        let msg = ChatMessage(role: "user", text: "", imageBase64: b64)
                        messages.append(msg)
                        sendAI(text: "", imageBase64: b64)
                    } else {
                        let msg = ChatMessage(role: "user", text: "", imageBase64: b64, senderName: DeviceIdentity.shared.deviceName)
                        messages.append(msg)
                        appState.transport.sendImage(base64: b64, target: appState.chatPeerId, messageId: msg.id)
                    }
                }
                pickerItem = nil
            }
        }
        // 消息内链接 → 应用内浏览器（不跳出 Safari）
        .environment(\.openURL, OpenURLAction { url in
            webURL = url
            return .handled
        })
        .fullScreenCover(item: $webURL) { url in
            SafariView(url: url)
        }
        .onAppear {
            messages = isAI ? appState.aiMessages : peerMessagesForCurrent()
        }
        .onReceive(appState.$peerMessages) { newValue in
            if !isAI {
                let filtered = newValue.filter { $0.senderId == appState.chatPeerId }
                if filtered != messages { messages = filtered }
            }
        }
        .onChange(of: messages) { newValue in
            if isAI { appState.aiMessages = newValue } else { writeBackPeerMessages(newValue) }
        }
        .onDisappear {
            if isAI { appState.aiMessages = messages } else { writeBackPeerMessages(messages) }
        }
    }

    /// 当前会话的消息（按 chatPeerId 过滤）
    private func peerMessagesForCurrent() -> [ChatMessage] {
        appState.peerMessages.filter { $0.senderId == appState.chatPeerId }
    }

    /// 写回当前会话消息（合并进全局 peerMessages）
    private func writeBackPeerMessages(_ sessionMsgs: [ChatMessage]) {
        var all = appState.peerMessages.filter { $0.senderId != appState.chatPeerId }
        all.append(contentsOf: sessionMsgs)
        appState.peerMessages = all.sorted { $0.createdAt < $1.createdAt }
    }

    private var currentModel: ApiConfig.ModelInfo {
        ApiConfig.models.first { $0.id == selectedModel } ?? ApiConfig.models[0]
    }
    private var currentModelName: String { currentModel.name }
    private var currentModelIcon: String { currentModel.vision ? "👁" : "🤖" }
    private var streamContent: String { apiClient.streamText }
    private var streamReasoning: String { apiClient.reasoningText }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        input = ""

        let userMsg = ChatMessage(role: "user", text: text, senderId: isAI ? "" : appState.chatPeerId)
        messages.append(userMsg)

        if isAI {
            sendAI(text)
        } else {
            // 对端加密发送（带 messageId 用于送达确认）
            appState.transport.sendText(text, target: appState.chatPeerId, messageId: userMsg.id)
        }
    }

    private func sendAI(_ text: String) {
        isStreaming = true
        // 灵动岛：AI 任务开始
        EvoActivityManager.shared.start(sessionId: "ai", peerName: "EVO AI")
        EvoActivityManager.shared.update(status: "思考中", progress: 0.1, fileName: text.count > 20 ? String(text.prefix(20)) + "…" : text)
        let history = messages.dropLast().map { (role: $0.role == "user" ? "user" : "assistant", content: $0.text) }
        Task {
            let result = await apiClient.sendMessage(
                history: history,
                userMessage: text,
                model: selectedModel,
                onDelta: { delta, isReasoning in
                    Task { @MainActor in
                        if isReasoning {
                        } else {
                            if let last = messages.last, last.role == "ai" {
                                messages[messages.count - 1] = ChatMessage(
                                    id: last.id, role: "ai", text: last.text + delta,
                                    reasoning: last.reasoning
                                )
                            } else {
                                messages.append(ChatMessage(role: "ai", text: delta))
                            }
                        }
                    }
                }
            )
            isStreaming = false
            if result == nil || result?.isEmpty == true {
                messages.append(ChatMessage(role: "ai", text: "（无回复）", isError: true))
                EvoActivityManager.shared.end(status: "失败", progress: 0)
            } else {
                EvoActivityManager.shared.end(status: "完成", progress: 1)
            }
        }
    }

    /// 发送图片给 AI（vision 模型）
    private func sendAI(text: String, imageBase64: String) {
        isStreaming = true
        EvoActivityManager.shared.start(sessionId: "ai", peerName: "EVO AI")
        EvoActivityManager.shared.update(status: "分析图片中", progress: 0.2)
        let history = messages.dropLast().map { (role: $0.role == "user" ? "user" : "assistant", content: $0.text) }
        Task {
            let result = await apiClient.sendImageMessage(
                history: history,
                userMessage: text,
                imageBase64: imageBase64,
                model: ApiConfig.visionModel,
                onDelta: { delta, isReasoning in
                    Task { @MainActor in
                        if isReasoning {
                        } else {
                            if let last = messages.last, last.role == "ai" {
                                messages[messages.count - 1] = ChatMessage(
                                    id: last.id, role: "ai", text: last.text + delta,
                                    reasoning: last.reasoning
                                )
                            } else {
                                messages.append(ChatMessage(role: "ai", text: delta))
                            }
                        }
                    }
                }
            )
            isStreaming = false
            if result == nil || result?.isEmpty == true {
                messages.append(ChatMessage(role: "ai", text: "（无回复）", isError: true))
                EvoActivityManager.shared.end(status: "失败", progress: 0)
            } else {
                EvoActivityManager.shared.end(status: "完成", progress: 1)
            }
        }
    }

    private func deleteMessage(_ message: ChatMessage) {
        messages.removeAll { $0.id == message.id }
    }

    // MARK: - 语音录制与播放

    private func startRecording() {
        if isAI {
            showVoiceHint = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showVoiceHint = false }
            return
        }
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            guard granted else {
                showVoiceHint = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showVoiceHint = false }
                return
            }
            DispatchQueue.main.async {
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playAndRecord, mode: .default)
                    try session.setActive(true)
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("evo_voice_\(Date().timeIntervalSince1970).m4a")
                    let settings: [String: Any] = [
                        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                        AVSampleRateKey: 44100,
                        AVNumberOfChannelsKey: 1,
                        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
                    ]
                    let rec = try AVAudioRecorder(url: url, settings: settings)
                    rec.record()
                    recorder = rec
                    isRecording = true
                    recordingSeconds = 0
                    recordTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                        recordingSeconds = rec.currentTime
                    }
                } catch {
                    showVoiceHint = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showVoiceHint = false }
                }
            }
        }
    }

    private func stopRecordingAndSend() {
        recordTimer?.invalidate()
        recordTimer = nil
        guard let rec = recorder, rec.isRecording else {
            isRecording = false
            return
        }
        let duration = rec.currentTime
        rec.stop()
        isRecording = false
        let url = rec.url
        guard let data = try? Data(contentsOf: url), duration > 0.5 else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let b64 = data.base64EncodedString()
        let msg = ChatMessage(role: "user", text: "", voiceBase64: b64, voiceDurationMs: duration * 1000, senderName: DeviceIdentity.shared.deviceName)
        messages.append(msg)
        appState.transport.sendVoice(base64: b64, target: appState.chatPeerId, durationMs: duration * 1000, messageId: msg.id)
        try? FileManager.default.removeItem(at: url)
    }

    /// 上滑取消录音（丢弃）
    private func cancelRecording() {
        recordTimer?.invalidate()
        recordTimer = nil
        guard let rec = recorder else {
            isRecording = false
            return
        }
        rec.stop()
        isRecording = false
        try? FileManager.default.removeItem(at: rec.url)
    }

    private func playVoice(_ msg: ChatMessage) {
        stopVoice()
        guard let data = Data(base64Encoded: msg.voiceBase64) else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(data: data)
            player.play()
            voicePlayer = player
            playingVoiceId = msg.id
        } catch {
            playingVoiceId = nil
        }
    }

    private func stopVoice() {
        voicePlayer?.stop()
        voicePlayer = nil
        playingVoiceId = nil
    }

    /// 发送文件（Base64 传输，带文件名）
    private func sendFile(name: String, data: Data) {
        let b64 = data.base64EncodedString()
        let text = "[文件] \(name)"
        if isAI {
            let msg = ChatMessage(role: "user", text: text)
            messages.append(msg)
            sendAI(text: text, imageBase64: "")
        } else {
            let msg = ChatMessage(role: "user", text: text, senderName: DeviceIdentity.shared.deviceName)
            messages.append(msg)
            // 文件走图片通道？（relay 无 file 类型）——用文本通道发文件名 + data 标记
            appState.transport.sendText("[file]\(name)::\(b64)", target: appState.chatPeerId, messageId: msg.id)
        }
    }

    /// 发送拍摄的照片
    private func sendCameraImage(_ image: UIImage) {
        let resized = image.resized(maxSide: 1280)
        let jpeg = resized.jpegData(compressionQuality: 0.8) ?? Data()
        let b64 = jpeg.base64EncodedString()
        if isAI {
            let msg = ChatMessage(role: "user", text: "", imageBase64: b64)
            messages.append(msg)
            sendAI(text: "", imageBase64: b64)
        } else {
            let msg = ChatMessage(role: "user", text: "", imageBase64: b64, senderName: DeviceIdentity.shared.deviceName)
            messages.append(msg)
            appState.transport.sendImage(base64: b64, target: appState.chatPeerId, messageId: msg.id)
        }
    }

    private func regenerateAIResponse(for message: ChatMessage) {
        guard isAI, !isStreaming,
              let messageIndex = messages.firstIndex(where: { $0.id == message.id }),
              let userMessage = messages[..<messageIndex].last(where: { $0.role == "user" })
        else { return }

        messages.removeSubrange(messageIndex..<messages.endIndex)
        sendAI(userMessage.text)
    }
}

/// 消息气泡
struct MessageBubble: View {
    let msg: ChatMessage
    let isMine: Bool
    let isAI: Bool
    let deviceName: String
    let playingVoiceId: String?
    let onPlayVoice: (ChatMessage) -> Void
    let onStopVoice: () -> Void

    /// 送达状态图标（自己发的消息：✓ 已发送 / ✓✓ 已送达 / ! 失败）
    @ViewBuilder
    private var deliveryStatusIcon: some View {
        switch msg.status {
        case "delivered":
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(.green)
        case "failed":
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(Theme.error)
        default:
            Image(systemName: "checkmark")
                .font(.system(size: 10))
                .foregroundColor(Theme.textTertiary)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // 左头像列（对方）
            if !isMine {
                Circle()
                    .fill(isAI ? Theme.primaryDim : Theme.surfaceAlt)
                    .frame(width: 36, height: 36)
                    .overlay(Text(isAI ? "🤖" : "👤").font(.system(size: 18)))
            } else {
                Color.clear.frame(width: 44, height: 44)
            }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 3) {
                if isMine {
                    HStack(spacing: 4) {
                        if msg.role == "user" && !isAI {
                            deliveryStatusIcon
                        }
                        Text("我 · \(deviceName)")
                            .font(.caption2)
                            .foregroundColor(Theme.textTertiary)
                    }
                } else {
                    Text(isAI ? "AI 助手" : msg.senderName)
                        .font(.caption2)
                        .foregroundColor(isAI ? Theme.info : Theme.textTertiary)
                }

                // 气泡内容
                if isAI {
                    VStack(alignment: .leading, spacing: 4) {
                        if !msg.reasoning.isEmpty {
                            Text("🤔 思考过程 ▸")
                                .font(.caption2)
                                .foregroundColor(Theme.textTertiary)
                        }
                        if !msg.imageBase64.isEmpty, let data = Data(base64Encoded: msg.imageBase64), let ui = UIImage(data: data) {
                            Image(uiImage: ui)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 240)
                                .cornerRadius(12)
                        }
                        if !msg.text.isEmpty {
                            Text(renderRichText(msg.text))
                                .font(.body)
                                .foregroundColor(Theme.textPrimary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: 320, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.medium)
                            .fill(Theme.bubbleAi)
                    )
                } else {
                    VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                        if !msg.imageBase64.isEmpty, let data = Data(base64Encoded: msg.imageBase64), let ui = UIImage(data: data) {
                            Image(uiImage: ui)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 240)
                                .cornerRadius(12)
                        }
                        // 语音消息：▶ 播放按钮 + 时长
                        if !msg.voiceBase64.isEmpty {
                            Button {
                                if playingVoiceId == msg.id {
                                    onStopVoice()
                                } else {
                                    onPlayVoice(msg)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: playingVoiceId == msg.id ? "stop.circle.fill" : "play.circle.fill")
                                        .font(.system(size: 26))
                                    Text(String(format: "%.0f\"", msg.voiceDurationMs / 1000))
                                        .font(.caption)
                                        .monospacedDigit()
                                }
                                .foregroundColor(isMine ? .white : Theme.textPrimary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                            }
                        }
                        if !msg.text.isEmpty {
                            Text(renderRichText(msg.text))
                                .font(.body)
                                .foregroundColor(isMine ? .white : Theme.textPrimary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isMine ? Theme.bubbleMine : Theme.bubblePeer)
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)

            // 右头像列（自己）
            if isMine {
                Circle()
                    .fill(Theme.surfaceAlt)
                    .frame(width: 36, height: 36)
                    .overlay(Text("👤").font(.system(size: 18)))
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
    }
}

/// 模型选择 Sheet
struct ModelPickerSheet: View {
    @Binding var selected: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("选择模型")
                .font(.headline)
                .padding(Spacing.xl)
            ForEach(ApiConfig.models) { m in
                Button {
                    selected = m.id
                    dismiss()
                } label: {
                    HStack(spacing: 14) {
                        Text(m.vision ? "👁" : "🤖").font(.title3)
                        VStack(alignment: .leading) {
                            Text(m.name)
                                .font(.body.weight(selected == m.id ? .semibold : .regular))
                                .foregroundColor(selected == m.id ? Theme.primary : Theme.textPrimary)
                            Text(m.desc)
                                .font(.caption)
                                .foregroundColor(Theme.textTertiary)
                        }
                        Spacer()
                        if selected == m.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Theme.primary)
                        }
                    }
                    .padding(Spacing.lg)
                }
                Divider().overlay(Theme.surfaceHigh).padding(.leading, 56)
            }
            Spacer()
        }
        .background(Theme.surface)
        .presentationDetents([.height(260)])
    }
}

/// 会话信息 Sheet
struct ChatInfoSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let isAI: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Circle()
                    .fill(isAI ? Theme.primaryDim : Theme.surfaceAlt)
                    .frame(width: 52, height: 52)
                    .overlay(Text(isAI ? "🤖" : "👤").font(.title3))
                VStack(alignment: .leading) {
                    Text(isAI ? "AI 助手" : appState.chatPeerName)
                        .font(.headline)
                        .foregroundColor(Theme.textPrimary)
                    Text(isAI ? "云端 AI · 非端到端加密" : "ID: \(appState.chatPeerId)")
                        .font(.caption2.monospaced())
                        .foregroundColor(Theme.textTertiary)
                }
                Spacer()
            }
            .padding(Spacing.xl)

            Divider().overlay(Theme.surfaceHigh)

            if isAI {
                InfoRow(icon: "🤖", title: "当前模型", subtitle: "DeepSeek V4")
                InfoRow(icon: "🔐", title: "加密说明", subtitle: "AI 对话经云端中继代理，非端到端加密")
                Button {
                    appState.aiMessages.removeAll()
                    dismiss()
                } label: {
                    InfoRow(icon: "🧹", title: "清除对话", subtitle: "清空当前 AI 会话历史")
                }
            } else {
                InfoRow(icon: "🔗", title: "连接状态", subtitle: "中继连接")
                InfoRow(icon: "🔐", title: "加密说明", subtitle: "端到端加密 · 消息仅双方可见")
            }
            Spacer()
        }
        .background(Theme.surface)
        .presentationDetents([.height(320)])
    }
}

struct InfoRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Text(icon).font(.body)
            VStack(alignment: .leading) {
                Text(title).font(.body).foregroundColor(Theme.textPrimary)
                Text(subtitle).font(.caption).foregroundColor(Theme.textTertiary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(Theme.textTertiary)
        }
        .padding(Spacing.lg)
    }
}

// MARK: - UIImage 压缩扩展
extension UIImage {
    func resized(maxSide: CGFloat) -> UIImage {
        let scale = min(maxSide / size.width, maxSide / size.height, 1.0)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

/// 语音提示气泡（录音/功能提示浮层）
struct VoiceHintBubble: View {
    let text: String
    let isRecording: Bool

    private var display: String {
        if !text.isEmpty { return text }
        return isRecording ? "正在录音..." : "按住说话"
    }
    var body: some View {
        Text(display)
            .font(.caption)
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.black.opacity(0.7)))
    }
}

/// 输入区组件（微信布局）：语音切换 + 输入框/按住说话 + 表情 + 加号
struct ChatInputBar: View {
    @Binding var input: String
    let isAI: Bool
    let peerName: String
    let voiceMode: Bool
    let isRecording: Bool
    let isVoiceSlidingUp: Bool
    let recordingSeconds: Double
    let onToggleVoiceMode: () -> Void
    let onEmoji: () -> Void
    let onPlus: () -> Void
    let onSend: () -> Void
    let onStartRecord: () -> Void
    let onEndRecord: () -> Void
    let onCancelRecord: () -> Void
    let onSlideUpChange: (Bool) -> Void
    let onDragChange: (CGFloat) -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // 语音/键盘切换
            Button(action: onToggleVoiceMode) {
                Image(systemName: voiceMode ? "keyboard" : "waveform")
                    .font(.system(size: 20))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 36, height: 40)
            }

            if voiceMode {
                // 按住说话（微信样式：长按激活录音 + 拖动上滑取消/转文字）
                Text(isRecording ? (isVoiceSlidingUp ? "松开 取消" : "松开 发送") : "按住 说话")
                    .font(.body)
                    .foregroundColor(isRecording ? (isVoiceSlidingUp ? Theme.error : Theme.primary) : Theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(isRecording ? (isVoiceSlidingUp ? Theme.error.opacity(0.15) : Theme.primary.opacity(0.15)) : Theme.surfaceHigh)
                    )
                    .gesture(
                        LongPressGesture(minimumDuration: 0.15)
                            .sequenced(before: DragGesture(minimumDistance: 0))
                            .onChanged { value in
                                switch value {
                                case .first(true):
                                    // 长按激活 → 开始录音
                                    onStartRecord()
                                case .second(true, let drag?):
                                    onSlideUpChange(drag.translation.height < -60)
                                    onDragChange(drag.translation.height)
                                default:
                                    break
                                }
                            }
                            .onEnded { value in
                                onSlideUpChange(false)
                                onDragChange(0)
                                switch value {
                                case .second(true, let drag?):
                                    if drag.translation.height < -140 {
                                        // 转文字（即将上线）
                                        onCancelRecord()
                                    } else if drag.translation.height < -60 {
                                        onCancelRecord()
                                    } else {
                                        onEndRecord()
                                    }
                                default:
                                    // 长按后原地松开 → 发送
                                    onEndRecord()
                                }
                            }
                    )
            } else {
                TextField(isAI ? "向 AI 提问..." : "加密消息给 \(peerName)...", text: $input)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .background(RoundedRectangle(cornerRadius: 20).fill(Theme.surfaceHigh))
                    .submitLabel(.send)
                    .onSubmit(onSend)
            }

            // 表情按钮
            Button(action: onEmoji) {
                Image(systemName: "face.smiling")
                    .font(.system(size: 20))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 36, height: 40)
            }

            // 加号
            Button(action: onPlus) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 36, height: 40)
            }

            // 发送（有文字时）
            if !input.isEmpty {
                Button(action: onSend) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Theme.primary))
                }
            }
        }
    }
}

/// 附件面板（微信风格：2行×4列每页8个，多页左右滑动）
struct AttachmentPanel: View {
    let onAlbum: () -> Void
    let onCamera: () -> Void
    let onFile: () -> Void
    let onVoiceCall: () -> Void
    let onLocation: () -> Void
    let onRedPacket: () -> Void
    let onGift: () -> Void
    let onTransfer: () -> Void
    let onVoiceInput: () -> Void
    let onNamecard: () -> Void

    @State private var page = 0

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    // 第 1 页：8 个常用
    private var page1: [AttachmentItemData] {
        [
            AttachmentItemData(icon: "photo.on.rectangle.angled", color: Color(hex: 0x34C759), label: "照片", action: onAlbum),
            AttachmentItemData(icon: "camera.fill", color: Color(hex: 0x007AFF), label: "拍摄", action: onCamera),
            AttachmentItemData(icon: "folder.fill", color: Color(hex: 0xFF9500), label: "文件", action: onFile),
            AttachmentItemData(icon: "phone.fill", color: Color(hex: 0x34C759), label: "语音通话", action: onVoiceCall),
            AttachmentItemData(icon: "location.fill", color: Color(hex: 0xFF3B30), label: "位置", action: onLocation),
            AttachmentItemData(icon: "gift.fill", color: Color(hex: 0xFF3B30), label: "红包", action: onRedPacket),
            AttachmentItemData(icon: "gift.circle.fill", color: Color(hex: 0xFF9500), label: "礼物", action: onGift),
            AttachmentItemData(icon: "arrow.left.arrow.right", color: Color(hex: 0x007AFF), label: "转账", action: onTransfer),
        ]
    }

    // 第 2 页：其余
    private var page2: [AttachmentItemData] {
        [
            AttachmentItemData(icon: "mic.circle.fill", color: Color(hex: 0xAF52DE), label: "语音输入", action: onVoiceInput),
            AttachmentItemData(icon: "person.crop.square.fill", color: Color(hex: 0x007AFF), label: "名片", action: onNamecard),
        ]
    }

    var body: some View {
        VStack(spacing: 8) {
            TabView(selection: $page) {
                gridPage(page1).tag(0)
                gridPage(page2).tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: page2.isEmpty ? .never : .always))
            .frame(height: 150)

            // 页码指示点
            if !page2.isEmpty {
                HStack(spacing: 6) {
                    ForEach(0..<2, id: \.self) { i in
                        Circle()
                            .fill(i == page ? Theme.primary : Theme.surfaceAlt)
                            .frame(width: 6, height: 6)
                    }
                }
            }
        }
        .padding(.vertical, Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .padding(.horizontal, Spacing.sm)
        .padding(.bottom, Spacing.sm)
    }

    private func gridPage(_ items: [AttachmentItemData]) -> some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(items) { item in
                AttachmentItem(icon: item.icon, color: item.color, label: item.label, action: item.action)
            }
        }
        .padding(.horizontal, Spacing.lg)
    }
}

/// 附件项数据
struct AttachmentItemData: Identifiable {
    let id = UUID()
    let icon: String
    let color: Color
    let label: String
    let action: () -> Void
}

/// 附件网格单项
struct AttachmentItem: View {
    let icon: String
    let color: Color
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(color.opacity(0.15))
                        .frame(width: 56, height: 56)
                    Image(systemName: icon)
                        .font(.system(size: 24))
                        .foregroundColor(color)
                }
                Text(label)
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: 72)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.plain)
    }
}

/// 微信式录音浮层：绿色气泡+波形 / 松手提示 / 取消·转文字
struct RecordingOverlay: View {
    let seconds: Double
    let dragOffset: CGFloat
    let onCancel: () -> Void
    let onToText: () -> Void
    let onSend: () -> Void

    private var mode: RecordingMode {
        if dragOffset < -140 { return .toText }
        if dragOffset < -60 { return .cancel }
        return .send
    }

    enum RecordingMode {
        case send, cancel, toText
    }

    var body: some View {
        ZStack {
            // 半透明黑底
            Color.black.opacity(0.45).ignoresSafeArea()

            VStack(spacing: 20) {
                // 绿色气泡 + 波形
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(mode == .cancel ? Color.red : Color(hex: 0x07C160))
                        .frame(width: 220, height: 150)

                    // 波形（录音动画）
                    WaveformBars(isActive: true, color: .white)
                        .frame(width: 180, height: 60)
                        .padding(.bottom, 30)

                    Text(String(format: "%.0f\"", seconds))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.bottom, 10)
                }

                // 松手提示
                Text(mode == .cancel ? "松手 取消" : (mode == .toText ? "松手 转文字" : "松手 发语音"))
                    .font(.headline)
                    .foregroundColor(mode == .cancel ? .red : (mode == .toText ? Color(hex: 0x07C160) : .white))

                // 底部按钮：取消 / 滑到这里转文字
                HStack(spacing: 16) {
                    Button(action: onCancel) {
                        Text("取消")
                            .font(.body.weight(.medium))
                            .foregroundColor(.white)
                            .frame(width: 100, height: 44)
                            .background(Capsule().fill(Color.white.opacity(0.2)))
                    }

                    Button(action: onToText) {
                        Text("滑到这里\n转文字")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white)
                            .frame(width: 100, height: 44)
                            .background(Capsule().fill(mode == .toText ? Color(hex: 0x07C160) : Color.white.opacity(0.2)))
                    }
                }
            }
        }
    }
}

/// 录音波形（动态竖条）
struct WaveformBars: View {
    let isActive: Bool
    let color: Color

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<28, id: \.self) { i in
                    let phase = sin(time * 8 + Double(i) * 0.6)
                    let height = isActive ? (8 + abs(phase) * 22) : 6
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: 3, height: height)
                }
            }
            .frame(height: 60)
        }
    }
}

/// 表情面板（常用 emoji 网格）
struct EmojiPanel: View {
    let onSelect: (String) -> Void

    private let emojis: [String] = [
        "😀","😄","😁","😂","🤣","😊","😍","🥰","😘","😎","🤔","😴","👍","👎","👏","🙏",
        "🔥","💯","🎉","🎊","❤️","💔","💖","⭐","✅","❌","❓","❗","💪","🤝","👋","✌️",
        "🎮","🎧","🎬","📷","🎁","💰","📱","💻","☕","🍺","🍜","🍎","🚀","🌙","☀️","🌈"
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 8) {
                ForEach(emojis, id: \.self) { emoji in
                    Button {
                        onSelect(emoji)
                    } label: {
                        Text(emoji)
                            .font(.system(size: 28))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Spacing.md)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .padding(.horizontal, Spacing.sm)
        .padding(.bottom, Spacing.sm)
    }
}

/// 消息列表（ScrollView + 气泡 + contextMenu + 自动滚动）
struct MessageListView: View {
    let messages: [ChatMessage]
    let isAI: Bool
    let isStreaming: Bool
    let streamContent: String
    let streamReasoning: String
    let deviceName: String
    let playingVoiceId: String?
    let onPlayVoice: (ChatMessage) -> Void
    let onStopVoice: () -> Void
    let onCopy: (ChatMessage) -> Void
    let onRegenerate: (ChatMessage) -> Void
    let onDelete: (ChatMessage) -> Void
    let onCountChange: (ScrollViewProxy) -> Void
    let onStreamChange: (ScrollViewProxy) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    Text(isAI ? "🤖 与 AI 助手对话 · 经云端中继" : "🔐 端到端加密 · 消息仅双方可见")
                        .font(.caption2)
                        .foregroundColor(Theme.textTertiary)
                        .padding(.vertical, 4)

                    ForEach(messages) { msg in
                        MessageBubble(
                            msg: msg,
                            isMine: msg.role == "user",
                            isAI: msg.role == "ai",
                            deviceName: deviceName,
                            playingVoiceId: playingVoiceId,
                            onPlayVoice: onPlayVoice,
                            onStopVoice: onStopVoice
                        )
                        .id(msg.id)
                        .contextMenu {
                            Button {
                                onCopy(msg)
                            } label: {
                                Label("复制", systemImage: "doc.on.doc")
                            }

                            if isAI && msg.role == "ai" {
                                Button {
                                    onRegenerate(msg)
                                } label: {
                                    Label("重新生成", systemImage: "arrow.clockwise")
                                }
                                .disabled(isStreaming)
                            }

                            Button(role: .destructive) {
                                onDelete(msg)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                    if isStreaming {
                        MessageBubble(
                            msg: ChatMessage(role: "ai", text: streamContent, reasoning: streamReasoning),
                            isMine: false, isAI: true, deviceName: deviceName,
                            playingVoiceId: nil,
                            onPlayVoice: { _ in },
                            onStopVoice: {}
                        )
                        .id("streaming")
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
            }
            .onChange(of: messages.count) { _ in
                onCountChange(proxy)
            }
            .onChange(of: streamContent) { _ in
                onStreamChange(proxy)
            }
        }
    }
}

/// AI 模型切换行
struct ModelSwitcherRow: View {
    let icon: String
    let name: String
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Button(action: onTap) {
                HStack(spacing: 4) {
                    Text("\(icon) \(name) ▾")
                        .font(.caption)
                        .foregroundColor(Theme.primary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Theme.primary.opacity(0.15))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.primary.opacity(0.35), lineWidth: 1))
                )
            }
            Text("切换模型")
                .font(.caption2)
                .foregroundColor(Theme.textTertiary)
            Spacer()
        }
    }
}
