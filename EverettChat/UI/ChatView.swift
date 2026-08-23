import SwiftUI
import UIKit
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers

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
    @State private var showCameraModePicker = false
    @State private var cameraMode: CameraPicker.CameraMode = .photo
    @State private var cameraImage: UIImage?
    // 语音按住录音：上滑取消
    @State private var isVoiceSlidingUp = false
    @State private var voiceDragOffset: CGFloat = 0
    @State private var voiceHintText = ""
    // 语音/键盘切换模式
    @State private var voiceMode = false
    // 表情面板
    @State private var showEmojiPanel = false
    // 转发目标消息
    @State private var forwardTarget: ChatMessage? = nil
    // 图片全屏预览 / 视频播放
    @State private var fullscreenImage: UIImage? = nil
    @State private var videoToPlay: String? = nil
    // 待发送图片（压缩/原图选择）
    @State private var pendingImageData: Data? = nil
    @State private var showImageQualityPicker = false

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
                avatarState: isAI ? currentAvatarState : .idle,
                onPlayVoice: playVoice,
                onStopVoice: stopVoice,
                onCopy: { msg in UIPasteboard.general.string = msg.text },
                onForward: { msg in forwardTarget = msg },
                onRegenerate: regenerateAIResponse,
                onDelete: deleteMessage,
                onResend: resend,
                onImageTap: { img in fullscreenImage = img },
                onVideoTap: { b64 in videoToPlay = b64 },
                onOpenURL: { url in webURL = url },
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
                        onCamera: { showCameraModePicker = true },
                        onFile: { showFilePicker = true },
                        onVoiceCall: {
                            showPlusPanel = false
                            CallManager.shared.startCall(peerId: appState.chatPeerId, peerName: appState.chatPeerName, type: .audio)
                        },
                        onVideoCall: {
                            showPlusPanel = false
                            CallManager.shared.startCall(peerId: appState.chatPeerId, peerName: appState.chatPeerName, type: .video)
                        },
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
                                appState.conn.sendText(card, target: appState.chatPeerId, messageId: msg.id)
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
                    onTextFieldTap: {
                        withAnimation { showPlusPanel = false; showEmojiPanel = false }
                    },
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
            CameraPicker(mode: cameraMode,
                         onCapture: { image in sendCameraImage(image) },
                         onVideo: { url in sendCameraVideo(url) })
        }
        // 相机模式选择（拍照/录像）
        .confirmationDialog("拍摄", isPresented: $showCameraModePicker, titleVisibility: .visible) {
            Button {
                                cameraMode = .photo
                                showCamera = true
                            } label: { Label("拍照", systemImage: "camera") }
                            Button {
                                cameraMode = .video
                                showCamera = true
                            } label: { Label("录像", systemImage: "video") }
            Button("取消", role: .cancel) {}
        }
        // 相册（图片 + 视频）
        .photosPicker(isPresented: $showPhotoPicker, selection: $pickerItem, matching: .any(of: [.images, .videos]))
        .onChange(of: pickerItem) { item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    // 判断是图片还是视频
                    if let type = item.supportedContentTypes.first {
                        if type.conforms(to: .movie) || type.conforms(to: .video) {
                            sendVideoData(data)
                        } else if type.conforms(to: .image) {
                            // 图片：弹压缩/原图选择
                            pendingImageData = data
                            showImageQualityPicker = true
                        } else {
                            sendFile(name: "媒体_\(Date().timeIntervalSince1970)", data: data)
                        }
                    } else {
                        pendingImageData = data
                        showImageQualityPicker = true
                    }
                }
                pickerItem = nil
            }
        }
        // 图片质量选择（压缩/原图）
        .confirmationDialog("发送图片", isPresented: $showImageQualityPicker, titleVisibility: .visible) {
            Button("压缩发送（推荐，更快）") {
                if let data = pendingImageData { sendImageData(data, original: false) }
                pendingImageData = nil
            }
            Button("原图发送（不压缩）") {
                if let data = pendingImageData { sendImageData(data, original: true) }
                pendingImageData = nil
            }
            Button("取消", role: .cancel) { pendingImageData = nil }
        }
        // 消息内链接 → 应用内浏览器（不跳出 Safari）
        .environment(\.openURL, OpenURLAction { url in
            webURL = url
            return .handled
        })
        .fullScreenCover(item: $webURL) { url in
            SafariView(url: url)
        }
        // 转发：选择目标会话
        .sheet(item: $forwardTarget) { msg in
            ForwardSheet(target: msg, appState: appState) { targetId, targetName in
                appState.conn.sendText(msg.text, target: targetId, messageId: UUID().uuidString)
                forwardTarget = nil
                voiceHintText = "已转发给 \(targetName)"
                showVoiceHint = true
            }
        }
        // 图片全屏预览
        .fullScreenCover(item: $fullscreenImage) { img in
            FullscreenImageView(image: img)
        }
        // 视频全屏播放（应用内 AVPlayer）
        .fullScreenCover(item: $videoToPlay) { b64 in
            FullscreenVideoView(videoBase64: b64)
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
    /// AI 头像状态：流式回复时说话，否则待机
    private var currentAvatarState: AvatarState {
        isStreaming ? .speaking : (isAI ? .idle : .idle)
    }
    private var currentModelName: String { currentModel.name }
    private var currentModelIcon: String { currentModel.vision ? "eye.fill" : "sparkles" }
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
            if appState.conn.isConnected {
                appState.conn.sendText(text, target: appState.chatPeerId, messageId: userMsg.id)
            } else {
                // 未连接 → 标记发送失败，显示重发按钮
                if let idx = messages.firstIndex(where: { $0.id == userMsg.id }) {
                    messages[idx].status = "failed"
                }
            }
        }
    }

    /// 重发失败消息
    private func resend(_ msg: ChatMessage) {
        if let idx = messages.firstIndex(where: { $0.id == msg.id }) {
            messages[idx].status = "sent"
        }
        appState.conn.sendText(msg.text, target: appState.chatPeerId, messageId: msg.id)
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
        appState.conn.sendVoice(base64: b64, target: appState.chatPeerId, durationMs: duration * 1000, messageId: msg.id)
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

    /// 发送图片数据（默认压缩 1280px；original=true 发原图）
    private func sendImageData(_ data: Data, original: Bool = false) {
        guard let img = UIImage(data: data) else { return }
        var b64: String
        if original {
            // 原图：不压缩
            b64 = data.base64EncodedString()
        } else {
            let resized = img.resized(maxSide: 1280)
            b64 = (resized.jpegData(compressionQuality: 0.8) ?? data).base64EncodedString()
        }
        if isAI {
            let msg = ChatMessage(role: "user", text: "", imageBase64: b64, hasOriginal: original)
            messages.append(msg)
            sendAI(text: "", imageBase64: b64)
        } else {
            let msg = ChatMessage(role: "user", text: "", imageBase64: b64, hasOriginal: original, senderName: DeviceIdentity.shared.deviceName)
            messages.append(msg)
            appState.conn.sendImage(base64: b64, target: appState.chatPeerId, messageId: msg.id)
        }
    }

    /// 发送视频数据（压缩转码 mp4）
    private func sendVideoData(_ data: Data) {
        // 视频时长
        var duration: Double = 0
        if let asset = try? AVURLAsset(url: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tmp_video_\(Date().timeIntervalSince1970).mp4")) {
            duration = CMTimeGetSeconds(asset.duration)
        }
        // 直接保存临时文件取时长
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("evo_video_\(Date().timeIntervalSince1970).mp4")
        try? data.write(to: tmpURL)
        let asset = AVURLAsset(url: tmpURL)
        duration = CMTimeGetSeconds(asset.duration)
        let b64 = data.base64EncodedString()
        if isAI {
            let msg = ChatMessage(role: "user", text: "", videoBase64: b64, videoDurationMs: duration * 1000)
            messages.append(msg)
            sendAI(text: "[视频 \(Int(duration))s]", imageBase64: "")
        } else {
            let msg = ChatMessage(role: "user", text: "", videoBase64: b64, videoDurationMs: duration * 1000, senderName: DeviceIdentity.shared.deviceName)
            messages.append(msg)
            appState.conn.sendVideo(base64: b64, target: appState.chatPeerId, durationMs: duration * 1000, messageId: msg.id)
        }
        try? FileManager.default.removeItem(at: tmpURL)
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
            appState.conn.sendText("[file]\(name)::\(b64)", target: appState.chatPeerId, messageId: msg.id)
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
            appState.conn.sendImage(base64: b64, target: appState.chatPeerId, messageId: msg.id)
        }
    }

    /// 发送拍摄的视频
    private func sendCameraVideo(_ url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        sendVideoData(data)
        try? FileManager.default.removeItem(at: url)
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
    @State private var isReasoningExpanded = false
    var avatarState: AvatarState = .idle
    var autoExpandReasoning: Bool = false
    var onResend: (() -> Void)? = nil
    var onImageTap: ((UIImage) -> Void)? = nil
    var onVideoTap: ((String) -> Void)? = nil
    var onCopy: (() -> Void)? = nil
    var onForward: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onOpenURL: ((URL) -> Void)? = nil

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

    /// 消息时间格式化（今天只显示时间，其他显示日期+时间）
    static func timeString(_ date: Date) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        if cal.isDateInToday(date) {
            f.dateFormat = "HH:mm"
        } else if cal.isDate(date, equalTo: Date(), toGranularity: .year) {
            f.dateFormat = "M月d日 HH:mm"
        } else {
            f.dateFormat = "yyyy/M/d HH:mm"
        }
        return f.string(from: date)
    }

    init(msg: ChatMessage, isMine: Bool, isAI: Bool, deviceName: String,
         playingVoiceId: String?, onPlayVoice: @escaping (ChatMessage) -> Void,
         onStopVoice: @escaping () -> Void, avatarState: AvatarState = .idle,
         autoExpandReasoning: Bool = false, onResend: (() -> Void)? = nil,
         onImageTap: ((UIImage) -> Void)? = nil, onVideoTap: ((String) -> Void)? = nil,
         onCopy: (() -> Void)? = nil, onForward: (() -> Void)? = nil, onDelete: (() -> Void)? = nil,
         onOpenURL: ((URL) -> Void)? = nil) {
        self.msg = msg
        self.isMine = isMine
        self.isAI = isAI
        self.deviceName = deviceName
        self.playingVoiceId = playingVoiceId
        self.onPlayVoice = onPlayVoice
        self.onStopVoice = onStopVoice
        self.avatarState = avatarState
        self.autoExpandReasoning = autoExpandReasoning
        self.onResend = onResend
        self.onImageTap = onImageTap
        self.onVideoTap = onVideoTap
        self.onCopy = onCopy
        self.onForward = onForward
        self.onDelete = onDelete
        self.onOpenURL = onOpenURL
        // 流式中思考默认展开
        _isReasoningExpanded = State(initialValue: autoExpandReasoning)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // 左头像列（对方）
            if !isMine {
                // AI：Evo Living Avatar（按状态动画）；对端：好友头像或占位
                if isAI {
                    LivingAvatarBubble(state: avatarState, size: 36)
                } else {
                    if let peerAvatar = ProfileStore.shared.friendAvatar(msg.senderId.isEmpty ? msg.senderName : msg.senderId) {
                        Image(uiImage: peerAvatar)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 36, height: 36)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Theme.outline, lineWidth: 1))
                    } else {
                        Circle()
                            .fill(Theme.surfaceAlt)
                            .frame(width: 36, height: 36)
                            .overlay(Image(systemName: "person.fill").font(.system(size: 12)).foregroundColor(Theme.textSecondary))
                    }
                }
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
                        // 发送失败 → 重发按钮
                        if msg.status == "failed", let onResend {
                            Button(action: onResend) {
                                Image(systemName: "arrow.clockwise.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(Theme.error)
                            }
                            .buttonStyle(.plain)
                        }
                        // 操作菜单（复制/转发/删除——可见按钮）
                        if let onCopy, let onForward, let onDelete {
                            Menu {
                                Button(action: onCopy) {
                                    Label("复制", systemImage: "doc.on.doc")
                                }
                                Button(action: onForward) {
                                    Label("转发", systemImage: "arrowshape.turn.up.right")
                                }
                                Button(role: .destructive, action: onDelete) {
                                    Label("删除", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(Theme.textTertiary)
                                    .padding(4)
                            }
                        }
                    }
                } else {
                    HStack(spacing: 4) {
                        Text(isAI ? "AI 助手" : msg.senderName)
                            .font(.caption2)
                            .foregroundColor(isAI ? Theme.info : Theme.textTertiary)
                        // 操作菜单（复制/转发/删除——可见按钮）
                        if let onCopy, let onForward, let onDelete {
                            Menu {
                                Button(action: onCopy) {
                                    Label("复制", systemImage: "doc.on.doc")
                                }
                                Button(action: onForward) {
                                    Label("转发", systemImage: "arrowshape.turn.up.right")
                                }
                                Button(role: .destructive, action: onDelete) {
                                    Label("删除", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(Theme.textTertiary)
                                    .padding(4)
                            }
                        }
                    }
                }

                // 气泡内容
                if isAI {
                    VStack(alignment: .leading, spacing: 4) {
                        if !msg.reasoning.isEmpty {
                            // 思考过程：可展开/折叠
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    isReasoningExpanded.toggle()
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "brain.head.profile")
                                        .font(.system(size: 11))
                                        .foregroundColor(Theme.textTertiary)
                                    Text(isReasoningExpanded ? "思考过程 ▾" : "思考过程 ▸")
                                        .font(.caption2)
                                        .foregroundColor(Theme.textTertiary)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if isReasoningExpanded {
                                Text(msg.reasoning)
                                    .font(.caption)
                                    .foregroundColor(Theme.textTertiary)
                                    .textSelection(.enabled)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: Radius.small)
                                            .fill(Theme.surfaceAlt.opacity(0.6))
                                    )
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        if !msg.imageBase64.isEmpty, let data = Data(base64Encoded: msg.imageBase64), let ui = UIImage(data: data) {
                            // 图片：点击全屏查看
                            Button {
                                onImageTap?(ui)
                            } label: {
                                Image(uiImage: ui)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: 240)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(alignment: .bottomTrailing) {
                                        if msg.hasOriginal {
                                            Text("原图")
                                                .font(.system(size: 8, weight: .semibold))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(Capsule().fill(Color.black.opacity(0.6)))
                                                .padding(4)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                        // 视频消息：缩略图 + 播放按钮 + 时长（点击全屏播放）
                        if !msg.videoBase64.isEmpty {
                            VideoBubbleCard(
                                videoBase64: msg.videoBase64,
                                durationMs: msg.videoDurationMs,
                                onPlay: { onVideoTap?(msg.videoBase64) }
                            )
                        }
                        if !msg.text.isEmpty {
                            Text(renderRichText(msg.text))
                                .font(.body)
                                .foregroundColor(Theme.textPrimary)
                                .textSelection(.enabled)
                        }
                        // 时间显示
                        Text(Self.timeString(msg.createdAt))
                            .font(.system(size: 9))
                            .foregroundColor(Theme.textTertiary)
                            .padding(.top, 1)
                        // URL 链接卡片（标题 + 封面预览）
                        if !msg.text.isEmpty, msg.imageBase64.isEmpty, msg.videoBase64.isEmpty, msg.voiceBase64.isEmpty,
                           let urlString = extractFirstURL(from: msg.text) {
                            URLCardView(urlString: urlString) { url in
                                onOpenURL?(url)
                            }
                        }

                        // 工具卡片（时间/日历/天气/定位/代码运行）——所有消息都支持
                        if !msg.text.isEmpty {
                            let cards = extractToolCards(from: msg.text)
                            if !cards.isEmpty {
                                ForEach(Array(cards.enumerated()), id: \.offset) { _, item in
                                    AIToolCardView(card: item.card, code: item.code)
                                }
                            }
                        }
                        // URL 链接卡片（标题 + 封面预览）
                        if !msg.text.isEmpty, msg.imageBase64.isEmpty, msg.videoBase64.isEmpty, msg.voiceBase64.isEmpty,
                           let urlString = extractFirstURL(from: msg.text) {
                            URLCardView(urlString: urlString) { url in
                                onOpenURL?(url)
                            }
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
                            // 图片：点击全屏查看
                            Button {
                                onImageTap?(ui)
                            } label: {
                                Image(uiImage: ui)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: 240)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(alignment: .bottomTrailing) {
                                        if msg.hasOriginal {
                                            Text("原图")
                                                .font(.system(size: 8, weight: .semibold))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(Capsule().fill(Color.black.opacity(0.6)))
                                                .padding(4)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                        // 视频消息：缩略图 + 播放按钮 + 时长（点击全屏播放）
                        if !msg.videoBase64.isEmpty {
                            VideoBubbleCard(
                                videoBase64: msg.videoBase64,
                                durationMs: msg.videoDurationMs,
                                onPlay: { onVideoTap?(msg.videoBase64) }
                            )
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
                    .overlay(Image(systemName: "person.fill").font(.system(size: 12)).foregroundColor(Theme.textSecondary))
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
                        Image(systemName: m.vision ? "eye.fill" : "sparkles")
                            .font(.system(size: 20))
                            .foregroundColor(m.vision ? Theme.info : Theme.primary)
                            .frame(width: 28)
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
                    .overlay(Image(systemName: isAI ? "sparkles" : "person.fill").font(.system(size: 24)).foregroundColor(Theme.primary))
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
                InfoRow(icon: "brain.head.profile", title: "当前模型", subtitle: "DeepSeek V4")
                InfoRow(icon: "antenna.radiowaves.left.and.right", title: "加密说明", subtitle: "AI 对话经云端中继代理，非端到端加密")
                Button {
                    appState.aiMessages.removeAll()
                    dismiss()
                } label: {
                    InfoRow(icon: "trash", title: "清除对话", subtitle: "清空当前 AI 会话历史")
                }
            } else {
                InfoRow(icon: "link.icloud", title: "连接状态", subtitle: "中继连接")
                InfoRow(icon: "lock.shield", title: "加密说明", subtitle: "端到端加密 · 消息仅双方可见")
            }
            Spacer()
        }
        .background(Theme.surface)
        .presentationDetents([.height(320)])
    }
}

struct InfoRow: View {
    let icon: String  // SF Symbol
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundColor(Theme.primary)
                .frame(width: 28)
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
    let onTextFieldTap: () -> Void
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
                    .overlay(alignment: isRecording ? .trailing : .leading) {
                        if isRecording {
                            Text(String(format: " %.1f\"", recordingSeconds))
                                .font(.caption.monospacedDigit())
                                .foregroundColor(isVoiceSlidingUp ? Theme.error : Theme.primary)
                                .padding(.trailing, 10)
                                .transition(.opacity)
                        }
                    }
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
                    // 点击输入框 → 收回附件/表情面板
                    .simultaneousGesture(TapGesture().onEnded { onTextFieldTap() })
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
    let onVideoCall: () -> Void
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
            AttachmentItemData(icon: "video.fill", color: Color(hex: 0xAF52DE), label: "视频通话", action: onVideoCall),
            AttachmentItemData(icon: "person.crop.square.fill", color: Color(hex: 0x007AFF), label: "名片", action: onNamecard),
        ]
    }

    var body: some View {
        VStack(spacing: 8) {
            TabView(selection: $page) {
                gridPage(page1).tag(0)
                gridPage(page2).tag(1)
            }
            // 页面指示器用自定义点，TabView 自身不占额外高度
            .tabViewStyle(.page(indexDisplayMode: .never))
            // 两行格子：56 图标 + 8 间距 + 18 文字 = 82/行 ×2 + 14 行距 = 178pt，给足 190
            .frame(height: 190)

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
        LazyVGrid(columns: columns, spacing: 20) {
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
    var avatarState: AvatarState = .idle
    let onPlayVoice: (ChatMessage) -> Void
    let onStopVoice: () -> Void
    let onCopy: (ChatMessage) -> Void
    let onForward: (ChatMessage) -> Void
    let onRegenerate: (ChatMessage) -> Void
    let onDelete: (ChatMessage) -> Void
    let onResend: ((ChatMessage) -> Void)?
    let onImageTap: ((UIImage) -> Void)?
    let onVideoTap: ((String) -> Void)?
    let onOpenURL: ((URL) -> Void)?
    let onCountChange: (ScrollViewProxy) -> Void
    let onStreamChange: (ScrollViewProxy) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: isAI ? "sparkles" : "lock.shield")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.textTertiary)
                        Text(isAI ? "与 AI 助手对话 · 经云端中继" : "端到端加密 · 消息仅双方可见")
                            .font(.caption2)
                            .foregroundColor(Theme.textTertiary)
                    }
                    .padding(.vertical, 4)

                    ForEach(messages) { msg in
                        MessageBubble(
                            msg: msg,
                            isMine: msg.role == "user",
                            isAI: msg.role == "ai",
                            deviceName: deviceName,
                            playingVoiceId: playingVoiceId,
                            onPlayVoice: onPlayVoice,
                            onStopVoice: onStopVoice,
                            avatarState: avatarState,
                            onResend: { onResend?(msg) },
                            onImageTap: onImageTap,
                            onVideoTap: onVideoTap,
                            onCopy: { onCopy(msg) },
                            onForward: { onForward(msg) },
                            onDelete: { onDelete(msg) },
                            onOpenURL: onOpenURL
                        )
                        .id(msg.id)
                        .contextMenu {
                            Button {
                                onCopy(msg)
                            } label: {
                                Label("复制", systemImage: "doc.on.doc")
                            }

                            Button {
                                onForward(msg)
                            } label: {
                                Label("转发", systemImage: "arrowshape.turn.up.right")
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
                            onStopVoice: {},
                            avatarState: .thinking,
                            autoExpandReasoning: true
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

/// 转发选择器：选择目标会话
struct ForwardSheet: View {
    let target: ChatMessage
    let appState: AppState
    let onForward: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // AI 助手
                Button {
                    onForward("", "AI 助手")
                    dismiss()
                } label: {
                    Label("AI 助手", systemImage: "sparkles")
                        .foregroundColor(Theme.textPrimary)
                }

                // 最近对端会话
                let peers = appState.conversations.filter { $0.type == "peer" }
                ForEach(peers) { conv in
                    Button {
                        onForward(conv.id, conv.name)
                        dismiss()
                    } label: {
                        Label(conv.name, systemImage: "person.circle")
                            .foregroundColor(Theme.textPrimary)
                    }
                }
            }
            .navigationTitle("转发消息")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}
