import SwiftUI
import ActivityKit

/// 开发者设置页（调试模式 / 调试通道 / 远程日志 / 测试工具）
struct DeveloperView: View {
    @AppStorage("debug_mode") private var debugMode = false
    @State private var recentLogs: String = "点击「获取日志」查看最近日志"
    @State private var logVersion: String = ""
    @State private var isLoading = false

    // 启动封面测试
    @State private var splashDelay: Double = 5.0
    @State private var showSplashTest = false

    // 灵动岛测试
    @State private var isTestingIsland = false
    @State private var islandProgress: Double = 0
    @State private var islandTimer: Timer?
    @State private var islandError: String? = nil

    var body: some View {
        List {
            // 调试模式开关
            Section {
                Toggle(isOn: $debugMode) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("调试模式")
                            .font(.body)
                        Text(debugMode ? "已开启 · 消息列表显示「EVO 调试通道」" : "关闭 · 调试通道不可见")
                            .font(.caption)
                            .foregroundColor(Theme.textTertiary)
                    }
                }
            } header: {
                Text("调试模式")
            } footer: {
                Text("开启后，中继下发的远程诊断命令（__cmd__）会记录到消息列表的「EVO 调试通道」会话中，便于查看。调试完成建议关闭。")
            }

            // 远程日志
            Section {
                Button {
                    fetchLogs()
                } label: {
                    HStack {
                        Label("获取远程日志", systemImage: "doc.text.magnifyingglass")
                        Spacer()
                        if isLoading {
                            ProgressView()
                        }
                    }
                }
                Text(recentLogs)
                    .font(.caption2.monospaced())
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(20)
            } header: {
                Text("远程日志")
            }

            // 设备信息
            Section {
                LabeledContent("版本", value: logVersion.isEmpty ? "未知" : logVersion)
                LabeledContent("设备 ID", value: String(DeviceIdentity.shared.deviceId.prefix(12)))
            } header: {
                Text("设备信息")
            }

            // MARK: - 测试灵动岛
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    if !EvoActivityManager.shared.isSupported {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("实时活动未开启")
                                .font(.subheadline)
                                .foregroundColor(.orange)
                        }
                        Text("请前往 设置 → EVO → 实时活动 开启后重试")
                            .font(.caption)
                            .foregroundColor(Theme.textTertiary)
                        Button("打开设置") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.subheadline)
                    }

                    if let err = islandError {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text(err)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }

                    if isTestingIsland {
                        HStack(spacing: 12) {
                            ProgressView(value: islandProgress, total: 1.0)
                                .tint(Theme.primary)
                            Text("\(Int(islandProgress * 100))%")
                                .font(.caption.monospaced())
                                .foregroundColor(Theme.textSecondary)
                                .frame(width: 36)
                        }
                        Button(role: .destructive) {
                            stopIslandTest()
                        } label: {
                            Label("结束测试", systemImage: "xmark.circle.fill")
                                .font(.subheadline)
                        }
                    } else {
                        Button {
                            startIslandTest()
                        } label: {
                            Label("开始测试灵动岛", systemImage: "iphone.radiowaves.left.and.right")
                                .font(.subheadline)
                        }
                    }
                }
            } header: {
                Text("测试灵动岛")
            } footer: {
                Text("点击「开始测试」后，灵动岛会显示 AI 任务进度动画，模拟 step 1→5 后自动结束。可在锁屏或灵动岛查看效果。")
            }

            // MARK: - 测试启动封面
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("延迟显示")
                            .font(.subheadline)
                        Spacer()
                        HStack(spacing: 4) {
                            Button {
                                splashDelay = max(1, splashDelay - 1)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(Theme.primary)
                                    .font(.title3)
                            }
                            .buttonStyle(.plain)

                            Text("\(Int(splashDelay)) 秒")
                                .font(.body.monospaced())
                                .foregroundColor(Theme.textPrimary)
                                .frame(minWidth: 50)

                            Button {
                                splashDelay = min(15, splashDelay + 1)
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(Theme.primary)
                                    .font(.title3)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        showSplashTest = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + splashDelay) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                showSplashTest = false
                            }
                        }
                    } label: {
                        Label("模拟启动封面 (\(Int(splashDelay)) 秒)", systemImage: "photo.fill")
                            .font(.subheadline)
                    }
                }
            } header: {
                Text("测试启动封面")
            } footer: {
                Text("点击后全屏显示启动封面，\(Int(splashDelay)) 秒后自动淡出进入主界面，模拟真实 App 启动流程。可调延迟时间（1-15 秒）。")
            }
        }
        .navigationTitle("开发者")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(splashTestOverlay)
        .onDisappear {
            islandTimer?.invalidate()
            islandTimer = nil
        }
    }

    // MARK: - 启动封面测试 overlay（纯净版，模拟真实启动）
    @ViewBuilder
    private var splashTestOverlay: some View {
        if showSplashTest {
            ZStack {
                Color(red: 0.039, green: 0.039, blue: 0.071) // #0A0A12
                    .ignoresSafeArea()
                Image("launch_cover")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
            }
            .transition(.opacity)
            .ignoresSafeArea()
            .statusBarHidden(true)
        }
    }

    // MARK: - 灵动岛测试

    private func startIslandTest() {
        islandError = nil
        let ok = EvoActivityManager.shared.start(sessionId: "test-\(Date().timeIntervalSince1970)", peerName: "灵动岛测试")
        guard ok else {
            islandError = "Live Activity 启动失败，请检查设置中是否开启实时活动权限"
            return
        }

        isTestingIsland = true
        islandProgress = 0

        let steps = [
            (status: "思考中",  tool: "分析中",  progress: 0.2),
            (status: "搜索中",  tool: "搜索中",  progress: 0.4),
            (status: "执行中",  tool: "执行中",  progress: 0.6),
            (status: "验证中",  tool: "验证中",  progress: 0.8),
            (status: "完成",    tool: "已完成",  progress: 1.0),
        ]

        var stepIndex = 0
        islandTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { timer in
            guard stepIndex < steps.count else {
                timer.invalidate()
                EvoActivityManager.shared.end(status: "测试完成", progress: 1.0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isTestingIsland = false
                    islandProgress = 0
                }
                return
            }
            let s = steps[stepIndex]
            islandProgress = s.progress
            EvoActivityManager.shared.update(status: s.status, stepText: "Step \(stepIndex + 1) / \(steps.count)", progress: s.progress, toolName: s.tool)
            stepIndex += 1
        }
    }

    private func stopIslandTest() {
        islandTimer?.invalidate()
        islandTimer = nil
        EvoActivityManager.shared.cancel()
        isTestingIsland = false
        islandProgress = 0
    }

    // MARK: - 远程日志

    private func fetchLogs() {
        isLoading = true
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        logVersion = "EVO v\(appVersion)"
        let logs = DiagAgent.shared.recentLogs(30)
        if logs.isEmpty {
            recentLogs = "暂无日志记录"
        } else {
            recentLogs = logs.map { "[\($0.lvl)] \($0.msg)" }.joined(separator: "\n")
        }
        isLoading = false
    }
}