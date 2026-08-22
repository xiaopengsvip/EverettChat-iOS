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

    private var isAI: Bool { appState.chatMode == "ai" }
    private let apiClient = ChatApiClient()

    var body: some View {
        VStack(spacing: 0) {
            // 顶栏：返回 + 标题 + 副标题（模型名/ID）+ ℹ️
            HStack(spacing: Spacing.sm) {
                Button {
                    appState.showChat = false
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(Theme.textPrimary)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(isAI ? "AI 助手" : appState.chatPeerName)
                        .font(.headline)
                        .foregroundColor(Theme.textPrimary)
                    Text(isAI ? currentModelName : "ID: \(String(appState.chatPeerId.prefix(8)))")
                        .font(.caption2)
                        .foregroundColor(Theme.textTertiary)
                }
                Spacer()
                Button {
                    showInfoSheet = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 18))
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)

            Divider().overlay(Theme.surfaceHigh)

            // 消息列表
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        // 顶部提示
                        Text(isAI ? "🤖 与 AI 助手对话 · 经云端中继" : "🔐 端到端加密 · 消息仅双方可见")
                            .font(.caption2)
                            .foregroundColor(Theme.textTertiary)
                            .padding(.vertical, 4)

                        ForEach(messages) { msg in
                            MessageBubble(
                                msg: msg,
                                isMine: msg.role == "user",
                                isAI: msg.role == "ai",
                                deviceName: appState.deviceName,
                                playingVoiceId: playingVoiceId,
                                onPlayVoice: playVoice,
                                onStopVoice: stopVoice
                            )
                            .id(msg.id)
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.string = msg.text
                                } label: {
                                    Label("复制", systemImage: "doc.on.doc")
                                }

                                if isAI && msg.role == "ai" {
                                    Button {
                                        regenerateAIResponse(for: msg)
                                    } label: {
                                        Label("重新生成", systemImage: "arrow.clockwise")
                                    }
                                    .disabled(isStreaming)
                                }

                                Button(role: .destructive) {
                                    deleteMessage(msg)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                        if isStreaming {
                            MessageBubble(
                                msg: ChatMessage(role: "ai", text: streamContent, reasoning: streamReasoning),
                                isMine: false, isAI: true, deviceName: appState.deviceName,
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
                    withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
                }
                .onChange(of: streamContent) { _ in
                    withAnimation { proxy.scrollTo("streaming", anchor: .bottom) }
                }
            }

            // 输入区
            VStack(spacing: 0) {
                if isAI {
                    HStack(spacing: Spacing.sm) {
                        Button {
                            showModelSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Text("\(currentModelIcon) \(currentModelName) ▾")
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
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, 4)
                }

                HStack(spacing: Spacing.sm) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Image(systemName: "photo")
                            .font(.system(size: 18))
                            .foregroundColor(Theme.textSecondary)
                            .frame(width: 40, height: 40)
                    }
                    .onChange(of: pickerItem) { item in
                        guard let item else { return }
                        Task {
                            if let data = try? await item.loadTransferable(type: Data.self),
                               let img = UIImage(data: data) {
                                let resized = img.resized(maxSide: 1280)
                                let jpeg = resized.jpegData(compressionQuality: 0.8) ?? data
                                let b64 = jpeg.base64EncodedString()
                                if isAI {
                                    // AI 发送图片
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
                    // 语音按钮（点击开始/停止录音）
                    Button {
                        if isRecording {
                            stopRecordingAndSend()
                        } else {
                            startRecording()
                        }
                    } label: {
                        Image(systemName: isRecording ? "stop.circle.fill" : "mic")
                            .font(.system(size: 18))
                            .foregroundColor(isRecording ? Theme.error : Theme.textSecondary)
                            .frame(width: 40, height: 40)
                    }
                    if isRecording {
                        Text(String(format: "%.0f\"", recordingSeconds))
                            .font(.caption)
                            .foregroundColor(Theme.error)
                            .monospacedDigit()
                    }
                    TextField(isAI ? "向 AI 提问..." : "加密消息给 \(appState.chatPeerName)...", text: $input)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 20).fill(Theme.surfaceHigh))
                        .submitLabel(.send)
                        .onSubmit { send() }
                    Button {
                        send()
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(input.isEmpty ? Theme.surfaceAlt : Theme.primary))
                    }
                    .disabled(input.isEmpty)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
            }
            // 原生 Liquid Glass 输入区
            .background(.thinMaterial)
        }
        .background(Theme.bg)
        .sheet(isPresented: $showModelSheet) { ModelPickerSheet(selected: $selectedModel) }
        .sheet(isPresented: $showInfoSheet) { ChatInfoSheet(isAI: isAI) }
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
        AVAudioApplication.requestRecordPermission { granted in
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
        guard let data = try? Data(contentsOf: url), duration > 0.5 else { return }
        let b64 = data.base64EncodedString()
        let msg = ChatMessage(role: "user", text: "", voiceBase64: b64, voiceDurationMs: duration * 1000, senderName: DeviceIdentity.shared.deviceName)
        messages.append(msg)
        appState.transport.sendVoice(base64: b64, target: appState.chatPeerId, durationMs: duration * 1000, messageId: msg.id)
        try? FileManager.default.removeItem(at: url)
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
                            Text(msg.text)
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
                            Text(msg.text)
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
