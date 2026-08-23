import SwiftUI
import UIKit

/// 我的页（设置）
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var profile = ProfileStore.shared
    @State private var showAutoDelete = false
    @State private var showRecoveryKey = false
    @State private var showRestore = false
    @State private var restoreInput = ""
    @State private var restoreResult: String? = nil
    @State private var showMyQr = false
    @State private var webURL: URL?
    @State private var showSessionPicker = false
    @State private var showStorageManager = false
    @State private var showProfileEdit = false

    var body: some View {
        List {
            // 个人资料卡片
            Section {
                Button {
                    showProfileEdit = true
                } label: {
                    HStack(spacing: 14) {
                        if let img = ProfileStore.shared.myAvatarImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(Circle())
                        } else {
                            LivingAvatarBubble(state: .idle, size: 56)
                                .frame(width: 56, height: 56)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ProfileStore.shared.myProfile.name.isEmpty ? appState.deviceName : ProfileStore.shared.myProfile.name)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text(ProfileStore.shared.myProfile.signature.isEmpty ? "这个人很懒，什么都没写~" : ProfileStore.shared.myProfile.signature)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            Text("唯一 ID: \(String(appState.deviceId.prefix(8)))")
                                .font(.caption2.monospaced())
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(Color(UIColor.tertiaryLabel))
                    }
                }
                .buttonStyle(.plain)
            }

            // 外观
            Section {
                Picker("外观", selection: themeModeBinding) {
                    Text("跟随系统").tag("system")
                    Text("珍珠白").tag("light")
                    Text("深邃黑").tag("dark")
                }
                .pickerStyle(.inline)
            } header: {
                Text("外观")
            }

            // 设备与通用
            Section {
                Button {
                    _ = DeviceIdentity.shared.rerollName()
                    appState.objectWillChange.send()
                } label: {
                    SettingsRowLabel(icon: "pencil", title: "设备名称", subtitle: appState.deviceName)
                }
                SettingsRowLabel(icon: "battery.100percent", title: "后台保活", subtitle: "前台保活 · 电池优化白名单")
                Button {
                    showSessionPicker = true
                } label: {
                    SettingsRowLabel(icon: "link", title: "连接保持", subtitle: SessionDuration.current.label)
                }
                SettingsRowLabel(icon: "server.rack", title: "中继服务器", subtitle: "已配置 · \(PublicRelay.httpURL)")
                Button {
                    showAutoDelete = true
                } label: {
                    SettingsRowLabel(icon: "clock.arrow.circlepath", title: "自动删除消息",
                                     subtitle: {
                                         let days = UserDefaults.standard.integer(forKey: "auto_delete_days")
                                         return days == 0 ? "不自动删除" : "保留 \(days) 天"
                                     }())
                }
                SettingsRowLabel(icon: "text.bubble", title: "反馈", subtitle: "问题与建议")
            } header: {
                Text("设备与通用")
            }

            // 存储
            Section {
                Button {
                    showStorageManager = true
                } label: {
                    SettingsRowLabel(icon: "internaldrive", title: "存储管理", subtitle: "分类占用 · 清理缓存")
                }
            } header: {
                Text("存储")
            }

            // 身份
            Section {
                Button {
                    showRecoveryKey = true
                } label: {
                    SettingsRowLabel(icon: "key", title: "恢复密钥", subtitle: "保存此密钥，换机可恢复身份")
                }
                Button {
                    showRestore = true
                } label: {
                    SettingsRowLabel(icon: "arrow.clockwise.circle", title: "恢复身份", subtitle: "输入恢复密钥找回身份")
                }
            } header: {
                Text("身份")
            }

            // 关于
            Section {
                SettingsRowLabel(icon: "iphone", title: "版本", subtitle: "v1.0.0 · iOS")
                Button {
                    openWeb("https://vios.top/")
                } label: {
                    SettingsRowLabel(icon: "globe", title: "官网", subtitle: "vios.top")
                }
                Button {
                    openWeb("https://linktr.vios.top/")
                } label: {
                    SettingsRowLabel(icon: "person.crop.circle.badge.questionmark", title: "开发者信息", subtitle: "linktr.vios.top")
                }
                Button {
                    if let url = URL(string: "mailto:EVO@vios.top") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    SettingsRowLabel(icon: "envelope", title: "邮箱", subtitle: "EVO@vios.top")
                }
            } header: {
                Text("关于")
            }
        }
        .listStyle(.insetGrouped)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        // 我的二维码：当前页面直接全屏打开（不跳转）
        .fullScreenCover(isPresented: $showMyQr) {
            MyQrCodeView()
        }
        // 官网/开发者信息：应用内打开（不跳出 Safari）
        .fullScreenCover(item: $webURL) { url in
            SafariView(url: url)
        }
        // 存储管理
        .sheet(isPresented: $showStorageManager) {
            StorageManagerView()
        }
        // 个人资料编辑
        .sheet(isPresented: $showProfileEdit) {
            ProfileEditView()
        }
        // 恢复密钥展示
        .alert("恢复密钥", isPresented: $showRecoveryKey) {
            Button("复制") {
                UIPasteboard.general.string = DeviceIdentity.shared.recoveryKey
            }
            Button("完成", role: .cancel) {}
        } message: {
            Text("""
            请保存此密钥（换机或重装时输入可恢复身份）：

            \(DeviceIdentity.shared.recoveryKey)
            """)
        }
        // 恢复身份
        .alert("恢复身份", isPresented: $showRestore) {
            TextField("输入恢复密钥", text: $restoreInput)
            Button("恢复") {
                if DeviceIdentity.shared.restore(fromRecoveryKey: restoreInput) {
                    restoreResult = "✅ 身份已恢复\n新 ID: \(DeviceIdentity.shared.shortId)\n请重新添加好友"
                } else {
                    restoreResult = "❌ 恢复密钥无效"
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(restoreResult ?? "输入之前保存的恢复密钥")
        }
        // 连接保持时长选择
        .confirmationDialog("连接保持时长", isPresented: $showSessionPicker, titleVisibility: .visible) {
            ForEach(SessionDuration.allCases, id: \.rawValue) { d in
                Button(d.label) {
                    UserDefaults.standard.set(d.rawValue, forKey: "session_duration_hours")
                    appState.objectWillChange.send()
                }
            }
            Button("取消", role: .cancel) {}
        }
        // 自动删除天数选择
        .confirmationDialog("自动删除消息", isPresented: $showAutoDelete, titleVisibility: .visible) {
            Button("不自动删除") { setAutoDelete(0) }
            Button("1 天") { setAutoDelete(1) }
            Button("7 天") { setAutoDelete(7) }
            Button("30 天") { setAutoDelete(30) }
            Button("90 天") { setAutoDelete(90) }
            Button("取消", role: .cancel) {}
        }
    }

    private func setAutoDelete(_ days: Int) {
        UserDefaults.standard.set(days, forKey: "auto_delete_days")
        appState.applyAutoDelete()
    }

    /// 应用内打开网页（不跳出 Safari）
    private func openWeb(_ urlString: String) {
        if let url = URL(string: urlString) {
            webURL = url
        }
    }

    private var themeModeBinding: Binding<String> {
        Binding(
            get: { UserDefaults.standard.string(forKey: "theme_mode") ?? "system" },
            set: { applyThemeMode($0) }
        )
    }

    private func applyThemeMode(_ mode: String) {
        UserDefaults.standard.set(mode, forKey: "theme_mode")
        AppTheme.apply(mode, systemDark: UITraitCollection.current.userInterfaceStyle == .dark)
        NotificationCenter.default.post(name: Notification.Name("EVOThemeChanged"), object: nil)
    }
}

/// 设置行标签（SF Symbol + 标题 + 副标题）
struct SettingsRowLabel: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .frame(width: 24)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.body)
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}


