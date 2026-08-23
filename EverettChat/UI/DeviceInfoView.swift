import SwiftUI

/// 设备信息页：设备名称修改 + 唯一 ID + 后台保活 + 中继服务器
struct DeviceInfoView: View {
    @State private var nameInput = DeviceIdentity.shared.deviceName
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    var body: some View {
        List {
            // 设备名称
            Section {
                TextField("设备名称", text: $nameInput)
                    .font(.body)
                Button("随机生成一个") {
                    nameInput = DeviceIdentity.shared.rerollName()
                }
                .font(.subheadline)
                .foregroundColor(Theme.primary)
            } header: {
                Text("设备名称")
            } footer: {
                Text("设备名称用于在其它设备上显示。可随时修改，不影响唯一 ID。")
            }

            // 唯一 ID
            Section {
                LabeledContent("唯一 ID", value: String(appState.deviceId.prefix(8)))
                LabeledContent("完整 ID", value: appState.deviceId)
                    .font(.caption2.monospaced())
            } header: {
                Text("身份标识")
            }

            // 中继服务器
            Section {
                LabeledContent("中继地址", value: PublicRelay.httpURL)
                LabeledContent("WebSocket", value: PublicRelay.wsURL)
            } header: {
                Text("中继服务器")
            } footer: {
                Text("所有消息经端到端加密后通过中继转发。")
            }
        }
        .navigationTitle("设备与通用")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") {
                    DeviceIdentity.shared.setName(nameInput)
                    appState.objectWillChange.send()
                    dismiss()
                }
            }
        }
    }
}

extension DeviceIdentity {
    /// 自定义设备名（写入 customNameKey）
    func setName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmed.isEmpty ? deviceName : trimmed, forKey: "everett_custom_name")
    }
}