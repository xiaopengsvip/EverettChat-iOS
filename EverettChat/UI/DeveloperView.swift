import SwiftUI

/// 开发者设置页（调试模式 / 调试通道 / 远程日志）
struct DeveloperView: View {
    @AppStorage("debug_mode") private var debugMode = false
    @State private var recentLogs: String = "点击「获取日志」查看最近日志"
    @State private var logVersion: String = ""
    @State private var isLoading = false

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
        }
        .navigationTitle("开发者")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func fetchLogs() {
        isLoading = true
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        logVersion = "EVO v\(appVersion)"
        // 取本机 DiagAgent 日志缓冲
        let logs = DiagAgent.shared.recentLogs(count: 30)
        if logs.isEmpty {
            recentLogs = "暂无日志记录"
        } else {
            recentLogs = logs.map { "[\($0.lvl)] \($0.msg)" }.joined(separator: "\n")
        }
        isLoading = false
    }
}