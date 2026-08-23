import SwiftUI

/// TURN 服务器配置（Cloudflare Calls / coturn）
/// 开通 Cloudflare Calls：https://dash.cloudflare.com → Realtime → 创建 TURN 凭据
struct TurnConfigView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var turnURL = ""
    @State private var turnUser = ""
    @State private var turnPass = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("turn:turn.cloudflare.com:3478", text: $turnURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("用户名", text: $turnUser)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("密码", text: $turnPass)
                } header: {
                    Text("TURN 服务器")
                } footer: {
                    Text("用于 WebRTC 通话 P2P 失败时兜底转发。开通 Cloudflare Calls 后在面板创建 TURN 凭据，将 URL/用户名/密码填到这里。")
                }
            }
            .navigationTitle("TURN 配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        UserDefaults.standard.set(turnURL.trimmingCharacters(in: .whitespaces), forKey: "turn_url")
                        UserDefaults.standard.set(turnUser.trimmingCharacters(in: .whitespaces), forKey: "turn_user")
                        UserDefaults.standard.set(turnPass, forKey: "turn_pass")
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            turnURL = UserDefaults.standard.string(forKey: "turn_url") ?? ""
            turnUser = UserDefaults.standard.string(forKey: "turn_user") ?? ""
            turnPass = UserDefaults.standard.string(forKey: "turn_pass") ?? ""
        }
    }
}
