import SwiftUI
import ActivityKit

/// 开发者设置页（调试模式 / 调试通道 / 远程日志 / 测试工具）
struct DeveloperView: View {
    @AppStorage("debug_mode") private var debugMode = false
    @State private var recentLogs: String = "点击「获取日志」查看最近日志"
    @State private var logVersion: String = ""
    @State private var isLoading = false

    // 启动封面测试
    @State private var splashDelay: Double = 5.0        // 默认 5 秒
    @State private var showSplashTest = false            // 是否显示封面

    // 灵动岛测试
    @State private var isTestingIsland = false           // 是否正在测试
    @State private var islandProgress: Double = 0        // 测试进度
    @State private var islandTimer: Timer?

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
                            Text("当前设备不支持灵动岛 / Live Activity")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }

                    if isTestingIsland {
                        // 测试中：显示进度
                        HStack(spacing: 12) {
                            ProgressView(value: islandProgress, total: 1.0)
                                .tint(Theme.primary)
                            Text("\(Int(islandProgress * 100))%")
                                .font(.caption.monospaced())
                                .foregroundColor(Theme.textSecondary)
                                .frame(width: 36)
                        }

                        HStack {
                            Button(role: .destructive) {
                                stopIslandTest()
                            } label: {
                                Label("结束测试", systemImage: "xmark.circle.fill")
                                    .font(.subheadline)
                            }
                        }
                    } else {
                        Button {
                            startIslandTest()
                        } label: {
                            Label("开始测试灵动岛", systemImage: "iphone.radiowaves.left.and.right")
                                .font(.subheadline)
                        }
                        .disabled(!EvoActivityManager.shared.isSupported)
                    }
                }
            } header: {
                Text("测试灵动岛")
            } footer: {
                Text("点击「开始测试」后，灵动岛会显示 AI 任务进度动画，模拟 step 1→5 后自动结束。可在锁屏查看效果。")
            }

            // MARK: - 测试启动封面
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    // 延迟时间设置
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
                        // 延迟后自动关闭
                        DispatchQueue.main.asyncAfter(deadline: .now() + splashDelay) {
                            if showSplashTest { showSplashTest = false }
                        }
                    } label: {
                        Label("显示启动封面 (\(Int(splashDelay)) 秒)", systemImage: "photo.fill")
                            .font(.subheadline)
                    }
                }
            } header: {
                Text("测试启动封面")
            } footer: {
                Text("点击后全屏显示启动封面图（launch_cover），\(Int(splashDelay)) 秒后自动消失。可调延迟时间（1-15 秒），便于观察封面效果。")
            }
        }
        .navigationTitle("开发者")
        .navigationBarTitleDisplayMode(.inline)
        // 启动封面测试 overlay
        .overlay(splashTestOverlay)
        // 页面消失时清理定时器（避免泄漏/重复触发）
        .onDisappear {
            islandTimer?.invalidate()
            islandTimer = nil
        }
    }

    // MARK: - 启动封面测试 overlay
    @ViewBuilder
    private var splashTestOverlay: some View {
        if showSplashTest {
            ZStack {
                Color(red: 0.039, green: 0.039, blue: 0.071) // #0A0A12 同启动封面背景
                    .ignoresSafeArea()

                Image("launch_cover")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()

                // 右上角：倒计时 + 关闭按钮
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            showSplashTest = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.white.opacity(0.7))
                                .padding(16)
                        }
                    }
                    Spacer()
                }

                // 底部：倒计时文字
                VStack {
                    Spacer()
                    Text("启动封面 (测试) · \(Int(splashDelay)) 秒后自动消失")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.bottom, 40)
                }
            }
            .transition(.opacity)
        }
    }

    // MARK: - 灵动岛测试

    private func startIslandTest() {
        isTestingIsland = true
        islandProgress = 0

        // 启动 Live Activity（AI 任务模式）
        EvoActivityManager.shared.start(sessionId: "test-\(Date().timeIntervalSince1970)", peerName: "灵动岛测试")

        // 模拟进度：step 1~5，每 0.8 秒更新一次（工具名纯文字，无 emoji）
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
                // 结束测试
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